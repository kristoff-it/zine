const FileWatcher = @This();
const std = @import("std");
const ws = @import("ws");

const log = std.log.scoped(.watcher);

gpa: std.mem.Allocator,
out_dir_path: []const u8,
notify_fd: std.os.fd_t,
watch_fds: std.AutoHashMapUnmanaged(std.os.fd_t, WatchEntry) = .{},
ws_server: ws.Server,

clients_lock: std.Thread.Mutex = .{},
clients: std.AutoArrayHashMapUnmanaged(*ws.Conn, void) = .{},

const WatchEntry = struct {
    dir_path: []const u8,
    kind: TreeKind,

    const TreeKind = enum { input, output };
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    var fw = try FileWatcher.init();
    try fw.addTree(gpa, "test/");
    try fw.listen(gpa);
}

pub fn init(gpa: std.mem.Allocator, out_dir_path: []const u8) !FileWatcher {
    const notify_fd = try std.os.inotify_init1(0);
    const ws_server = try ws.Server.init(gpa, .{});

    var self: FileWatcher = .{
        .gpa = gpa,
        .out_dir_path = out_dir_path,
        .notify_fd = notify_fd,
        .ws_server = ws_server,
    };

    try self.addTree(.output, out_dir_path);
    return self;
}

pub fn addInputTree(self: *FileWatcher, root_dir_path: []const u8) !void {
    return self.addTree(.input, root_dir_path);
}

fn addTree(
    self: *FileWatcher,
    tree_kind: WatchEntry.TreeKind,
    root_dir_path: []const u8,
) !void {
    const root_dir = try std.fs.cwd().openDir(root_dir_path, .{ .iterate = true });
    try self.addDir(tree_kind, root_dir_path);

    var it = try root_dir.walk(self.gpa);
    while (try it.next()) |entry| switch (entry.kind) {
        else => continue,
        .directory => {
            const dir_path = try std.fs.path.join(self.gpa, &.{ root_dir_path, entry.path });
            try self.addDir(tree_kind, dir_path);
        },
    };
}

fn addDir(
    self: *FileWatcher,
    tree_kind: WatchEntry.TreeKind,
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
    try self.watch_fds.put(self.gpa, watch_fd, .{
        .dir_path = dir_path,
        .kind = tree_kind,
    });
    log.debug("added {s} -> {}", .{ dir_path, watch_fd });
}

pub fn listen(self: *FileWatcher) !void {
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
                    const dir_path = try std.fs.path.join(self.gpa, &.{
                        parent.dir_path,
                        dir_name,
                    });

                    log.debug("ISDIR CREATE {s}", .{dir_path});

                    try self.addTree(parent.kind, dir_path);
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
                            log.debug("re-building!", .{});
                            const result = try std.ChildProcess.run(.{
                                .allocator = self.gpa,
                                .argv = &.{ "zig", "build" },
                            });
                            defer {
                                self.gpa.free(result.stdout);
                                self.gpa.free(result.stderr);
                            }

                            if (result.stdout.len > 0) {
                                log.info("zig build stdout: {s}", .{result.stdout});
                            }
                            if (result.stderr.len > 0) {
                                log.info("zig build stderr: {s}", .{result.stderr});
                            }
                        },
                        .output => {
                            const name = event.getName() orelse continue;
                            if (std.mem.indexOfScalar(u8, name, '.') == null) {
                                continue;
                            }
                            log.debug("re-load: {s}/{s}!", .{
                                parent.dir_path,
                                name,
                            });

                            self.clients_lock.lock();
                            defer self.clients_lock.unlock();

                            var idx: usize = 0;
                            while (idx < self.clients.entries.len) {
                                const conn = self.clients.entries.get(idx).key;

                                const msg_fmt =
                                    \\{{
                                    \\  "command":"reload",
                                    \\  "path":"{s}/{s}",
                                    \\  "originalPath":"",
                                    \\  "liveCSS":true,
                                    \\  "liveImg":true
                                    \\}}
                                ;

                                var buf: [4096]u8 = undefined;
                                const msg = try std.fmt.bufPrint(&buf, msg_fmt, .{
                                    parent.dir_path[self.out_dir_path.len..],
                                    name,
                                });

                                conn.write(msg) catch |err| {
                                    log.debug("error writing to websocket: {s}", .{
                                        @errorName(err),
                                    });
                                    self.clients.swapRemoveAt(idx);
                                    continue;
                                };

                                idx += 1;
                            }
                        },
                    }
                }
            }
        }
    }
}

pub fn handleWs(self: *FileWatcher, res: *std.http.Server.Response) !void {
    errdefer res.deinit();

    var h: [20]u8 = undefined;

    const key = res.request.headers.getFirstValue("sec-websocket-key") orelse {
        std.debug.print("couldn't find key header!\n", .{});
        return;
    };

    var buf =
        ("HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: upgrade\r\n" ++
        "Sec-Websocket-Accept: 0000000000000000000000000000\r\n\r\n").*;

    const key_pos = buf.len - 32;

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key);
    hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    hasher.final(&h);

    _ = std.base64.standard.Encoder.encode(buf[key_pos .. key_pos + 28], h[0..]);

    const stream = res.connection.stream;
    try stream.writeAll(&buf);

    var conn = self.ws_server.newConn(stream);
    var context: Handler.Context = .{ .watcher = self };
    var handler = try Handler.init(undefined, &conn, &context);
    self.ws_server.handle(Handler, &handler, &conn);
}

const Handler = struct {
    conn: *ws.Conn,
    context: *Context,

    const Context = struct {
        watcher: *FileWatcher,
    };

    pub fn init(h: ws.Handshake, conn: *ws.Conn, context: *Context) !Handler {
        _ = h; // we're not using this in our simple case

        return Handler{
            .conn = conn,
            .context = context,
        };
    }

    pub fn handle(self: *Handler, message: ws.Message) !void {
        const data = message.data;
        const gpa = self.context.watcher.gpa;

        log.debug("ws message: {s}\n", .{data});

        if (std.mem.indexOf(u8, data, "\"command\":\"hello\"")) |_| {
            try self.conn.write(
                \\{
                \\  "command": "hello",
                \\  "protocols": [ "http://livereload.com/protocols/official-7" ],
                \\  "serverName": "Zine"
                \\}
            );

            const watcher = self.context.watcher;
            watcher.clients_lock.lock();
            defer watcher.clients_lock.unlock();
            try watcher.clients.put(gpa, self.conn, {});
        }
    }

    pub fn close(self: *Handler) void {
        log.debug("ws connection was closed\n", .{});
        const watcher = self.context.watcher;
        watcher.clients_lock.lock();
        defer watcher.clients_lock.unlock();
        _ = watcher.clients.swapRemove(self.conn);
    }
};

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
