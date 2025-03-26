const std = @import("std");
const builtin = @import("builtin");
const mime = @import("mime");
const tracy = @import("tracy");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const fatal = @import("../fatal.zig");
const ws = @import("serve/websocket.zig");
const zinereload_js = @embedFile("serve/zinereload.js");
const not_found_html = @embedFile("serve/404.html");
const Channel = @import("../channel.zig").Channel;
const Allocator = std.mem.Allocator;

const Watcher = @import("serve/watcher/MacosWatcher.zig");
// const Watcher = switch (builtin.target.os.tag) {
//     .linux => @import("exes/server/watcher/LinuxWatcher.zig"),
//     .macos => @import("exes/server/watcher/MacosWatcher.zig"),
//     .windows => @import("exes/server/watcher/WindowsWatcher.zig"),
//     else => @compileError("unsupported platform"),
// };

const log = std.log.scoped(.serve);

pub const ServeEvent = union(enum) {
    change,
    connect: *std.http.Server.Request,
    disconnect: *ws.Connection,
};

pub fn serve(gpa: Allocator, args: []const []const u8) void {
    if (builtin.single_threaded) fatal.msg(
        "error: single-threaded zine does not yet support the 'serve' command, sorry",
        .{},
    );

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cmd: Command = .parse(args);

    worker.start();
    defer worker.stopWaitAndDeinit();
    var build = root.run(gpa);

    var buf: [64]ServeEvent = undefined;
    var channel: Channel(ServeEvent) = .init(&buf);
    var watcher: Watcher = .init(
        gpa,
        &channel,
        &.{
            try gpa.dupe(u8, build.cfg.getAssetsDirPath()),
            try gpa.dupe(u8, build.cfg.getLayoutsDirPath()),
            "content",
        },
        &.{},
    );

    watcher.start() catch |err| fatal.msg(
        "error: unable to start file watcher: {s}",
        .{@errorName(err)},
    );

    const public = std.fs.cwd().openDir(
        "public",
        .{},
    ) catch |err| fatal.dir("public", err);

    var server: Server = .init(gpa, &channel, public);
    const listen_address = server.start(cmd) catch |err| fatal.msg(
        "error: unable to start live webserver: {s}",
        .{@errorName(err)},
    );

    build.deinit(gpa);

    const node = root.progress.start(try std.fmt.allocPrint(
        gpa,
        "Listening at http://{any}/",
        .{listen_address},
    ), 0);
    defer node.end();

    var websockets: std.AutoArrayHashMapUnmanaged(*ws.Connection, void) = .empty;
    while (true) {
        const event = channel.get();
        log.debug("new event: {s}", .{@tagName(event)});
        switch (event) {
            .change => {
                build = root.run(gpa);
                for (websockets.entries.items(.key)) |conn| {
                    conn.writeMessage(
                        \\{ "command": "reload_all" }
                    , .text) catch |err| {
                        log.debug("error writing to ws: {s}", .{@errorName(err)});
                        conn.close();
                    };
                }
                build.deinit(gpa);
            },
            .connect => |req| {
                const c = try gpa.create(ws.Connection);
                c.* = ws.Connection.init(req) catch |err| {
                    std.debug.print(
                        "warning: failed to establish a websocket connection: {s}\n",
                        .{@errorName(err)},
                    );
                    continue;
                };
                try websockets.put(gpa, c, {});
                const reader = std.Thread.spawn(.{}, Server.readWs, .{
                    &server,
                    c,
                }) catch |err| fatal.msg(
                    "error: failed to spawn websocket reader thread: {s}",
                    .{@errorName(err)},
                );
                reader.detach();
            },
            .disconnect => |conn| {
                _ = websockets.swapRemove(conn);
                conn.close();
            },
        }
    }
}

