const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const Variant = @import("../Variant.zig");
const Section = Variant.Section;
const Allocator = std.mem.Allocator;
const BuildAsset = root.BuildAsset;

pub fn debug(
    gpa: Allocator,
    args: []const []const u8,
) bool {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cmd: Command = try .parse(gpa, args);

    const cfg, const base_dir_path = root.Config.load(gpa);

    worker.start();
    defer if (builtin.mode == .Debug) worker.stopWaitAndDeinit();

    // build_assets: *const std.StringArrayHashMapUnmanaged(BuildAsset) = .empty;
    const build = root.run(gpa, &cfg, .{
        .base_dir_path = base_dir_path,
        .build_assets = &.empty,
        .drafts = false,
        .mode = .memory,
    });

    defer if (builtin.mode == .Debug) build.deinit(gpa);

    for (build.variants, 0..) |*variant, vidx| {
        std.debug.print(
            \\----------------------------
            \\       -- VARIANT --
            \\----------------------------
            \\.id = {},
            \\.content_dir_path = {s}
            \\
        , .{
            vidx,
            build.cfg.Site.content_dir_path,
        });

        std.mem.sort(Section, variant.sections.items, variant, struct {
            pub fn lessThan(v: *Variant, lhs: Section, rhs: Section) bool {
                var bl: [std.fs.max_path_bytes]u8 = undefined;
                var br: [std.fs.max_path_bytes]u8 = undefined;
                return std.mem.order(
                    u8,
                    std.fmt.bufPrint(&bl, "{}", .{
                        lhs.content_sub_path.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                            false,
                        ),
                    }) catch unreachable,
                    std.fmt.bufPrint(&br, "{}", .{
                        rhs.content_sub_path.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                            false,
                        ),
                    }) catch unreachable,
                ) == .lt;
            }
        }.lessThan);
        for (variant.sections.items[1..], 1..) |*s, idx| {
            std.debug.print(
                \\
                \\  ------- SECTION -------
                \\.index = {},
                \\.section_path = {},
                \\.pages = [
                \\
            , .{
                idx, s.content_sub_path.fmt(
                    &variant.string_table,
                    &variant.path_table,
                    variant.content_dir_path,
                    true,
                ),
            });

            for (s.pages.items) |p_idx| {
                const p = variant.pages.items[p_idx];

                std.debug.print("    {}", .{
                    p._scan.file.fmt(
                        &variant.string_table,
                        &variant.path_table,
                        variant.content_dir_path,
                    ),
                });

                if (cmd.ids) {
                    std.debug.print(" ({})", .{p_idx});

                    if (p._scan.subsection_id != 0) {
                        std.debug.print(" [{}]", .{p._scan.subsection_id});
                    }
                }

                std.debug.print("\n", .{});
            }

            std.debug.print("],\n\n", .{});
        }

        var it = variant.urls.iterator();
        while (it.next()) |kv| {
            const pn = kv.key_ptr;
            const lh = kv.value_ptr;
            if (lh.kind == .page_asset) {
                std.debug.print("{} ({})\n", .{
                    pn.fmt(
                        &variant.string_table,
                        &variant.path_table,
                        null,
                    ),
                    lh.id,
                });
            }
        }
    }

    if (build.any_prerendering_error or
        build.any_rendering_error.load(.acquire))
    {
        return true;
    }

    return false;
}

pub const Command = struct {
    build_assets: std.StringArrayHashMapUnmanaged(BuildAsset),
    drafts: bool,
    ids: bool,

    pub fn deinit(co: *const Command, gpa: Allocator) void {
        var ba = co.build_assets;
        ba.deinit(gpa);
    }

    pub fn parse(gpa: Allocator, args: []const []const u8) !Command {
        var build_assets: std.StringArrayHashMapUnmanaged(BuildAsset) = .empty;
        var drafts = false;
        var ids = false;

        const eql = std.mem.eql;
        const startsWith = std.mem.startsWith;
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                fatal.msg(help_message, .{});
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
            } else if (eql(u8, arg, "--ids")) {
                ids = true;
            } else {
                fatal.msg("error: unexpected cli argument '{s}'\n", .{arg});
            }
        }

        return .{
            .build_assets = build_assets,
            .drafts = drafts,
            .ids = ids,
        };
    }
};

const help_message =
    \\Usage: zine debug [OPTIONS]
    \\
    \\Command specific options:
    \\  --ids        Include ids when printing info. Snapshot unsafe!
    // \\  --build-assets FILE    Path to a file containing a list of build assets
    \\  --help, -h   Show this help menu
    \\
    \\
;
