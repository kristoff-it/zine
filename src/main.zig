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
    serve,
    release,
    tree,
    help,
    @"-h",
    @"--help",
    version,
    @"-v",
    @"--version",
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

    if (args.len < 2) fatalHelp();

    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        std.debug.print(
            "unrecognized subcommand: '{s}'\n\n",
            .{args[1]},
        );
        fatalHelp();
    };

    const any_error = switch (cmd) {
        .init => @import("cli/init.zig").init(gpa, args[2..]),
        .serve => @import("cli/serve.zig").serve(gpa, args[2..]),
        .release => @import("cli/release.zig").release(gpa, args[2..]),
        .tree => @panic("TODO"),
        .help, .@"-h", .@"--help" => fatalHelp(),
        .version, .@"-v", .@"--version" => printVersion(),
    };

    return @intFromBool(any_error);
}

// pub fn showTree(
//     arena: Allocator,
//     build: *const Build,
// ) !void {
//     const sep = std.fs.path.sep;
//     for (build.variants, 0..) |variant, vidx| {
//         std.debug.print(
//             \\----------------------------
//             \\       -- VARIANT --
//             \\----------------------------
//             \\.id = {},
//             \\.content_dir_path = {s}
//             \\
//         , .{
//             vidx,
//             build.cfg.Site.content_dir_path,
//         });
//         for (variant.sections.items[1..], 1..) |s, idx| {
//             var path: std.ArrayListUnmanaged(u8) = .{};
//             {
//                 const csp = s.content_sub_path.slice(&variant.path_table);
//                 for (csp) |c| {
//                     try path.appendSlice(arena, c.slice(&variant.string_table));
//                     try path.append(arena, sep);
//                 }
//             }

//             std.debug.print(
//                 \\
//                 \\  ------- SECTION -------
//                 \\.index = {},
//                 \\.section_path = {s},
//                 \\.pages = [
//                 \\
//             , .{
//                 idx,
//                 path.items,
//             });

//             for (s.pages.items) |p_idx| {
//                 const p = variant.pages.items[p_idx];

//                 path.clearRetainingCapacity();
//                 const csp = p._scan.md_path.slice(&variant.path_table);
//                 for (csp) |c| {
//                     try path.appendSlice(arena, c.slice(&variant.string_table));
//                     try path.append(arena, sep);
//                 }

//                 std.debug.print("   {s}{s}", .{
//                     path.items,
//                     p._scan.md_name.slice(&variant.string_table),
//                 });

//                 if (p._scan.subsection_id != 0) {
//                     std.debug.print(" #{}\n", .{p._scan.subsection_id});
//                 } else {
//                     std.debug.print("\n", .{});
//                 }
//             }

//             std.debug.print("],\n\n", .{});
//         }
//     }
// }

fn printVersion() noreturn {
    @panic("TODO");
    // std.debug.print("{s}\n", .{build_options.version});
    // std.process.exit(0);
}

pub fn fatalHelp() noreturn {
    std.debug.print(
        \\Usage: zine COMMAND [OPTIONS]
        \\
        \\Commands:
        \\  init          Initialize a zine site in the current directory
        \\  serve         Start the development server
        \\  release       Create a release of a Zine website
        \\  tree          Show the content tree for the site
        \\  help          Show this menu and exit
        \\  version       Print the Zine version and exit
        \\
        \\General Options:
        \\  --help, -h   Print command specific usage
        \\
        \\
    , .{});
    std.process.exit(1);
}
