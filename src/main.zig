const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const tracy = @import("tracy");
const fatal = @import("fatal.zig");
const worker = @import("worker.zig");
const root = @import("root.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.main);

pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

const Command = enum {
    init,
    release,
    debug,
    help,
    @"-h",
    @"--help",
    version,
    @"-v",
    @"--version",
    // Because other ssgs have them:
    serve,
    server,
    dev,
    develop,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
pub const gpa = if (builtin.single_threaded)
    debug_allocator.allocator()
else
    std.heap.smp_allocator;

pub fn main() u8 {
    errdefer |err| switch (err) {
        error.OutOfMemory, error.Overflow => fatal.oom(),
    };

    root.progress = std.Progress.start(.{ .draw_buffer = &root.progress_buf });
    defer root.progress.end();

    if (builtin.mode == .Debug) {
        std.debug.print(
            \\*-----------------------------------------------*
            \\|    WARNING: THIS IS A DEBUG BUILD OF ZINE     |
            \\|-----------------------------------------------|
            \\| Debug builds enable expensive sanity checks   |
            \\| that reduce performance.                      |
            \\|                                               |
            \\| To create a release build, run:               |
            \\|                                               |
            \\|           zig build --release=fast            |
            \\|                                               |
            \\| If you're investigating a bug in Zine, then a |
            \\| debug build might turn confusing behavior     |
            \\| into a crash.                                 |
            \\|                                               |
            \\| To disable all forms of concurrency, you can  |
            \\| add the following flag to your build command: |
            \\|                                               |
            \\|              -Dsingle-threaded                |
            \\|                                               |
            \\*-----------------------------------------------*
            \\
            \\
        , .{});
    }
    if (tracy.enable) {
        std.debug.print(
            \\*-----------------------------------------------*
            \\|            WARNING: TRACING ENABLED           |
            \\|-----------------------------------------------|
            \\| Tracing introduces a significant performance  |
            \\| overhead.                                     |
            \\|                                               |
            \\| If you're not interested in tracing Zine,     |
            \\| remove `-Dtracy` when building again.         |
            \\*-----------------------------------------------*
            \\
            \\
        , .{});
    }

    if (options.tsan) {
        std.debug.print(
            \\*-----------------------------------------------*
            \\|             WARNING: TSAN ENABLED             |
            \\|-----------------------------------------------|
            \\| Thread sanitizer introduces a significant     |
            \\| performance overhead.                         |
            \\|                                               |
            \\| If you're not interested in debugging         |  
            \\| concurrency bugs in Zine, remove `-Dtsan`     |
            \\| when building again.                          |
            \\*-----------------------------------------------*
            \\
            \\
        , .{});
    }

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const cmd = blk: {
        if (args.len >= 2) {
            if (std.meta.stringToEnum(Command, args[1])) |cmd| {
                break :blk cmd;
            }
        }

        @import("cli/serve.zig").serve(gpa, args[1..]);
    };

    const any_error = switch (cmd) {
        .init => @import("cli/init.zig").init(gpa, args[2..]),
        .release => @import("cli/release.zig").release(gpa, args[2..]),
        .debug => @import("cli/debug.zig").debug(gpa, args[2..]),
        .help, .@"-h", .@"--help" => fatal.help(),
        .version, .@"-v", .@"--version" => printVersion(),
        .serve, .server, .dev, .develop => {
            std.debug.print(
                "error: run zine without subcommand to start the development web server\n\n",
                .{},
            );
            fatal.help();
        },
    };

    return @intFromBool(any_error);
}

fn printVersion() noreturn {
    std.debug.print("{s}\n", .{options.version});
    std.process.exit(0);
}
