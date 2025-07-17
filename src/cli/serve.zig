const std = @import("std");
const builtin = @import("builtin");
const mime = @import("mime");
const tracy = @import("tracy");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const fatal = @import("../fatal.zig");
const ws = @import("serve/websocket.zig");
const Build = @import("../Build.zig");
const PathTable = @import("../PathTable.zig");
const StringTable = @import("../StringTable.zig");
const PathName = PathTable.PathName;
const Path = PathTable.Path;
const String = StringTable.String;
const Channel = @import("../channel.zig").Channel;
const Allocator = std.mem.Allocator;
const BuildAsset = root.BuildAsset;
const assert = std.debug.assert;

const zinereload_js = @embedFile("serve/zinereload.js");
const not_found_html = @embedFile("serve/404.html");
const error_html = @embedFile("serve/error.html");
const outside_html = @embedFile("serve/outside.html");
const Watcher = switch (builtin.target.os.tag) {
    .linux => @import("serve/watcher/LinuxWatcher.zig"),
    .macos => @import("serve/watcher/MacosWatcher.zig"),
    .windows => @import("serve/watcher/WindowsWatcher.zig"),
    else => @compileError("unsupported platform"),
};

const log = std.log.scoped(.serve);

pub const ServeEvent = union(enum) {
    change,
    connect: ws.Connection,
    disconnect: ws.Connection,
};

