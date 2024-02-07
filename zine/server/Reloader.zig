const Reloader = @This();
const std = @import("std");
const builtin = @import("builtin");
const ws = @import("ws");

const log = std.log.scoped(.watcher);
const ListenerFn = fn (self: *Reloader, path: []const u8, name: []const u8) void;
const Watcher = switch (builtin.target.os.tag) {
    .linux => @import("watcher/LinuxWatcher.zig"),
    .macos => @import("watcher/MacosWatcher.zig"),
    .windows => @compileError("TODO: implement file watcher for windows"),
    else => @compileError("unsupported platform"),
};

gpa: std.mem.Allocator,
ws_server: ws.Server,
out_dir_path: []const u8,
watcher: Watcher,

clients_lock: std.Thread.Mutex = .{},
clients: std.AutoArrayHashMapUnmanaged(*ws.Conn, void) = .{},

pub fn init(
    gpa: std.mem.Allocator,
    out_dir_path: []const u8,
    in_dir_paths: []const []const u8,
) !Reloader {
    const ws_server = try ws.Server.init(gpa, .{});

    return .{
        .gpa = gpa,
        .out_dir_path = out_dir_path,
        .ws_server = ws_server,
        .watcher = try Watcher.init(gpa, out_dir_path, in_dir_paths),
    };
}

pub fn listen(self: *Reloader) !void {
    try self.watcher.listen(self.gpa, self);
}

pub fn onInputChange(self: *Reloader, path: []const u8, name: []const u8) void {
    _ = name;
    _ = path;
    log.debug("re-building!", .{});
    const result = std.ChildProcess.run(.{
        .allocator = self.gpa,
        .argv = &.{ "zig", "build" },
    }) catch |err| {
        log.err("unable to run zig build: {s}", .{@errorName(err)});
        return;
    };
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
}
pub fn onOutputChange(self: *Reloader, path: []const u8, name: []const u8) void {
    if (std.mem.indexOfScalar(u8, name, '.') == null) {
        return;
    }
    log.debug("re-load: {s}/{s}!", .{ path, name });

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
        const msg = std.fmt.bufPrint(&buf, msg_fmt, .{
            path[self.out_dir_path.len..],
            name,
        }) catch {
            log.err("unable to generate ws message", .{});
            return;
        };

        conn.write(msg) catch |err| {
            log.debug("error writing to websocket: {s}", .{
                @errorName(err),
            });
            self.clients.swapRemoveAt(idx);
            continue;
        };

        idx += 1;
    }
}

pub fn handleWs(self: *Reloader, res: *std.http.Server.Response) !void {
    errdefer res.deinit();

    var h: [20]u8 = undefined;

    const key = res.request.headers.getFirstValue("sec-websocket-key") orelse {
        log.debug("couldn't find key header!\n", .{});
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
        watcher: *Reloader,
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
