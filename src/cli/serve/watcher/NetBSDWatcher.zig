const NetBSDWatcher = @This();

const std = @import("std");
const Io = std.Io;
const fatal = @import("../../../fatal.zig");
const Debouncer = @import("../../serve.zig").Debouncer;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.watcher);

const KEvent = extern struct {
    ident: usize,
    filter: i16,
    flags: u16,
    fflags: u32,
    data: i64,
    udata: usize,
};

const EVFILT_VNODE: i16 = -4;
const EV_ADD: u16 = 0x0001;
const EV_ENABLE: u16 = 0x0002;
const EV_CLEAR: u16 = 0x0010;
const NOTE_WRITE: u32 = 0x00000002;
const NOTE_DELETE: u32 = 0x00000001;
const NOTE_RENAME: u32 = 0x00000008;
const NOTE_EXTEND: u32 = 0x00000004;

const timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

extern "c" fn kqueue() c_int;
extern "c" fn kevent(kq: c_int, changelist: ?[*]const KEvent, nchanges: c_int, eventlist: ?[*]KEvent, nevents: c_int, timeout: ?*const timespec) c_int;

io: Io,
gpa: Allocator,
debouncer: *Debouncer,
dir_paths: []const []const u8,

kq: std.posix.fd_t = -1,

pub fn init(
    io_: Io,
    gpa_: Allocator,
    debouncer_: *Debouncer,
    dir_paths_: []const []const u8,
) NetBSDWatcher {
    const kq = kqueue();
    if (kq < 0) fatal.msg("error: unable to create kqueue", .{});
    return .{
        .io = io_,
        .gpa = gpa_,
        .debouncer = debouncer_,
        .dir_paths = dir_paths_,
        .kq = kq,
    };
}

pub fn start(watcher: *NetBSDWatcher) !void {
    const t = try std.Thread.spawn(.{}, NetBSDWatcher.listen, .{watcher});
    t.detach();
}

pub fn listen(watcher: *NetBSDWatcher) !void {
    var watch_fds: std.AutoHashMapUnmanaged(std.posix.fd_t, void) = .{};
    defer watch_fds.deinit(watcher.gpa);

    for (watcher.dir_paths) |dir_path| {
        addWatch(watcher, dir_path, &watch_fds) catch |err| {
            log.err("failed to watch {s}: {s}", .{ dir_path, @errorName(err) });
        };
    }

    var events: [32]KEvent = undefined;
    while (true) {
        const nev = kevent(watcher.kq, null, 0, &events, @intCast(events.len), null);
        if (nev < 0) {
            log.err("kevent error", .{});
            continue;
        }

        var changed = false;
        for (events[0..@intCast(nev)]) |ev| {
            if (ev.filter == EVFILT_VNODE) {
                if (ev.fflags & NOTE_WRITE != 0 or
                    ev.fflags & NOTE_DELETE != 0 or
                    ev.fflags & NOTE_RENAME != 0 or
                    ev.fflags & NOTE_EXTEND != 0)
                {
                    changed = true;
                }
            }
        }
        if (changed) {
            watcher.debouncer.newEvent();
        }
    }
}

fn addWatch(
    watcher: *NetBSDWatcher,
    dir_path: []const u8,
    watch_fds: *std.AutoHashMapUnmanaged(std.posix.fd_t, void),
) !void {
    const dir = try std.Io.Dir.cwd().openDir(watcher.io, dir_path, .{ .iterate = true });
    defer dir.close(watcher.io);

    const fd = dir.handle;
    if (!watch_fds.contains(fd)) {
        var ev: [1]KEvent = .{.{
            .ident = @intCast(fd),
            .filter = EVFILT_VNODE,
            .flags = EV_ADD | EV_ENABLE | EV_CLEAR,
            .fflags = NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND,
            .data = 0,
            .udata = 0,
        }};
        _ = kevent(watcher.kq, @ptrCast(&ev), 1, null, 0, null);
        try watch_fds.put(watcher.gpa, fd, {});
    }
}

pub fn deinit(watcher: *NetBSDWatcher) void {
    if (watcher.kq != -1) {
        std.posix.close(watcher.kq);
        watcher.kq = -1;
    }
}
