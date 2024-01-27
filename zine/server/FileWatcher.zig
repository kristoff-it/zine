const FileWatcher = @This();
const std = @import("std");

epoll_fd: std.os.fd_t,
notify_fd: std.os.fd_t,
dir_fds: std.AutoHashMapUnmanaged(std.os.fd_t, []const u8),

pub fn init() !FileWatcher {
    const notify_fd = try std.os.inotify_init1(0);
    const epoll_fd = try std.os.epoll_create1(0);
    return .{
        .notify_fd = notify_fd,
        .epoll_fd = epoll_fd,
    };
}

pub fn addDir(self: *FileWatcher, dir_path: []const u8) !void {
    const mask = Mask.all(
        .IN_ONLYDIR,
        .IN_MODIFY,
        .IN_MOVE,
        .IN_CREATE,
        .IN_DELETE,
        .IN_EXCL_UNLINK,
    );
    const watch_fd = try std.os.inotify_add_watch(self.notify_fd, dir_path, mask);
    try self.notify_fds.put(dir_path, watch_fd);
}

pub fn listen(self: *FileWatcher) !void {}

const Mask = struct {
    const IN_ACCESS = 0x00000001;
    const IN_MODIFY = 0x00000002;
    const IN_ATTRIB = 0x00000004;
    const IN_CLOSE_WRITE = 0x00000008;
    const IN_CLOSE_NOWRITE = 0x00000010;
    const IN_CLOSE = (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);
    const IN_OPEN = 0x00000020;
    const IN_MOVED_FROM = 0x00000040;
    const IN_MOVED_TO = 0x00000080;
    const IN_MOVE = (IN_MOVED_FROM | IN_MOVED_TO);
    const IN_CREATE = 0x00000100;
    const IN_DELETE = 0x00000200;
    const IN_DELETE_SELF = 0x00000400;
    const IN_MOVE_SELF = 0x00000800;
    const IN_ALL_EVENTS = 0x00000fff;

    const IN_UNMOUNT = 0x00002000;
    const IN_Q_OVERFLOW = 0x00004000;
    const IN_IGNORED = 0x00008000;

    const IN_ONLYDIR = 0x01000000;
    const IN_DONT_FOLLOW = 0x02000000;
    const IN_EXCL_UNLINK = 0x04000000;
    const IN_MASK_CREATE = 0x10000000;
    const IN_MASK_ADD = 0x20000000;

    const IN_ISDIR = 0x40000000;
    const IN_ONESHOT = 0x80000000;

    pub fn all(comptime flags: []std.meta.DeclEnum(Mask)) u32 {
        var result: u32 = 0;
        for (flags) |f| result |= @field(Mask, @tagName(f));
        return result;
    }
};