pub fn serve(gpa: Allocator, args: []const []const u8) noreturn {
    if (builtin.single_threaded) {
        std.debug.print(
            "error: single-threaded zine does not yet support running the live server, sorry\n\n",
            .{},
        );

        fatal.help();
    }
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cmd: Command = try .parse(gpa, args);

    worker.start();
    defer if (builtin.mode == .Debug) worker.stopWaitAndDeinit();

    var buf: [64]ServeEvent = undefined;
    var channel: Channel(ServeEvent) = .init(&buf);

    var debouncer: Debouncer = .{
        .cascade_window_ms = cmd.debounce,
        .channel = &channel,
    };

    debouncer.start() catch |err| fatal.msg(
        "error: unable to start debouncer: {s}",
        .{@errorName(err)},
    );

    var cfg, const base_dir_path = root.Config.load(gpa);
    switch (cfg) {
        .Site => |*s| s.host_url = try std.fmt.allocPrint(
            gpa,
            "http://{s}:{}/",
            .{ cmd.host, cmd.port },
        ),

        .Multilingual => |*ml| {
            ml.host_url = try std.fmt.allocPrint(
                gpa,
                "http://{s}:{}/",
                .{ cmd.host, cmd.port },
            );

            for (ml.locales) |l| if (l.host_url_override != null) {
                fatal.msg("error: host_url_override is not yet supported by the zine live server, sorry!", .{});
            };
        },
    }

    var dirs_to_watch: std.ArrayListUnmanaged([:0]const u8) = .empty;
    defer if (builtin.mode == .Debug) dirs_to_watch.deinit(gpa);

    try dirs_to_watch.appendSlice(
        gpa,
        &.{
            try std.fs.path.joinZ(gpa, &.{
                base_dir_path,
                cfg.getAssetsDirPath(),
            }),
            try std.fs.path.joinZ(gpa, &.{
                base_dir_path,
                cfg.getLayoutsDirPath(),
            }),
        },
    );
    switch (cfg) {
        .Site => |s| try dirs_to_watch.append(
            gpa,
            try std.fs.path.joinZ(gpa, &.{
                base_dir_path,
                s.content_dir_path,
            }),
        ),
        .Multilingual => |ml| {
            try dirs_to_watch.append(gpa, try std.fs.path.joinZ(gpa, &.{
                base_dir_path,
                ml.i18n_dir_path,
            }));
            for (ml.locales) |l| try dirs_to_watch.append(
                gpa,
                try std.fs.path.joinZ(gpa, &.{
                    base_dir_path,
                    l.content_dir_path,
                }),
            );
        },
    }

    var watcher: Watcher = .init(
        gpa,
        &debouncer,
        dirs_to_watch.items,
    );

    watcher.start() catch |err| fatal.msg(
        "error: unable to start file watcher: {s}",
        .{@errorName(err)},
    );

    var build_lock: std.Thread.RwLock = .{};
    var build = root.run(gpa, &cfg, .{
        .base_dir_path = base_dir_path,
        .build_assets = &cmd.build_assets,
        .drafts = cmd.drafts,
        .mode = .memory,
    }) catch fatal.oom();

    var server: Server = .init(gpa, &channel, &build, &build_lock);
    const listen_address = server.start(cmd) catch |err| fatal.msg(
        "error: unable to start live webserver: {s}",
        .{@errorName(err)},
    );
    _ = listen_address;

    std.debug.print(
        \\Starting the Zine development server.
        \\Run 'zine help' to learn more about available options.
        \\
        \\
    , .{});

    const name = switch (cfg) {
        .Site => |s| try std.fmt.allocPrint(
            gpa,
            "Listening at http://{s}:{}{f}",
            .{ cmd.host, cmd.port, root.fmtJoin('/', &.{ "/", s.url_path_prefix, "/" }) },
        ),
        .Multilingual => try std.fmt.allocPrint(
            gpa,
            "Listening at http://{s}:{}/",
            .{ cmd.host, cmd.port },
        ),
    };

    const node = root.progress.start(name, 0);
    defer node.end();

    var websockets: std.AutoArrayHashMapUnmanaged(
        std.posix.socket_t,
        ws.Connection,
    ) = .empty;

    while (true) {
        const event = channel.get();
        log.debug("new event: {s}", .{@tagName(event)});
        switch (event) {
            .change => {
                build_lock.lock();
                build.deinit(gpa);
                build = root.run(gpa, &cfg, .{
                    .base_dir_path = base_dir_path,
                    .build_assets = &cmd.build_assets,
                    .drafts = cmd.drafts,
                    .mode = .memory,
                }) catch fatal.oom();
                build_lock.unlock();

                for (websockets.entries.items(.value)) |*conn| {
                    conn.writeMessage(
                        \\{ "command": "reload_all" }
                    , .text) catch |err| {
                        log.debug(
                            "error writing to ws: {s}",
                            .{@errorName(err)},
                        );
                    };
                }
            },
            .connect => |conn| {
                try websockets.put(gpa, conn.stream.handle, conn);
                // We don't lock build because this thread is the only writer

                for (build.mode.memory.errors.items) |build_err| {
                    const bytes = try std.json.stringifyAlloc(
                        gpa,
                        .{
                            .command = "build",
                            .err = build_err.msg,
                        },
                        .{},
                    );

                    defer gpa.free(bytes);

                    conn.writeMessage(bytes, .text) catch |err| {
                        log.debug(
                            "error writing to ws: {s}",
                            .{@errorName(err)},
                        );
                    };
                }

                if (build.any_rendering_error.load(.acquire)) {
                    outer: for (build.variants) |*v| {
                        for (v.pages.items) |*p| {
                            if (!p._parse.active) continue;
                            if (p._parse.status != .parsed) continue;
                            if (p._analysis.frontmatter.items.len > 0) continue;
                            if (p._analysis.page.items.len > 0) continue;

                            if (p._render.errors.len > 0) {
                                const bytes = try std.json.stringifyAlloc(
                                    gpa,
                                    .{
                                        .command = "build",
                                        .err = p._render.errors,
                                    },
                                    .{},
                                );

                                defer gpa.free(bytes);

                                conn.writeMessage(bytes, .text) catch |err| {
                                    log.debug(
                                        "error writing to ws: {s}",
                                        .{@errorName(err)},
                                    );
                                };

                                break :outer;
                            }

                            for (p._render.alternatives) |alt| {
                                if (alt.errors.len > 0) {
                                    const bytes = try std.json.stringifyAlloc(
                                        gpa,
                                        .{
                                            .command = "build",
                                            .err = alt.errors,
                                        },
                                        .{},
                                    );

                                    defer gpa.free(bytes);

                                    conn.writeMessage(bytes, .text) catch |err| {
                                        log.debug(
                                            "error writing to ws: {s}",
                                            .{@errorName(err)},
                                        );
                                    };

                                    break :outer;
                                }
                            }
                        }
                    }
                }
            },
            .disconnect => |conn| {
                // the server thread will take care of closing the connection
                // as the corresponding thread shuts down
                _ = websockets.swapRemove(conn.stream.handle);
            },
        }
    }
}

