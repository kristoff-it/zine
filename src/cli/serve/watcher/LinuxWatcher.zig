const LinuxWatcher = @This();

const std = @import("std");
const fatal = @import("../../../fatal.zig");
const Debouncer = @import("../../serve.zig").Debouncer;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.watcher);

gpa: Allocator,
debouncer: *Debouncer,

notify_fd: std.posix.fd_t,
/// active watch entries
watch_fds: std.AutoHashMapUnmanaged(std.posix.fd_t, WatchEntry) = .{},
/// direct descendant tracker
children_fds: std.AutoHashMapUnmanaged(
    std.posix.fd_t,
    std.ArrayListUnmanaged(std.posix.fd_t),
) = .{},
/// inotify cookie tracker for move events
cookie_fds: std.AutoHashMapUnmanaged(u32, std.posix.fd_t) = .{},

const WatchEntry = struct {
    dir_path: []const u8,
    name: []const u8,
};

pub fn init(
    gpa: std.mem.Allocator,
    debouncer: *Debouncer,
    dir_paths: []const []const u8,
) LinuxWatcher {
    errdefer |err| fatal.msg("error: unable to start the file watcher: {s}", .{
        @errorName(err),
    });

    const notify_fd = try std.posix.inotify_init1(0);
    var watcher: LinuxWatcher = .{
        .gpa = gpa,
        .notify_fd = notify_fd,
        .debouncer = debouncer,
    };
    for (dir_paths) |p| {
        _ = try watcher.addTree(p);
    }
    return watcher;
}

/// Register `child` with the `parent`
fn addChild(
    watcher: *LinuxWatcher,
    parent: std.posix.fd_t,
    child: std.posix.fd_t,
) !void {
    const gpa = watcher.gpa;
    const children = try watcher.children_fds.getOrPut(gpa, parent);
    if (!children.found_existing) {
        children.value_ptr.* = .{};
    }
    try children.value_ptr.append(gpa, child);
}

/// Remove `child` from the `parent`, if present
fn removeChild(
    self: *LinuxWatcher,
    parent: std.posix.fd_t,
    child: std.posix.fd_t,
) ?std.posix.fd_t {
    if (self.children_fds.getEntry(parent)) |entry| {
        for (0.., entry.value_ptr.items) |i, fd| {
            if (child == fd) {
                return entry.value_ptr.swapRemove(i);
            }
        }
    }
    return null;
}

/// Remove child identified by `name`, if present
fn removeChildByName(
    self: *LinuxWatcher,
    parent: std.posix.fd_t,
    name: []const u8,
) ?std.posix.fd_t {
    if (self.children_fds.getEntry(parent)) |entry| {
        for (0.., entry.value_ptr.items) |i, fd| {
            if (self.watch_fds.get(fd)) |data| {
                if (std.mem.eql(u8, data.name, name)) {
                    return entry.value_ptr.swapRemove(i);
                }
            }
        }
    }
    return null;
}

/// Start tracking directory tree and returns the watch descriptor for `root_dir_path`
/// **NOTE**: caller is expected to register the returned watch fd as a child
fn addTree(
    watcher: *LinuxWatcher,
    root_dir_path: []const u8,
) !std.posix.fd_t {
    const gpa = watcher.gpa;

    var root_dir = try std.fs.openDirAbsolute(root_dir_path, .{
        .iterate = true,
    });
    defer root_dir.close();

    const parent_fd = try watcher.addDir(root_dir_path);

    // tracker for fds associated with dir paths
    // helps to track children within a recursive walk
    var lookup = std.StringHashMap(std.posix.fd_t).init(gpa);
    defer lookup.deinit();

    try lookup.put(root_dir_path, parent_fd);

    var it = try root_dir.walk(gpa);
    while (try it.next()) |entry| switch (entry.kind) {
        else => continue,
        .directory => {
            const dir_path = try std.fs.path.join(gpa, &.{
                root_dir_path,
                entry.path,
            });
            const dir_fd = try watcher.addDir(dir_path);
            const p_dir = std.fs.path.dirname(dir_path).?;
            const p_fd = lookup.get(p_dir).?;

            try watcher.addChild(p_fd, dir_fd);
            try lookup.put(dir_path, dir_fd);
        },
    };

    return parent_fd;
}

fn addDir(
    watcher: *LinuxWatcher,
    dir_path: []const u8,
) !std.posix.fd_t {
    const gpa = watcher.gpa;
    const mask = Mask.all(&.{
        .IN_ONLYDIR,     .IN_CLOSE_WRITE,
        .IN_MOVE,        .IN_MOVE_SELF,
        .IN_CREATE,      .IN_DELETE,
        .IN_EXCL_UNLINK,
    });
    const watch_fd = try std.posix.inotify_add_watch(
        watcher.notify_fd,
        dir_path,
        mask,
    );
    const name_copy = try gpa.dupe(u8, std.fs.path.basename(dir_path));
    try watcher.watch_fds.put(gpa, watch_fd, .{
        .dir_path = dir_path,
        .name = name_copy,
    });
    log.debug("added {s} -> {}", .{ dir_path, watch_fd });
    return watch_fd;
}