pub const Command = struct {
    host: []const u8,
    port: u16,

    fn parseAddress(arg: []const u8) struct { []const u8, ?u16 } {
        var it = std.mem.tokenizeScalar(u8, arg, ':');
        const host = it.next() orelse fatal.msg(
            "error: missing argument to '--address='",
            .{},
        );
        var port: ?u16 = null;
        if (it.next()) |p| port = std.fmt.parseInt(u16, p, 10) catch |err| fatal.msg(
            "error: bad port in '{s}': {s}",
            .{ arg, @errorName(err) },
        );

        return .{ host, port };
    }
    pub fn parse(args: []const []const u8) Command {
        var host: ?[]const u8 = null;
        var port: ?u16 = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.startsWith(u8, arg, "--address=")) {
                const suffix = arg["--address=".len..];
                host, const maybe_port = parseAddress(suffix);
                if (maybe_port) |p| port = p;
            }
            if (std.mem.eql(u8, arg, "--address")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--address'",
                    .{},
                );
                host, const maybe_port = parseAddress(args[idx]);
                if (maybe_port) |p| port = p;
            }

            if (std.mem.startsWith(u8, arg, "--port=")) {
                const suffix = arg["--port=".len..];
                port = std.fmt.parseInt(u16, suffix, 10) catch |err| fatal.msg(
                    "error: bad port in '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            }
            if (std.mem.eql(u8, arg, "--port")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--port'",
                    .{},
                );
                port = std.fmt.parseInt(u16, args[idx], 10) catch |err| fatal.msg(
                    "error: bad port in '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            }

            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                std.debug.print(
                    \\Usage: zine serve [OPTIONS]
                    \\
                    \\Command specific options:
                    \\  --host          Listening host (default 'localhost')
                    \\  --port          Listening port    (default 1990)
                    \\
                    \\General Options:
                    \\  --help, -h      Print command specific usage
                    \\
                    \\
                , .{});
                std.process.exit(1);
            }
        }

        return .{
            .host = host orelse "localhost",
            .port = port orelse 1990,
        };
    }
};
/// like fs.path.dirname but ensures a final `/`
fn dirNameWithSlash(path: []const u8) []const u8 {
    const d = std.fs.path.dirname(path).?;
    if (d.len > 1) {
        return path[0 .. d.len + 1];
    } else {
        return "/";
    }
}