pub const Command = struct {
    host: []const u8,
    port: u16,
    debounce: u16,
    build_assets: std.StringArrayHashMapUnmanaged(BuildAsset),
    drafts: bool,

    fn parseAddress(arg: []const u8) struct { []const u8, ?u16 } {
        if (arg.len <= 0) {
            fatal.msg(
                "error: missing argument to '--host='",
                .{},
            );
        }

        const host = if (arg[0] == '[') ipv6: {
            var i: usize = 1;
            while (i < arg.len) : (i += 1) {
                if (arg[i] == ']') {
                    break :ipv6 arg[0 .. i + 1];
                }
            }
            fatal.msg(
                "error: unmatched '[' in '--host='",
                .{},
            );
        } else arg[0 .. std.mem.indexOfScalar(u8, arg, ':') orelse arg.len];

        var port: ?u16 = null;
        const maybe_port = arg[host.len..];
        if (maybe_port.len > 0 and maybe_port[0] == ':') {
            port = std.fmt.parseInt(u16, maybe_port[1..], 10) catch |err| fatal.msg(
                \\error: bad port in '{s}': {s}
                \\hint: if you meant to use IPv6, wrap it in square brackets, e.g. --host=[::1]
                \\
            ,
                .{ arg, @errorName(err) },
            );
        }

        return .{ host, port };
    }
    pub fn parse(
        gpa: Allocator,
        args: []const []const u8,
    ) error{OutOfMemory}!Command {
        var host: ?[]const u8 = null;
        var port: ?u16 = null;
        var debounce: ?u16 = null;
        var build_assets: std.StringArrayHashMapUnmanaged(BuildAsset) = .empty;
        var drafts: ?bool = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.startsWith(u8, arg, "--host=")) {
                const suffix = arg["--host=".len..];
                host, const maybe_port = parseAddress(suffix);
                if (maybe_port) |p| port = p;
            } else if (std.mem.eql(u8, arg, "--host")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--host'",
                    .{},
                );
                host, const maybe_port = parseAddress(args[idx]);
                if (maybe_port) |p| port = p;
            } else if (std.mem.startsWith(u8, arg, "--port=")) {
                const suffix = arg["--port=".len..];
                port = std.fmt.parseInt(u16, suffix, 10) catch |err| fatal.msg(
                    "error: bad port value '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            } else if (std.mem.eql(u8, arg, "--port")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--port'",
                    .{},
                );
                port = std.fmt.parseInt(u16, args[idx], 10) catch |err| fatal.msg(
                    "error: bad port value '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            } else if (std.mem.startsWith(u8, arg, "--debounce=")) {
                const suffix = arg["--debounce=".len..];
                debounce = std.fmt.parseInt(u16, suffix, 10) catch |err| fatal.msg(
                    "error: bad debounce value '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            } else if (std.mem.eql(u8, arg, "--debounce")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--debounce'",
                    .{},
                );
                debounce = std.fmt.parseInt(u16, args[idx], 10) catch |err| fatal.msg(
                    "error: bad debounce value '{s}': {s}",
                    .{ arg, @errorName(err) },
                );
            } else if (std.mem.eql(u8, arg, "-h") or
                std.mem.eql(u8, arg, "--help"))
            {
                fatal.help();
            } else if (std.mem.startsWith(u8, arg, "--build-asset=")) {
                const name = arg["--build-asset=".len..];

                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing build asset sub-argument for '{s}'",
                    .{name},
                );

                const input_path = args[idx];

                idx += 1;
                var output_path: ?[]const u8 = null;
                var output_always = false;
                if (idx < args.len) {
                    const next = args[idx];
                    if (std.mem.startsWith(u8, next, "--output=")) {
                        output_path = next["--output=".len..];
                    } else if (std.mem.startsWith(u8, next, "--output-always=")) {
                        output_always = true;
                        output_path = next["--output-always=".len..];
                    } else {
                        idx -= 1;
                    }
                }

                const gop = try build_assets.getOrPut(gpa, name);
                if (gop.found_existing) fatal.msg(
                    "error: duplicate build asset name '{s}'",
                    .{name},
                );

                gop.value_ptr.* = .{
                    .input_path = input_path,
                    .output_path = output_path,
                    .output_always = output_always,
                    .rc = .{ .raw = @intFromBool(output_always) },
                };
            } else if (std.mem.eql(u8, arg, "--drafts")) {
                drafts = true;
            } else {
                std.debug.print("error: unexpected cli argument '{s}'\n\n", .{arg});
                fatal.help();
            }
        }

        return .{
            .host = host orelse "localhost",
            .port = port orelse 1990,
            .debounce = debounce orelse 25,
            .build_assets = build_assets,
            .drafts = drafts orelse false,
        };
    }
};
/// like fs.path.dirname but ensures a final `/`
// fn dirNameWithSlash(path: []const u8) []const u8 {
//     const d = std.fs.path.dirname(path).?;
//     if (d.len > 1) {
//         return path[0 .. d.len + 1];
//     } else {
//         return "/";
//     }
// }

