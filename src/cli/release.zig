const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const Allocator = std.mem.Allocator;
const BuildAsset = root.BuildAsset;

pub fn release(gpa: Allocator, args: []const []const u8) bool {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cmd: Command = try .parse(gpa, args);
    const cfg, const base_dir_path = root.Config.load(gpa);

    worker.start();
    defer if (builtin.mode == .Debug) worker.stopWaitAndDeinit();

    const build = root.run(gpa, &cfg, .{
        .base_dir_path = base_dir_path,
        .build_assets = &cmd.build_assets,
        .drafts = cmd.drafts,
        .mode = .{
            .disk = .{
                .output_dir_path = cmd.output_dir_path,
            },
        },
    }) catch fatal.oom();

    defer if (builtin.mode == .Debug) build.deinit(gpa);

    if (tracy.enable) {
        tracy.frameMarkNamed("waiting for tracy");
        var progress_tracy = root.progress.start("Tracy", 0);
        std.Thread.sleep(100 * std.time.ns_per_ms);
        progress_tracy.end();
    }

    if (build.any_prerendering_error or
        build.any_rendering_error.load(.acquire))
    {
        return true;
    }

    return false;
}

pub const Command = struct {
    output_dir_path: ?[]const u8,
    build_assets: std.StringArrayHashMapUnmanaged(BuildAsset),
    drafts: bool,

    pub fn deinit(co: *const Command, gpa: Allocator) void {
        var ba = co.build_assets;
        ba.deinit(gpa);
    }

    pub fn parse(gpa: Allocator, args: []const []const u8) !Command {
        var output_dir_path: ?[]const u8 = null;
        var build_assets: std.StringArrayHashMapUnmanaged(BuildAsset) = .empty;
        var drafts = false;

        const eql = std.mem.eql;
        const startsWith = std.mem.startsWith;
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                fatal.msg(help_message, .{});
            } else if (eql(u8, arg, "-i") or eql(u8, arg, "--install")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '{s}'",
                    .{arg},
                );
                output_dir_path = args[idx];
            } else if (startsWith(u8, arg, "--install=")) {
                output_dir_path = arg["--install=".len..];
            } else if (startsWith(u8, arg, "--build-asset=")) {
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
                    if (startsWith(u8, next, "--output=")) {
                        output_path = next["--output=".len..];
                    } else if (startsWith(u8, next, "--output-always=")) {
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
            } else if (eql(u8, arg, "--drafts")) {
                drafts = true;
            } else {
                fatal.msg("error: unexpected cli argument '{s}'\n", .{arg});
            }
        }

        return .{
            .output_dir_path = output_dir_path,
            .build_assets = build_assets,
            .drafts = drafts,
        };
    }
};

const help_message =
    \\Usage: zine release [OPTIONS]
    \\
    \\Command specific options:
    \\  --install DIR  Directory where to install the website (default 'public/')
    // \\  --build-assets FILE    Path to a file containing a list of build assets
    \\  --help, -h   Show this help menu
    \\
    \\
;
