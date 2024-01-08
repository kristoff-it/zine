const std = @import("std");
const fs = std.fs;
const mime = @import("mime");
const Allocator = std.mem.Allocator;
const not_found_html = @embedFile("404.html");
const assert = std.debug.assert;

const usage =
    \\usage: zine serve [options]
    \\
    \\options:
    \\      -p [port]        set the port number to listen on
    \\      --root [path]    directory of static files to serve
    \\
;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

const File = struct {
    mime_type: mime.Type,
    contents: []u8,
};

const Server = struct {
    /// The key is file path.
    files: std.StringHashMap(File),
    http_server: std.http.Server,

    fn deinit(s: *Server) void {
        s.files.deinit();
        s.http_server.deinit();
        s.* = undefined;
    }

    fn handleRequest(s: *Server, res: *std.http.Server.Response) !void {
        //var request_buffer: [8 * 1024]u8 = undefined;
        //const n = try res.readAll(&request_buffer);
        //const request_body = request_buffer[0..n];
        //_ = request_body;
        //std.debug.print("request_body:\n{s}\n", .{request_body});

        const path = res.request.target;
        const file = s.files.get(path) orelse {
            if (std.mem.endsWith(u8, path, "/")) {
                res.status = .not_found;
                res.transfer_encoding = .{ .content_length = not_found_html.len };
                try res.headers.append("content-type", "text/html");
                try res.headers.append("connection", "close");
                try res.send();
                _ = try res.writer().writeAll(not_found_html);
                try res.finish();
                return;
            } else {
                // redirects from `/path` to `/path/`
                const ally = general_purpose_allocator.allocator();
                const location = try std.fmt.allocPrint(ally, "{s}/", .{path});
                defer ally.free(location);
                res.status = .see_other;
                try res.headers.append("location", location);
                try res.send();
                try res.finish();
                return;
            }
        };

        res.transfer_encoding = .{ .content_length = file.contents.len };
        try res.headers.append("content-type", @tagName(file.mime_type));
        try res.headers.append("connection", "close");
        try res.send();

        _ = try res.writer().writeAll(file.contents);
        try res.finish();
    }
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len < 2) fatal("missing subcommand argument", .{});

    const cmd_name = args[1];
    if (std.mem.eql(u8, cmd_name, "serve")) {
        return cmdServe(gpa, arena, args[2..]);
    } else {
        fatal("unrecognized subcommand: '{s}'", .{cmd_name});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

fn cmdServe(gpa: Allocator, arena: Allocator, args: []const []const u8) !void {
    var listen_port: u16 = 0;
    var opt_root_dir_path: ?[]const u8 = null;

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
            } else {
                fatal("unrecognized arg: '{s}'", .{arg});
            }
        }
    }

    const root_dir_path = opt_root_dir_path orelse ".";
    var root_dir: fs.Dir = fs.cwd().openDir(root_dir_path, .{ .iterate = true }) catch |e|
        fatal("unable to open directory '{s}': {s}", .{ root_dir_path, @errorName(e) });
    defer root_dir.close();

    var server: Server = .{
        .files = std.StringHashMap(File).init(gpa),
        .http_server = std.http.Server.init(gpa, .{
            .reuse_address = true,
        }),
    };
    defer server.deinit();

    {
        var it = try root_dir.walk(arena);
        defer it.deinit();

        while (try it.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    const max_size = std.math.maxInt(u32);
                    const bytes = root_dir.readFileAlloc(arena, entry.path, max_size) catch |err| {
                        fatal("unable to read '{s}': {s}", .{ entry.path, @errorName(err) });
                    };
                    const sub_path = try normalizePathAlloc(arena, entry.path);
                    const ext = fs.path.extension(sub_path);
                    const file: File = .{
                        .mime_type = mime.extension_map.get(ext) orelse
                            .@"application/octet-stream",
                        .contents = bytes,
                    };
                    try server.files.put(sub_path, file);
                    if (std.mem.eql(u8, entry.basename, "index.html")) {
                        // Add an alias
                        try server.files.put(dirNameWithSlash(sub_path), file);
                    }
                },
                else => continue,
            }
        }
    }

    const address = try std.net.Address.parseIp("127.0.0.1", listen_port);
    try server.http_server.listen(address);
    const server_port = server.http_server.socket.listen_address.in.getPort();
    std.debug.print("Listening at http://127.0.0.1:{d}/\n", .{server_port});

    try serve(gpa, &server);
}

fn serve(gpa: Allocator, s: *Server) !void {
    var header_buffer: [1024]u8 = undefined;
    accept: while (true) {
        var res = try s.http_server.accept(.{
            .allocator = gpa,
            .header_strategy = .{ .static = &header_buffer },
        });
        defer res.deinit();

        while (res.reset() != .closing) {
            res.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :accept,
                error.EndOfStream => continue,
                else => return err,
            };
            s.handleRequest(&res) catch |err| {
                std.log.err("failed request: {s}", .{@errorName(err)});
                continue :accept;
            };
        }
    }
}

/// Make a file system path identical independently of operating system path inconsistencies.
/// This converts backslashes into forward slashes.
fn normalizePathAlloc(arena: Allocator, fs_path: []const u8) ![]const u8 {
    const new_buffer = try arena.alloc(u8, fs_path.len + 1);
    new_buffer[0] = canonical_sep;
    @memcpy(new_buffer[1..], fs_path);
    if (fs.path.sep != canonical_sep)
        normalizePath(new_buffer);
    return new_buffer;
}

const canonical_sep = fs.path.sep_posix;

fn normalizePath(bytes: []u8) void {
    assert(fs.path.sep != canonical_sep);
    std.mem.replaceScalar(u8, bytes, fs.path.sep, canonical_sep);
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
