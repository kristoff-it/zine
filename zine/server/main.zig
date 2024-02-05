const std = @import("std");
const options = @import("options");
const fs = std.fs;
const mime = @import("mime");
const Allocator = std.mem.Allocator;
const Reloader = @import("Reloader.zig");
const not_found_html = @embedFile("404.html");
const livereload_js = @embedFile("watcher/livereload.js");
const assert = std.debug.assert;

const log = std.log.scoped(.server);
pub const std_options = struct {
    pub const log_level = .err;
    pub const log_scope_levels = options.log_scope_levels;
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
    http_server: std.http.Server,

    fn deinit(s: *Server) void {
        s.public_dir.close();
        s.http_server.deinit();
        s.* = undefined;
    }

    fn handleRequest(s: *Server, res: *std.http.Server.Response) !bool {
        var arena_impl = std.heap.ArenaAllocator.init(general_purpose_allocator.allocator());
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        // var request_buffer: [8 * 1024]u8 = undefined;
        // const n = try res.readAll(&request_buffer);
        // const request_body = request_buffer[0..n];

        var path = res.request.target;

        if (std.mem.indexOf(u8, path, "..")) |_| {
            std.debug.print("'..' not allowed in URLs\n", .{});
            @panic("TODO: check if '..' is fine");
        }

        if (std.mem.endsWith(u8, path, "/")) {
            path = try std.fmt.allocPrint(arena, "{s}{s}", .{ path, "index.html" });
        }

        if (std.mem.eql(u8, path, "/livereload.js?path=__zine-livereload__")) {
            res.transfer_encoding = .{ .content_length = livereload_js.len };
            try res.headers.append("content-type", "text/javascript");
            try res.headers.append("connection", "close");
            try res.send();
            _ = try res.writer().writeAll(livereload_js);
            try res.finish();
            log.debug("sent livereload script \n", .{});
            return false;
        }

        if (std.mem.eql(u8, path, "/__zine-livereload__")) {
            const ws = try std.Thread.spawn(.{}, Reloader.handleWs, .{ s.watcher, res });
            ws.detach();
            return true;
        }

        path = path[0 .. std.mem.indexOfScalar(u8, path, '?') orelse path.len];

        const ext = fs.path.extension(path);
        const mime_type = mime.extension_map.get(ext) orelse
            .@"application/octet-stream";

        const file = s.public_dir.openFile(path[1..], .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (std.mem.endsWith(u8, res.request.target, "/")) {
                    res.status = .not_found;
                    res.transfer_encoding = .{ .content_length = not_found_html.len };
                    try res.headers.append("content-type", "text/html");
                    try res.headers.append("connection", "close");
                    try res.send();
                    _ = try res.writer().writeAll(not_found_html);
                    try res.finish();
                    log.debug("not found\n", .{});
                    return false;
                } else {
                    // redirects from `/path` to `/path/`
                    const location = try std.fmt.allocPrint(arena, "{s}/", .{path});
                    res.status = .see_other;
                    try res.headers.append("location", location);
                    try res.send();
                    _ = try res.writer().writeAll(not_found_html);
                    try res.finish();
                    log.debug("append final slash redirect\n", .{});
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
                res.status = .internal_server_error;
                res.transfer_encoding = .{ .content_length = message.len };
                try res.headers.append("content-type", "text/html");
                try res.headers.append("connection", "close");
                try res.send();
                _ = try res.writer().writeAll(message);
                try res.finish();
                log.debug("error: {s}\n", .{@errorName(err)});
                return false;
            },
        };
        defer file.close();

        const contents = try file.readToEndAlloc(arena, std.math.maxInt(usize));

        if (mime_type == .@"text/html") {
            const injection =
                \\<script src="/livereload.js?path=__zine-livereload__"></script>
            ;
            res.transfer_encoding = .{ .content_length = contents.len + injection.len };
            try res.headers.append("content-type", @tagName(mime_type));
            try res.headers.append("connection", "close");
            try res.send();

            const head = "</head>";
            const head_pos = std.mem.indexOf(u8, contents, head) orelse contents.len;
            const w = res.writer();

            _ = try w.writeAll(contents[0..head_pos]);
            _ = try w.writeAll(injection);
            _ = try w.writeAll(contents[head_pos..]);

            try res.finish();
            log.debug("sent file\n", .{});
            return false;
        } else {
            res.transfer_encoding = .{ .content_length = contents.len };
            try res.headers.append("content-type", @tagName(mime_type));
            try res.headers.append("connection", "close");
            try res.send();
            _ = try res.writer().writeAll(contents);
            try res.finish();
            log.debug("sent file\n", .{});
            return false;
        }
    }
};

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

    {
        var i: usize = 0;
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
    var root_dir: fs.Dir = fs.cwd().openDir(root_dir_path, .{ .iterate = true }) catch |e|
        fatal("unable to open directory '{s}': {s}", .{ root_dir_path, @errorName(e) });
    defer root_dir.close();

    var watcher = try Reloader.init(gpa, root_dir_path, input_dirs.items);

    var server: Server = .{
        .watcher = &watcher,
        .public_dir = root_dir,
        .http_server = std.http.Server.init(.{
            .reuse_address = true,
        }),
    };
    defer server.deinit();

    const watch_thread = try std.Thread.spawn(.{}, Reloader.listen, .{&watcher});
    watch_thread.detach();

    const address = try std.net.Address.parseIp("127.0.0.1", listen_port);
    try server.http_server.listen(address);
    const server_port = server.http_server.socket.listen_address.in.getPort();
    std.debug.print("Listening at http://127.0.0.1:{d}/\n", .{server_port});

    try serve(gpa, &server);
}

fn serve(gpa: Allocator, s: *Server) !void {
    var header_buffer: [1024]u8 = undefined;
    accept: while (true) {
        var became_websocket = false;
        // handleRequest owns res
        var res = try s.http_server.accept(.{
            .allocator = gpa,
            .header_strategy = .{ .static = &header_buffer },
        });

        defer {
            if (!became_websocket) {
                res.deinit();
            } else {
                log.debug("request became websocket\n", .{});
            }
        }

        while (res.reset() != .closing) {
            res.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :accept,
                error.EndOfStream => continue,
                else => return err,
            };
            log.debug("request: {s}", .{res.request.target});
            became_websocket = s.handleRequest(&res) catch |err| {
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