pub const Server = struct {
    gpa: Allocator,
    channel: *Channel(ServeEvent),
    build: *const Build,
    build_lock: *std.Thread.RwLock,

    pub const max_connection_header_size: usize = 8 * 1024;

    pub fn init(
        gpa: Allocator,
        channel: *Channel(ServeEvent),
        build: *const Build,
        build_lock: *std.Thread.RwLock,
    ) Server {
        return .{
            .gpa = gpa,
            .channel = channel,
            .build = build,
            .build_lock = build_lock,
        };
    }

    pub fn start(s: *Server, cmd: Command) !std.net.Address {
        const host = if (cmd.host[0] == '[')
            cmd.host[1..][0 .. cmd.host.len - 2] // Strip brackets from IPv6
        else
            cmd.host;
        const list = try std.net.getAddressList(s.gpa, host, cmd.port);
        errdefer list.deinit();

        if (list.addrs.len == 0) fatal.msg(
            "error: unable to resolve host '{s}'",
            .{cmd.host},
        );

        const t = try std.Thread.spawn(.{}, Server.serve, .{ s, list });
        t.detach();

        return list.addrs[0];
    }

    fn serve(s: *Server, list: *std.net.AddressList) void {
        defer list.deinit();

        errdefer |err| switch (err) {
            error.OutOfMemory => fatal.oom(),
        };

        const address = list.addrs[0];
        var tcp_server = address.listen(
            .{ .reuse_address = true },
        ) catch |err| fatal.msg(
            "error: unable to bind to '{any}': {s}",
            .{ address, @errorName(err) },
        );
        defer tcp_server.deinit();

        // const server_port = tcp_server.listen_address.in.getPort();

        while (true) {
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
                    continue;
                },
            };

            const t = std.Thread.spawn(.{}, Server.handleConnection, .{
                s,
                conn,
            }) catch |err| fatal.msg(
                "error: unable to spawn connection thread: {s}",
                .{@errorName(err)},
            );
            t.detach();
        }
    }

    fn handleConnection(
        s: *Server,
        conn: std.net.Server.Connection,
    ) void {
        defer conn.stream.close();

        var buffer: [max_connection_header_size]u8 = undefined;
        var arena_state = std.heap.ArenaAllocator.init(s.gpa);
        const arena = arena_state.allocator();

        var http_server = std.http.Server.init(conn, &buffer);

        while (http_server.state == .ready) {
            var request = http_server.receiveHead() catch |err| {
                if (err != error.HttpConnectionClosing) {
                    log.debug("connection error: {s}\n", .{@errorName(err)});
                }
                return;
            };

            log.debug("request: {s}", .{request.head.target});
            s.handleRequest(arena, &request) catch |err| {
                log.debug("failed request: {s}", .{@errorName(err)});
                return;
            };
            _ = arena_state.reset(.retain_capacity);
        }
    }

    fn handleRequest(
        server: *Server,
        arena: Allocator,
        req: *std.http.Server.Request,
    ) !void {
        var path_with_query = req.head.target;

        if (std.mem.indexOf(u8, path_with_query, "..")) |_| {
            std.debug.print("'..' not allowed in URLs\n", .{});
            @panic("TODO: check if '..' is fine");
        }

        if (std.mem.indexOfScalar(u8, path_with_query, '%')) |_| {
            const buffer = try arena.dupe(u8, path_with_query);
            path_with_query = std.Uri.percentDecodeInPlace(buffer);
        }

        var path = path_with_query[0 .. std.mem.indexOfScalar(
            u8,
            path_with_query,
            '?',
        ) orelse path_with_query.len];

        switch (server.build.cfg.*) {
            .Site => |s| {
                if (s.url_path_prefix.len > 0) {
                    if (!std.mem.startsWith(u8, path[1..], s.url_path_prefix)) {
                        return sendOutsideOfPathPrefix(
                            arena,
                            req,
                            s.url_path_prefix,
                        );
                    }

                    var len = s.url_path_prefix.len;
                    if (s.url_path_prefix[len - 1] == '/') len -= 1;
                    path = path[1 + len ..];

                    if (path.len == 0) {
                        return appendSlashRedirect(
                            arena,
                            req,
                            path_with_query,
                        ) catch |err| fatal.file(path, err);
                    }
                }
            },
            .Multilingual => {},
        }

        const path_ends_with_slash = std.mem.endsWith(u8, path, "/");

        if (path_ends_with_slash) {
            path = try std.fmt.allocPrint(arena, "{s}{s}", .{
                path,
                "index.html",
            });
        }

        if (std.mem.eql(u8, path, "/__zine/zinereload.js")) {
            req.respond(zinereload_js, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/javascript" },
                    // .{ .name = "connection", .value = "close" },
                },
            }) catch |err| log.debug(
                "error while sending http response: {}",
                .{err},
            );

            log.debug("sent livereload script", .{});
            return;
        }

        if (std.mem.eql(u8, path, "/__zine/ws")) {
            server.handleWebsocket(req);
            return error.Websocket;
        }

        const ext = std.fs.path.extension(path);
        const mime_type = mime.extension_map.get(ext) orelse
            .@"application/octet-stream";

        server.build_lock.lockShared();
        defer server.build_lock.unlockShared();

        if (server.build.any_prerendering_error) return sendError(
            arena,
            req,
            "No page was built because of a pre-rendering error.",
        );

        // Site asset search
        not_found: {
            const site_asset = server.build.site_assets.get(PathName.get(
                &server.build.st,
                &server.build.pt,
                path,
            ) orelse break :not_found) orelse break :not_found;

            if (site_asset.load(.acquire) == 0) {
                return sendNotFound(
                    arena,
                    req,
                    true,
                ) catch |err| fatal.file(path, err);
            }

            return sendFile(
                arena,
                req,
                server.build.site_assets_dir,
                mime_type,
                path[1..],
            ) catch |err| fatal.file(path, err);
        }

        for (server.build.variants) |*v| {
            if (!std.mem.startsWith(u8, path[1..], v.output_path_prefix)) continue;
            const subpath = path[1..][v.output_path_prefix.len..][@intFromBool(v.output_path_prefix.len > 0 and path_ends_with_slash)..];

            const hint = v.urls.get(PathName.get(
                &v.string_table,
                &v.path_table,
                subpath,
            ) orelse continue) orelse continue;

            const page = &v.pages.items[hint.id];
            if (hint.kind != .page_asset) {
                if (!page._parse.active) return sendError(
                    arena,
                    req,
                    "This page is not active",
                );

                if (page._parse.status != .parsed) return sendError(
                    arena,
                    req,
                    "This page failed to parse",
                );

                if (page._analysis.frontmatter.items.len > 0) return sendError(
                    arena,
                    req,
                    "This page has frontmatter errors",
                );

                if (page._analysis.page.items.len > 0) return sendError(
                    arena,
                    req,
                    "This page contains SuperMD errors",
                );

                // TODO: why not just send the error directly for good measure?
                if (page._render.errors.len > 0) return sendError(
                    arena,
                    req,
                    "This page contains rendering errors",
                );
            }

            switch (hint.kind) {
                .page_main, .page_alias => {
                    return sendHtml(
                        arena,
                        req,
                        page._render.out,
                    ) catch |err| fatal.file(path, err);
                },
                .page_alternative => |name| {
                    const idx = for (page.alternatives, 0..) |alt, idx| {
                        if (std.mem.eql(u8, alt.name, name)) {
                            break idx;
                        }
                    } else unreachable;

                    // NOTE: some alternatives might be XML!
                    return sendAlternative(
                        arena,
                        req,
                        subpath,
                        page._render.alternatives[idx].out,
                    ) catch |err| fatal.file(path, err);
                },
                .page_asset => |pa| {
                    if (pa.load(.acquire) == 0) {
                        return sendNotFound(
                            arena,
                            req,
                            true,
                        ) catch |err| fatal.file(path, err);
                    }

                    return sendFile(
                        arena,
                        req,
                        v.content_dir,
                        mime_type,
                        subpath,
                    ) catch |err| fatal.file(path, err);
                },
            }
        }

        const normalized_path = std.mem.trimLeft(u8, path, "/");
        for (server.build.build_assets.entries.items(.value)) |ba| {
            const output_path = ba.output_path orelse continue;
            if (!std.mem.eql(u8, normalized_path, output_path)) continue;
            return sendFile(
                arena,
                req,
                server.build.base_dir,
                mime_type,
                ba.input_path,
            ) catch |err| fatal.file(path, err);
        }

        if (!path_ends_with_slash) {
            return appendSlashRedirect(
                arena,
                req,
                path_with_query,
            ) catch |err| fatal.file(path, err);
        } else {
            return sendNotFound(
                arena,
                req,
                false,
            ) catch |err| fatal.file(path, err);
        }
    }

    fn sendAlternative(
        arena: Allocator,
        req: *std.http.Server.Request,
        path: []const u8,
        src: []const u8,
    ) !void {
        const ext = std.fs.path.extension(path);
        const mime_type = mime.extension_map.get(ext) orelse
            .@"application/octet-stream";

        if (mime_type == .@"text/html") {
            return sendHtml(arena, req, src);
        }

        req.respond(src, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = @tagName(mime_type) },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
    }

    fn sendHtml(
        arena: Allocator,
        req: *std.http.Server.Request,
        src: []const u8,
    ) !void {
        const injection =
            \\<script defer src="/__zine/zinereload.js"></script>
        ;
        const head = "</head>";
        const head_pos = std.mem.indexOf(u8, src, head) orelse src.len;

        const injected = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
            src[0..head_pos],
            injection,
            src[head_pos..],
        });

        req.respond(injected, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
    }

    fn sendOutsideOfPathPrefix(
        arena: Allocator,
        req: *std.http.Server.Request,
        path: []const u8,
    ) !void {
        const data = try std.fmt.allocPrint(arena, outside_html, .{path});

        req.respond(data, .{
            .status = .not_found,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
        log.debug("outside of perfix path", .{});
    }

    fn sendError(
        arena: Allocator,
        req: *std.http.Server.Request,
        msg: []const u8,
    ) !void {
        const data = try std.fmt.allocPrint(arena, error_html, .{msg});

        req.respond(data, .{
            .status = .not_found,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
        log.debug("not found", .{});
    }

    fn sendNotFound(
        arena: Allocator,
        req: *std.http.Server.Request,
        /// Set to true when the asset exists but it was not referenced anywhere
        /// and thus would not be installed.
        not_installed: bool,
    ) !void {
        const msg = switch (not_installed) {
            true => "This path does exist but it was never referenced in the build!",
            false => "This path does not exist!",
        };

        const data = try std.fmt.allocPrint(arena, not_found_html, .{msg});

        req.respond(data, .{
            .status = .not_found,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                // .{ .name = "connection", .value = "close" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
        log.debug("not found", .{});
    }

    fn sendFile(
        arena: Allocator,
        req: *std.http.Server.Request,
        dir: std.fs.Dir,
        mime_type: mime.Type,
        file_path: []const u8,
    ) !void {
        assert(file_path[0] != '/');

        const contents = try dir.readFileAlloc(
            arena,
            file_path,
            std.math.maxInt(usize),
        );

        if (mime_type == .@"text/html") {
            return sendHtml(arena, req, contents);
        }

        req.respond(contents, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = @tagName(mime_type) },
                // .{ .name = "connection", .value = "close" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
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

        req.respond(not_found_html, .{
            .status = .see_other,
            .extra_headers = &.{
                .{ .name = "location", .value = location },
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "connection", .value = "close" },
            },
        }) catch |err| log.debug(
            "error while sending http response: {}",
            .{err},
        );
        log.debug("append final slash redirect", .{});
    }

    fn handleWebsocket(s: *Server, req: *std.http.Server.Request) void {
        var buf: [4096]u8 = undefined;
        const conn = ws.Connection.init(req, &buf) catch |err| {
            std.debug.print(
                "warning: failed to establish a websocket connection: {s}\n",
                .{@errorName(err)},
            );
            return;
        };
        s.channel.put(.{ .connect = conn });

        while (true) {
            var buf1: [4096]u8 = undefined;
            const msg = conn.readMessage(&buf1) catch |err| {
                log.debug("readWs error: {s} {any}", .{ @errorName(err), conn });
                s.channel.put(.{ .disconnect = conn });
                return;
            };
            _ = msg;
        }
    }
};

pub const Debouncer = struct {
    cascade_window_ms: i64,

    cascade_mutex: std.Thread.Mutex = .{},
    cascade_condition: std.Thread.Condition = .{},
    cascade_start_ms: i64 = 0,
    channel: *Channel(ServeEvent),

    /// Thread-safe. To be called when a new event comes in
    pub fn newEvent(d: *Debouncer) void {
        {
            d.cascade_mutex.lock();
            defer d.cascade_mutex.unlock();
            d.cascade_start_ms = std.time.milliTimestamp();
        }
        d.cascade_condition.signal();
    }

    pub fn start(d: *Debouncer) !void {
        const t = try std.Thread.spawn(.{}, Debouncer.notify, .{d});
        t.detach();
    }

    pub fn notify(d: *Debouncer) void {
        while (true) {
            d.cascade_mutex.lock();
            defer d.cascade_mutex.unlock();

            while (d.cascade_start_ms == 0) {
                // no active cascade
                d.cascade_condition.wait(&d.cascade_mutex);
            }
            // cascade != 0
            while (true) {
                const time_passed = std.time.milliTimestamp() - d.cascade_start_ms;
                if (time_passed >= d.cascade_window_ms) break;
                d.cascade_mutex.unlock();
                const sleep_ms = d.cascade_window_ms - time_passed;
                std.Thread.sleep(@intCast(sleep_ms * std.time.ns_per_ms));
                d.cascade_mutex.lock();
            }

            // We have slept enough, "commit" the cascade window and
            // trigger a new build.
            d.cascade_start_ms = 0;
            d.channel.put(.change);
        }
    }
};