/// Explicitly stop watching a descriptor
/// **NOTE**: should only be called on an active `fd`
fn rmWatch(
    watcher: *LinuxWatcher,
    fd: std.posix.fd_t,
) void {
    if (watcher.children_fds.getEntry(fd)) |entry| {
        for (entry.value_ptr.items) |child_fd| {
            watcher.rmWatch(child_fd);
        }
        watcher.children_fds.removeByPtr(entry.key_ptr);
    }
    std.posix.inotify_rm_watch(watcher.notify_fd, fd);
}

/// Handle the start of the move process
/// Remove `name`-identified fd from children of `from_fd`
/// Register `cookie` for the moved fd for future identification
fn moveDirStart(
    watcher: *LinuxWatcher,
    from_fd: std.posix.fd_t,
    cookie: u32,
    name: []const u8,
) !void {
    const moved_fd = watcher.removeChildByName(from_fd, name).?;

    try watcher.cookie_fds.put(
        watcher.gpa,
        cookie,
        moved_fd,
    );
}

/// Handle the end of the move process and returns the resulting moved fd
/// Register the moved fd as a child of `to_fd`
fn moveDirEnd(
    watcher: *LinuxWatcher,
    to_fd: std.posix.fd_t,
    cookie: u32,
    name: []const u8,
) !std.posix.fd_t {
    const gpa = watcher.gpa;
    const parent = watcher.watch_fds.get(to_fd).?;

    // known cookie - move within watched directories
    if (watcher.cookie_fds.fetchRemove(cookie)) |entry| {
        const moved_fd = entry.value;

        var watch_entry = watcher.watch_fds.getEntry(moved_fd).?.value_ptr;
        gpa.free(watch_entry.name);
        const name_copy = try gpa.dupe(u8, name);
        watch_entry.name = name_copy;

        try watcher.updateDirPath(moved_fd, parent.dir_path);
        try watcher.addChild(to_fd, moved_fd);
        return moved_fd;
    } else { // unknown cookie - move from the outside
        const dir_path = try std.fs.path.join(gpa, &.{ parent.dir_path, name });
        const moved_fd = try watcher.addTree(dir_path);
        try watcher.addChild(to_fd, moved_fd);
        return moved_fd;
    }
}

/// Cascade path updates for `fd` and its children
fn updateDirPath(
    watcher: *LinuxWatcher,
    fd: std.posix.fd_t,
    parent_dir: []const u8,
) !void {
    const gpa = watcher.gpa;
    var data = watcher.watch_fds.getEntry(fd).?.value_ptr;
    gpa.free(data.dir_path);
    const dir_path = try std.fs.path.join(gpa, &.{ parent_dir, data.name });
    data.dir_path = dir_path;

    if (watcher.children_fds.getEntry(fd)) |entry| {
        for (entry.value_ptr.items) |child_fd| {
            try watcher.updateDirPath(child_fd, dir_path);
        }
    }
}

/// Handle the post-move event
/// Remove stale cookie waiting for the `moved_fd`, if present
fn moveDirComplete(
    watcher: *LinuxWatcher,
    moved_fd: std.posix.fd_t,
) !void {
    var it = watcher.cookie_fds.iterator();
    while (it.next()) |entry| {
        // cookie for fd exists - moved outside the watched directory
        if (entry.value_ptr.* == moved_fd) {
            watcher.rmWatch(moved_fd);
            watcher.cookie_fds.removeByPtr(entry.key_ptr);
            break;
        }
    }
}

/// Clean up `fd`-related bookkeeping
/// **NOTE**: expects `fd` to be a no-longer-watched descriptor
fn dropWatch(
    watcher: *LinuxWatcher,
    fd: std.posix.fd_t,
) void {
    const gpa = watcher.gpa;
    if (watcher.watch_fds.fetchRemove(fd)) |entry| {
        gpa.free(entry.value.dir_path);
        gpa.free(entry.value.name);
    }

    var it = watcher.children_fds.keyIterator();
    while (it.next()) |parent_fd| {
        _ = watcher.removeChild(parent_fd.*, fd);
    }

    if (watcher.children_fds.fetchRemove(fd)) |entry| {
        log.warn("Stopping watch for {d} that has known children: {any}", .{ fd, entry.value });
    }
}

pub fn start(watcher: *LinuxWatcher) !void {
    const t = try std.Thread.spawn(.{}, LinuxWatcher.listen, .{watcher});
    t.detach();
}

