const FileWatcher = @This();
const std = @import("std");

notify_fd: std.os.fd_t,
watch_fds: std.AutoHashMapUnmanaged(std.os.fd_t, WatchEntry) = .{},

const WatchEntry = struct {
    dir_path: []const u8,
    parent_watch_fd: std.os.fd_t,
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    var fw = try FileWatcher.init();
    try fw.addDir(gpa, "test/");
    try fw.listen();
}

pub fn init() !FileWatcher {
    const notify_fd = try std.os.inotify_init1(0);
    return .{ .notify_fd = notify_fd };
}

const Mode = enum {
    // For when you don't need to build full paths for this subtree
    // (avoids storing the dirname and associated watch fd)
    bulk,
    // Stores fd and dir name in a hashmap to be able to rebuild
    // full paths from events.
    precise,
};
pub fn addTree(
    self: *FileWatcher,
    gpa: std.mem.Allocator,
    mode: Mode,
    root_dir_path: []const u8,
) !void {
    const parent_watch_fd = switch (mode) {
        .bulk => -1,
        .precise => 0,
    };
    return self.addTreeInternal(gpa, root_dir_path, parent_watch_fd);
}

const DirStackEntry = struct {
    dir: std.fs.Dir,
    watch_entry: *WatchEntry,
};
fn addTreeInternal(
    self: *FileWatcher,
    gpa: std.mem.Allocator,
    root_dir_path: []const u8,
    parent_watch_fd: std.os.fd_t,
) !void {
    _ = parent_watch_fd;
    const root_dir = try std.fs.cwd().openDir(root_dir_path, .{ .iterate = true });
    var dir_stack = std.ArrayList(DirStackEntry).init(self.gpa);
    const root_watch_entry = try self.addDir(
        gpa,
        root_dir_path,
    );
    try dir_stack.append(.{
        .dir = root_dir,
        .watch_entry = root_watch_entry,
    });

    while (dir_stack.popOrNull()) |dir_entry| {
        var dir = dir_entry.dir;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |sub_entry| {
            switch (sub_entry.kind) {
                else => continue,
                .directory => {
                    const sub_watch_entry = try self.addDir(
                        gpa,
                        root_dir_path,
                        dir_entry.watch_entry,
                    );
                    _ = sub_watch_entry;
                    try dir_stack.append(.{
                        .dir = try dir.openDir(sub_entry.name, .{
                            .iterate = true,
                        }),
                        .entry = sub_entry,
                    });
                },
            }
        }
    }
}

fn addDir(
    self: *FileWatcher,
    gpa: std.mem.Allocator,
    mode: Mode,
    dir_path: []const u8,
    parent_watch_fd: std.os.fd_t,
) !void {
    _ = parent_watch_fd;
    const mask = Mask.all(&.{
        .IN_ONLYDIR,
        .IN_MODIFY,
        .IN_MOVE,
        .IN_CREATE,
        .IN_DELETE,
        .IN_EXCL_UNLINK,
    });
    const watch_fd = try std.os.inotify_add_watch(
        self.notify_fd,
        dir_path,
        mask,
    );
    if (mode == .precise) try self.dir_fds.put(gpa, watch_fd, dir_path);

    std.debug.print("added {s} -> {}\n", .{ dir_path, watch_fd });
}

pub fn listen(self: *FileWatcher) !void {
    const Event = std.os.linux.inotify_event;
    const event_size = @sizeOf(Event);
    while (true) {
        var buffer: [event_size * 10]u8 = undefined;
        const len = try std.os.read(self.notify_fd, &buffer);
        std.debug.print("read {}\n", .{len});
        if (len < 0) {
            @panic("read error");
        }
        var event_data = buffer[0..len];
        while (event_data.len > 0) {
            const event: *Event = @alignCast(@ptrCast(event_data[0..event_size]));
            std.debug.print("event: {?s}\n", .{event.getName()});
            event_data = event_data[event_size + event.len ..];
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

    pub fn all(comptime flags: []const std.meta.DeclEnum(Mask)) u32 {
        var result: u32 = 0;
        inline for (flags) |f| result |= @field(Mask, @tagName(f));
        return result;
    }
};
