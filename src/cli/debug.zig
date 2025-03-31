const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const Allocator = std.mem.Allocator;
const BuildAsset = root.BuildAsset;

pub fn debug(
    gpa: Allocator,
    args: []const []const u8,
) bool {
    _ = args;
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

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

    for (build.variants, 0..) |variant, vidx| {
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
        for (variant.sections.items[1..], 1..) |s, idx| {
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

                std.debug.print("   {} -> {}index.html", .{
                    p._scan.file.fmt(
                        &variant.string_table,
                        &variant.path_table,
                        variant.content_dir_path,
                    ),
                    p._scan.url.fmt(
                        &variant.string_table,
                        &variant.path_table,
                        variant.content_dir_path,
                        true,
                    ),
                });

                if (p._scan.subsection_id != 0) {
                    std.debug.print(" #{}\n", .{p._scan.subsection_id});
                } else {
                    std.debug.print("\n", .{});
                }
            }

            std.debug.print("],\n\n", .{});
        }
    }

    if (build.any_prerendering_error or
        build.any_rendering_error.load(.acquire))
    {
        return true;
    }

    return false;
}
