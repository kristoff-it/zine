const LinuxWatcher = @This();

const std = @import("std");
const Reloader = @import("../Reloader.zig");

const log = std.log.scoped(.watcher);

notify_fd: std.os.fd_t,
watch_fds: std.AutoHashMapUnmanaged(std.os.fd_t, WatchEntry) = .{},

const TreeKind = enum { input, output };
const WatchEntry = struct {
    dir_path: []const u8,
    kind: TreeKind,
};

pub fn init(
    gpa: std.mem.Allocator,
    out_dir_path: []const u8,
    in_dir_paths: []const []const u8,
) !LinuxWatcher {
    const notify_fd = try std.os.inotify_init1(0);
    var self: LinuxWatcher = .{ .notify_fd = notify_fd };
    try self.addTree(gpa, .output, out_dir_path);
    for (in_dir_paths) |p| try self.addTree(gpa, .input, p);
    return self;
}

fn addTree(
    self: *LinuxWatcher,
    gpa: std.mem.Allocator,
    tree_kind: TreeKind,
    root_dir_path: []const u8,
) !void {
    const root_dir = try std.fs.cwd().openDir(root_dir_path, .{ .iterate = true });
    try self.addDir(gpa, tree_kind, root_dir_path);

    var it = try root_dir.walk(gpa);
    while (try it.next()) |entry| switch (entry.kind) {
        else => continue,
        .directory => {
            const dir_path = try std.fs.path.join(gpa, &.{ root_dir_path, entry.path });
            try self.addDir(gpa, tree_kind, dir_path);
        },
    };
}

fn addDir(
    self: *LinuxWatcher,
    gpa: std.mem.Allocator,
    tree_kind: TreeKind,
    dir_path: []const u8,
) !void {
    const mask = Mask.all(&.{
        .IN_ONLYDIR,     .IN_CLOSE_WRITE,
        .IN_MOVE,        .IN_DELETE,
        .IN_EXCL_UNLINK,
    });
    const watch_fd = try std.os.inotify_add_watch(
        self.notify_fd,
        dir_path,
        mask,
    );
    try self.watch_fds.put(gpa, watch_fd, .{
        .dir_path = dir_path,
        .kind = tree_kind,
    });
    log.debug("added {s} -> {}", .{ dir_path, watch_fd });
}

pub fn listen(
    self: *LinuxWatcher,
    gpa: std.mem.Allocator,
    reloader: *Reloader,
) !void {
    const Event = std.os.linux.inotify_event;
    const event_size = @sizeOf(Event);
    while (true) {
        var buffer: [event_size * 10]u8 = undefined;
        const len = try std.os.read(self.notify_fd, &buffer);
        if (len < 0) @panic("notify fd read error");

        var event_data = buffer[0..len];
        while (event_data.len > 0) {
            const event: *Event = @alignCast(@ptrCast(event_data[0..event_size]));
            const parent = self.watch_fds.get(event.wd).?;
            event_data = event_data[event_size + event.len ..];

            // std.debug.print("flags: ", .{});
            // Mask.debugPrint(event.mask);
            // std.debug.print("for {s}/{s}\n", .{ parent.dir_path, event.getName().? });

            if (Mask.is(event.mask, .IN_ISDIR)) {
                if (Mask.is(event.mask, .IN_CREATE)) {
                    const dir_name = event.getName().?;
                    const dir_path = try std.fs.path.join(gpa, &.{
                        parent.dir_path,
                        dir_name,
                    });

                    log.debug("ISDIR CREATE {s}", .{dir_path});

                    try self.addTree(gpa, parent.kind, dir_path);
                    continue;
                }

                if (Mask.is(event.mask, .IN_MOVE)) {
                    @panic("TODO: implement support for moving directories");
                }
            } else {
                if (Mask.is(event.mask, .IN_CLOSE_WRITE) or
                    Mask.is(event.mask, .IN_MOVED_TO))
                {
                    switch (parent.kind) {
                        .input => {
                            const name = event.getName() orelse continue;
                            reloader.onInputChange(parent.dir_path, name);
                        },
                        .output => {
                            const name = event.getName() orelse continue;
                            reloader.onOutputChange(parent.dir_path, name);
                        },
                    }
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