pub const Server = struct {
    gpa: Allocator,
    channel: *Channel(ServeEvent),
    public_dir: std.fs.Dir,

    pub const max_connection_header_size: usize = 8 * 1024;

    pub fn init(
        gpa: Allocator,
        channel: *Channel(ServeEvent),
        public_dir: std.fs.Dir,
    ) Server {
        return .{ .gpa = gpa, .channel = channel, .public_dir = public_dir };
    }

    pub fn start(s: *Server, cmd: Command) !std.net.Address {
        const list = try std.net.getAddressList(s.gpa, cmd.host, cmd.port);
        if (list.addrs.len == 0) fatal.msg(
            "error: unable to resolve host '{s}'",
            .{cmd.host},
        );
        _ = try std.Thread.spawn(.{}, Server.serve, .{ s, list });
        return list.addrs[0];
    }

    fn serve(s: *Server, list: *std.net.AddressList) void {
        defer list.deinit();

        errdefer |err| switch (err) {
            error.OutOfMemory => fatal.oom(),
        };

        const address = list.addrs[0];
        var tcp_server = address.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        }) catch |err| fatal.msg(
            "error: unable to bind to '{any}': {s}",
            .{ address, @errorName(err) },
        );
        defer tcp_server.deinit();

        // const server_port = tcp_server.listen_address.in.getPort();

        var arena_state = std.heap.ArenaAllocator.init(s.gpa);
        const arena = arena_state.allocator();

        var buffer: [max_connection_header_size]u8 = undefined;
        accept: while (true) {
            const conn = tcp_server.accept() catch |err| switch (err) {
                error.SystemResources,
                error.ProcessFdQuotaExceeded,
                error.SystemFdQuotaExceeded,
                error.Unexpected,
                error.SocketNotListening,
                error.ProtocolFailure,
                error.BlockedByFirewall,
                error.NetworkSubsystemFailed,
                error.WouldBlock,
                error.FileDescriptorNotASocket,
                error.OperationNotSupported,
                => fatal.msg(
                    "error: critical failure while opening new live server tcp connection: {s}",
                    .{@errorName(err)},
                ),
                error.ConnectionResetByPeer,
                error.ConnectionAborted,
                => {
                    log.debug("non-fatal tcp error: {s}", .{@errorName(err)});
                    continue :accept;
                },
            };

            var http_server = std.http.Server.init(conn, &buffer);
            var became_websocket = false;

            defer {
                if (!became_websocket) {
                    conn.stream.close();
                } else {
                    log.debug("request became websocket\n", .{});
                }
            }

            while (http_server.state == .ready) {
                var request = http_server.receiveHead() catch |err| {
                    if (err != error.HttpConnectionClosing) {
                        log.debug("connection error: {s}\n", .{@errorName(err)});
                    }
                    became_websocket = true;
                    continue :accept;
                };

                log.debug("request: {s}", .{request.head.target});
                became_websocket = s.handleRequest(arena, &request) catch |err| {
                    log.debug("failed request: {s}", .{@errorName(err)});
                    continue :accept;
                };
                _ = arena_state.reset(.retain_capacity);
                if (became_websocket) continue :accept;
            }
        }
    }

    fn handleRequest(
        server: *Server,
        arena: Allocator,
        req: *std.http.Server.Request,
    ) !bool {
        var path_with_query = req.head.target;

        if (std.mem.indexOf(u8, path_with_query, "..")) |_| {
            std.debug.print("'..' not allowed in URLs\n", .{});
            @panic("TODO: check if '..' is fine");
        }

        if (std.mem.indexOfScalar(u8, path_with_query, '%')) |_| {
            const buffer = try arena.dupe(u8, path_with_query);
            path_with_query = std.Uri.percentDecodeInPlace(buffer);
        }

        var path = path_with_query[0 .. std.mem.indexOfScalar(u8, path_with_query, '?') orelse path_with_query.len];
        const path_ends_with_slash = std.mem.endsWith(u8, path, "/");

        if (path_ends_with_slash) {
            path = try std.fmt.allocPrint(arena, "{s}{s}", .{
                path,
                "index.html",
            });
        }

        if (std.mem.eql(u8, path, "/__zine/zinereload.js")) {
            try req.respond(zinereload_js, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/javascript" },
                    .{ .name = "connection", .value = "close" },
                },
            });
            req.server.connection.stream.close();

            log.debug("sent livereload script \n", .{});
            return false;
        }

        if (std.mem.eql(u8, path, "/__zine/ws")) {
            server.channel.put(.{ .connect = req });
            return true;
        }

        defer req.server.connection.stream.close();

        const ext = std.fs.path.extension(path);
        const mime_type = mime.extension_map.get(ext) orelse
            .@"application/octet-stream";

        const file = server.public_dir.openFile(path[1..], .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (path_ends_with_slash) {
                    try req.respond(not_found_html, .{
                        .status = .not_found,
                        .extra_headers = &.{
                            .{ .name = "content-type", .value = "text/html" },
                            .{ .name = "connection", .value = "close" },
                        },
                    });
                    log.debug("not found\n", .{});
                    return false;
                } else {
                    try appendSlashRedirect(arena, req, path_with_query);
                    return false;
                }
            },
            else => {
                const message = try std.fmt.allocPrint(
                    arena,
                    "error accessing the resource: {s}",
                    .{
                        @errorName(err),
                    },
                );
                try req.respond(message, .{
                    .status = .internal_server_error,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/html" },
                        .{ .name = "connection", .value = "close" },
                    },
                });
                log.debug("error: {s}\n", .{@errorName(err)});
                return false;
            },
        };
        defer file.close();

        const contents = file.readToEndAlloc(arena, std.math.maxInt(usize)) catch |err| switch (err) {
            error.IsDir => {
                try appendSlashRedirect(arena, req, path_with_query);
                return false;
            },
            else => return err,
        };

        if (mime_type == .@"text/html") {
            const injection =
                \\<script src="/__zine/zinereload.js"></script>
            ;
            const head = "</head>";
            const head_pos = std.mem.indexOf(u8, contents, head) orelse contents.len;

            const injected = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
                contents[0..head_pos],
                injection,
                contents[head_pos..],
            });

            try req.respond(injected, .{
                .status = .ok,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/html" },
                    .{ .name = "connection", .value = "close" },
                },
            });

            log.debug("sent file\n", .{});
            return false;
        } else {
            try req.respond(contents, .{
                .status = .ok,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = @tagName(mime_type) },
                    .{ .name = "connection", .value = "close" },
                },
            });
            log.debug("sent file\n", .{});
            return false;
        }
    }

    fn appendSlashRedirect(
        arena: std.mem.Allocator,
        req: *std.http.Server.Request,
        path_with_query: []const u8,
    ) !void {
        // convert `foo/bar?query=1` to `foo/bar/?query=1`
        const query_start = std.mem.indexOfScalar(u8, path_with_query, '?') orelse path_with_query.len;
        const location = try std.fmt.allocPrint(
            arena,
            "{s}/{s}",
            .{ path_with_query[0..query_start], path_with_query[query_start..] },
        );

        try req.respond(not_found_html, .{
            .status = .see_other,
            .extra_headers = &.{
                .{ .name = "location", .value = location },
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "connection", .value = "close" },
            },
        });
        log.debug("append final slash redirect\n", .{});
    }

    pub fn readWs(s: *Server, conn: *ws.Connection) void {
        while (true) {
            var buf: [1024]u8 = undefined;
            const msg = conn.readMessage(&buf) catch |err| {
                log.debug("readWs error: {s} {any}", .{ @errorName(err), conn });
                s.channel.put(.{ .disconnect = conn });
                return;
            };
            log.debug("readWs msg: '{s}'", .{msg});
        }
    }
};
