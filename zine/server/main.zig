const std = @import("std");
const options = @import("options");
const fs = std.fs;
const mime = @import("mime");
const Allocator = std.mem.Allocator;
const Reloader = @import("Reloader.zig");
const not_found_html = @embedFile("404.html");
const zinereload_js = @embedFile("watcher/zinereload.js");
const assert = std.debug.assert;

const log = std.log.scoped(.server);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

const usage =
    \\usage: zine serve [options]
    \\
    \\options:
    \\      -p [port]        set the port number to listen on
    \\      --root [path]    directory of static files to serve
    \\
;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

const Server = struct {
    watcher: *Reloader,
    public_dir: std.fs.Dir,

    fn deinit(s: *Server) void {
        s.public_dir.close();
        s.* = undefined;
    }

    fn handleRequest(s: *Server, req: *std.http.Server.Request) !bool {
        var arena_impl = std.heap.ArenaAllocator.init(general_purpose_allocator.allocator());
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        // var request_buffer: [8 * 1024]u8 = undefined;
        // const n = try res.readAll(&request_buffer);
        // const request_body = request_buffer[0..n];

        var path = req.head.target;

        if (std.mem.indexOf(u8, path, "..")) |_| {
            std.debug.print("'..' not allowed in URLs\n", .{});
            @panic("TODO: check if '..' is fine");
        }

        if (std.mem.endsWith(u8, path, "/")) {
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

            log.debug("sent livereload script \n", .{});
            return false;
        }

        if (std.mem.eql(u8, path, "/__zine/ws")) {
            const ws = try std.Thread.spawn(.{}, Reloader.handleWs, .{
                s.watcher,
                req,
            });
            ws.detach();
            return true;
        }

        path = path[0 .. std.mem.indexOfScalar(u8, path, '?') orelse path.len];

        const ext = fs.path.extension(path);
        const mime_type = mime.extension_map.get(ext) orelse
            .@"application/octet-stream";

        const file = s.public_dir.openFile(path[1..], .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (std.mem.endsWith(u8, req.head.target, "/")) {
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
                    try appendSlashRedirect(arena, req);
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
                try appendSlashRedirect(arena, req);
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
};

fn appendSlashRedirect(
    arena: std.mem.Allocator,
    req: *std.http.Server.Request,
) !void {
    const location = try std.fmt.allocPrint(
        arena,
        "{s}/",
        .{req.head.target},
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

pub fn main() !void {
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);

    log.debug("log from server!", .{});

    if (args.len < 2) fatal("missing subcommand argument", .{});

    const cmd_name = args[1];
    if (std.mem.eql(u8, cmd_name, "serve")) {
        return cmdServe(gpa, args[2..]);
    } else {
        fatal("unrecognized subcommand: '{s}'", .{cmd_name});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

fn cmdServe(gpa: Allocator, args: []const []const u8) !void {
    var listen_port: u16 = 0;
    var opt_root_dir_path: ?[]const u8 = null;
    var input_dirs: std.ArrayListUnmanaged([]const u8) = .{};
    const zig_exe = args[0];

    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-p")) {
                i += 1;
                if (i >= args.len) fatal("expected arg after '{s}'", .{arg});
                listen_port = std.fmt.parseInt(u16, args[i], 10) catch |err| {
                    fatal("unable to parse port '{s}': {s}", .{ args[i], @errorName(err) });
                };
            } else if (std.mem.eql(u8, arg, "--root")) {
                i += 1;
                if (i >= args.len) fatal("expected arg after '{s}'", .{arg});
                opt_root_dir_path = args[i];
            } else if (std.mem.eql(u8, arg, "--input-dir")) {
                i += 1;
                if (i >= args.len) fatal("expected arg after '{s}'", .{arg});
                try input_dirs.append(gpa, args[i]);
            } else {
                fatal("unrecognized arg: '{s}'", .{arg});
            }
        }
    }

    const root_dir_path = opt_root_dir_path orelse ".";

    // ensure the path exists. without this, an empty website that
    // doesn't generate a zig-out/ will cause the server to error out
    try fs.cwd().makePath(root_dir_path);

    var root_dir: fs.Dir = fs.cwd().openDir(root_dir_path, .{ .iterate = true }) catch |e|
        fatal("unable to open directory '{s}': {s}", .{ root_dir_path, @errorName(e) });
    defer root_dir.close();

    var watcher = try Reloader.init(gpa, zig_exe, root_dir_path, input_dirs.items);

    var server: Server = .{
        .watcher = &watcher,
        .public_dir = root_dir,
    };
    defer server.deinit();

    const watch_thread = try std.Thread.spawn(.{}, Reloader.listen, .{&watcher});
    watch_thread.detach();

    try serve(&server, listen_port);
}

fn serve(s: *Server, listen_port: u16) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", listen_port);
    var tcp_server = try address.listen(.{
        .reuse_port = true,
        .reuse_address = true,
    });
    defer tcp_server.deinit();

    const server_port = tcp_server.listen_address.in.getPort();
    std.debug.print("\x1b[2K\rListening at http://127.0.0.1:{d}/\n", .{server_port});

    var buffer: [1024]u8 = undefined;
    accept: while (true) {
        const conn = try tcp_server.accept();

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
                std.debug.print("error: {s}\n", .{@errorName(err)});
                continue :accept;
            };

            log.debug("request: {s}", .{request.head.target});
            became_websocket = s.handleRequest(&request) catch |err| {
                log.debug("failed request: {s}", .{@errorName(err)});
                continue :accept;
            };
            if (became_websocket) continue :accept;
        }
    }
}

/// like fs.path.dirname but ensures a final `/`
fn dirNameWithSlash(path: []const u8) []const u8 {
    const d = fs.path.dirname(path).?;
    if (d.len > 1) {
        return path[0 .. d.len + 1];
    } else {
        return "/";
    }
}
