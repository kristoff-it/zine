const Reloader = @This();
const std = @import("std");
const builtin = @import("builtin");
const AnsiRenderer = @import("AnsiRenderer.zig");

const log = std.log.scoped(.watcher);
const ListenerFn = fn (self: *Reloader, path: []const u8, name: []const u8) void;
const Watcher = switch (builtin.target.os.tag) {
    .linux => @import("watcher/LinuxWatcher.zig"),
    .macos => @import("watcher/MacosWatcher.zig"),
    .windows => @import("watcher/WindowsWatcher.zig"),
    else => @compileError("unsupported platform"),
};

gpa: std.mem.Allocator,
zig_exe: []const u8,
out_dir_path: []const u8,
website_step_name: []const u8,
debug: bool,
include_drafts: bool,
watcher: Watcher,

clients_lock: std.Thread.Mutex = .{},
clients: std.AutoArrayHashMapUnmanaged(std.net.Stream, void) = .{},

pub fn init(
    gpa: std.mem.Allocator,
    zig_exe: []const u8,
    out_dir_path: []const u8,
    in_dir_paths: []const []const u8,
    website_step_name: []const u8,
    debug: bool,
    include_drafts: bool,
) !Reloader {
    return .{
        .gpa = gpa,
        .zig_exe = zig_exe,
        .out_dir_path = out_dir_path,
        .website_step_name = website_step_name,
        .debug = debug,
        .include_drafts = include_drafts,
        .watcher = try Watcher.init(gpa, out_dir_path, in_dir_paths),
    };
}

pub fn listen(self: *Reloader) !void {
    try self.watcher.listen(self.gpa, self);
}

pub fn onInputChange(self: *Reloader, path: []const u8, name: []const u8) void {
    _ = name;
    _ = path;
    const args: []const []const u8 = blk: {
        var args_count: usize = 3;
        var all_args: [5][]const u8 = .{
            self.zig_exe,
            "build",
            self.website_step_name,
            "",
            "",
        };

        if (self.include_drafts) {
            all_args[args_count] = "-Dinclude-drafts";
            args_count += 1;
        }
        if (self.debug) {
            all_args[args_count] = "-Ddebug";
            args_count += 1;
        }

        break :blk all_args[0..args_count];
    };
    log.debug("re-building! args: {s}", .{args});

    const result = std.process.Child.run(.{
        .allocator = self.gpa,
        .argv = args,
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
        std.debug.print("{s}\n\n", .{result.stderr});
    } else {
        std.debug.print("File change triggered a successful build.\n", .{});
    }

    self.clients_lock.lock();
    defer self.clients_lock.unlock();

    const html_err = AnsiRenderer.renderSlice(self.gpa, result.stderr) catch |err| err: {
        log.err("error rendering the ANSI-encoded error message: {s}", .{@errorName(err)});
        break :err result.stderr;
    };
    defer self.gpa.free(html_err);

    var idx: usize = 0;
    while (idx < self.clients.entries.len) {
        const conn = self.clients.entries.get(idx).key;

        conn.writeAll("event: build\n") catch |err| {
            log.debug("error writing to sse: {s}", .{
                @errorName(err),
            });
            self.clients.swapRemoveAt(idx);
            continue;
        };

        conn.writer().print("data: {s}\n\n", .{html_err}) catch |err| {
            log.debug("error writing to sse: {s}", .{
                @errorName(err),
            });
            self.clients.swapRemoveAt(idx);
            continue;
        };

        idx += 1;
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

        conn.writeAll("event: reload\n") catch |err| {
            log.debug("error writing to sse: {s}", .{
                @errorName(err),
            });
            self.clients.swapRemoveAt(idx);
            continue;
        };

        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "data: {s}/{s}\n\n", .{
            path[self.out_dir_path.len..],
            name,
        }) catch {
            log.err("unable to generate sse message", .{});
            return;
        };
        if (std.fs.path.sep != '/') {
            std.mem.replaceScalar(u8, msg, std.fs.path.sep, '/');
        }

        conn.writeAll(msg) catch |err| {
            log.debug("error writing to sse: {s}", .{
                @errorName(err),
            });
            self.clients.swapRemoveAt(idx);
            continue;
        };

        idx += 1;
    }
}