pub fn listen(watcher: *LinuxWatcher) !void {
    const gpa = watcher.gpa;
    const Event = std.os.linux.inotify_event;
    const event_size = @sizeOf(Event);
    while (true) {
        var buffer: [event_size * 10]u8 = undefined;
        const len = try std.posix.read(watcher.notify_fd, &buffer);
        if (len < 0) @panic("notify fd read error");

        var event_data = buffer[0..len];
        while (event_data.len > 0) {
            const event: *Event = @alignCast(@ptrCast(event_data[0..event_size]));
            const parent = watcher.watch_fds.get(event.wd).?;
            event_data = event_data[event_size + event.len ..];

            // std.debug.print("flags: ", .{});
            // Mask.debugPrint(event.mask);
            // std.debug.print("for {s}/{?s}\n", .{ parent.dir_path, event.getName() });

            if (Mask.is(event.mask, .IN_IGNORED)) {
                log.debug("IGNORE {s}", .{parent.dir_path});
                watcher.dropWatch(event.wd);
                continue;
            } else if (Mask.is(event.mask, .IN_MOVE_SELF)) {
                if (event.getName() == null) {
                    try watcher.moveDirComplete(event.wd);
                }
                continue;
            }

            if (Mask.is(event.mask, .IN_ISDIR)) {
                if (Mask.is(event.mask, .IN_CREATE)) {
                    const dir_name = event.getName().?;
                    const dir_path = try std.fs.path.join(gpa, &.{
                        parent.dir_path,
                        dir_name,
                    });

                    log.debug("ISDIR CREATE {s}", .{dir_path});

                    const new_fd = try watcher.addTree(dir_path);
                    try watcher.addChild(event.wd, new_fd);
                    const data = watcher.watch_fds.get(new_fd).?;
                    _ = data;
                    watcher.debouncer.newEvent();
                    continue;
                } else if (Mask.is(event.mask, .IN_MOVED_FROM)) {
                    log.debug("MOVING {s}/{s}", .{ parent.dir_path, event.getName().? });
                    try watcher.moveDirStart(event.wd, event.cookie, event.getName().?);
                    continue;
                } else if (Mask.is(event.mask, .IN_MOVED_TO)) {
                    log.debug("MOVED {s}/{s}", .{ parent.dir_path, event.getName().? });
                    const moved_fd = try watcher.moveDirEnd(event.wd, event.cookie, event.getName().?);
                    const moved = watcher.watch_fds.get(moved_fd).?;
                    _ = moved;
                    watcher.debouncer.newEvent();
                    continue;
                }
            } else {
                if (Mask.is(event.mask, .IN_CLOSE_WRITE) or
                    Mask.is(event.mask, .IN_MOVED_TO))
                {
                    watcher.debouncer.newEvent();
                }
            }
        }
    }
}

const Mask = struct {
    pub const IN_ACCESS = 0x00000001;
    pub const IN_MODIFY = 0x00000002;
    pub const IN_ATTRIB = 0x00000004;
    pub const IN_CLOSE_WRITE = 0x00000008;
    pub const IN_CLOSE_NOWRITE = 0x00000010;
    pub const IN_CLOSE = (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);
    pub const IN_OPEN = 0x00000020;
    pub const IN_MOVED_FROM = 0x00000040;
    pub const IN_MOVED_TO = 0x00000080;
    pub const IN_MOVE = (IN_MOVED_FROM | IN_MOVED_TO);
    pub const IN_CREATE = 0x00000100;
    pub const IN_DELETE = 0x00000200;
    pub const IN_DELETE_SELF = 0x00000400;
    pub const IN_MOVE_SELF = 0x00000800;
    pub const IN_ALL_EVENTS = 0x00000fff;

    pub const IN_UNMOUNT = 0x00002000;
    pub const IN_Q_OVERFLOW = 0x00004000;
    pub const IN_IGNORED = 0x00008000;

    pub const IN_ONLYDIR = 0x01000000;
    pub const IN_DONT_FOLLOW = 0x02000000;
    pub const IN_EXCL_UNLINK = 0x04000000;
    pub const IN_MASK_CREATE = 0x10000000;
    pub const IN_MASK_ADD = 0x20000000;

    pub const IN_ISDIR = 0x40000000;
    pub const IN_ONESHOT = 0x80000000;

    pub fn is(m: u32, comptime flag: std.meta.DeclEnum(Mask)) bool {
        const f = @field(Mask, @tagName(flag));
        return (m & f) != 0;
    }

    pub fn all(comptime flags: []const std.meta.DeclEnum(Mask)) u32 {
        var result: u32 = 0;
        inline for (flags) |f| result |= @field(Mask, @tagName(f));
        return result;
    }

    pub fn debugPrint(m: u32) void {
        const flags = .{
            .IN_ACCESS,
            .IN_MODIFY,
            .IN_ATTRIB,
            .IN_CLOSE_WRITE,
            .IN_CLOSE_NOWRITE,
            .IN_CLOSE,
            .IN_OPEN,
            .IN_MOVED_FROM,
            .IN_MOVED_TO,
            .IN_MOVE,
            .IN_CREATE,
            .IN_DELETE,
            .IN_DELETE_SELF,
            .IN_MOVE_SELF,
            .IN_ALL_EVENTS,

            .IN_UNMOUNT,
            .IN_Q_OVERFLOW,
            .IN_IGNORED,

            .IN_ONLYDIR,
            .IN_DONT_FOLLOW,
            .IN_EXCL_UNLINK,
            .IN_MASK_CREATE,
            .IN_MASK_ADD,

            .IN_ISDIR,
            .IN_ONESHOT,
        };
        inline for (flags) |f| {
            if (is(m, f)) {
                std.debug.print("{s} ", .{@tagName(f)});
            }
        }
    }
};
