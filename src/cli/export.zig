const std = @import("std");
const root = @import("../root.zig");
const render = @import("../render.zig");
const fatal = @import("../fatal.zig");
const context = @import("../context.zig");
const BuildAsset = root.BuildAsset;
const Variant = @import("../Variant.zig");
const embed = @import("../render/embed.zig");
const embedCss = embed.embedCss;
const Command = @import("release.zig").Command;
const log = std.log.scoped(.export_cmd);

pub fn exportContent(gpa: std.mem.Allocator, args: []const []const u8) bool {
    exportContentFn(gpa, args) catch |err| {
        fatal.msg("Error during export: {s}", .{@errorName(err)});
        return true;
    };
    return false;
}

fn exportContentFn(gpa: std.mem.Allocator, args: []const []const u8) !void {
    var cmd = try Command.parse(gpa, args, help_message);
    defer cmd.deinit(gpa);

    // 1. Load the Project Configuration
    const cfg, const base_dir_path = root.Config.load(gpa);

    const worker = @import("../worker.zig");
    worker.start();
    defer worker.stopWaitAndDeinit();

    // 2. Initialize Build in 'Memory' mode
    var build = try root.run(gpa, &cfg, .{
        .base_dir_path = base_dir_path,
        .build_assets = &cmd.build_assets, // TODO: this feature needs more tests and modifications
        .drafts = cmd.drafts,
        .mode = .memory,
        .is_export_mode = true,
    });
    defer build.deinit(gpa);

    const export_opts = switch (cfg) {
        .Site => |s| s.@"export",
        .Multilingual => |m| m.@"export",
    };

    // Prepare output base dir
    const output_dir = cmd.output_dir_path orelse export_opts.output_dir;
    try std.fs.cwd().makePath(output_dir);

    // 3. Iterate over variants and generate an output file for each
    for (build.variants) |*variant| {
        const variant_dir_path = if (variant.output_path_prefix.len == 0)
            output_dir
        else
            try std.fs.path.join(gpa, &.{ output_dir, variant.output_path_prefix });
        defer if (variant.output_path_prefix.len > 0) gpa.free(variant_dir_path);

        if (variant.output_path_prefix.len > 0) {
            try std.fs.cwd().makePath(variant_dir_path);
        }

        const output_path = try std.fs.path.join(gpa, &.{ variant_dir_path, export_opts.output_name });
        defer gpa.free(output_path);

        const file = std.fs.cwd().createFile(output_path, .{ .truncate = true, .exclusive = !cmd.force }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                fatal.msg("Error: output file '{s}' already exists. Use --force to overwrite.", .{output_path});
                return;
            },
            else => return err,
        };
        defer file.close();

        var output_buf: [4096]u8 = undefined;
        var writer_state = file.writer(&output_buf);
        const writer = &writer_state.interface;

        for (export_opts.custom_styles) |style_path| {
            _ = embedCss(gpa, build.base_dir, style_path, writer) catch |err| blk: {
                log.err("Failed to embed custom style '{s}': {s}", .{
                    style_path,
                    @errorName(err),
                });
                break :blk false;
            };
        }

        // Find the root page for this variant
        if (variant.root_index) |root_page_id| {
            try renderRecursive(gpa, variant, root_page_id, 1, writer, &build);
        }

        try file.sync();
        var buf: [256]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&buf);
        const stdout = &stdout_writer.interface;
        try stdout.print("Exported to {s}\n", .{output_path});
        try stdout.flush();
    }
}

// Recursive helper function to render pages in hierarchical order
fn renderRecursive(
    gpa: std.mem.Allocator,
    variant: *const Variant,
    page_id: u32,
    current_depth: u32,
    writer: anytype,
    build: *root.Build,
) !void {
    const page = &variant.pages.items[page_id];

    // Skip if page parsing failed or is inactive
    if (!page._parse.active) return;

    // Render Frontmatter as HTML (Title, optional Author/Date)
    try writer.print(
        "<div class=\"zine-page zine-depth-{d}\" id=\"{f}\">\n",
        .{
            current_depth,
            PageIdFormatter{ .page = page, .variant = variant },
        },
    );

    embed.processExportHtml(gpa, build, page, page._render.out, writer) catch |err| {
        log.err("Failed to process HTML for page '{f}': {s}", .{
            PageIdFormatter{ .page = page, .variant = variant },
            @errorName(err),
        });
        // Write original content as fallback
        try writer.writeAll(page._render.out);
    };

    // Recursive call for subpages/subsections
    if (page._scan.subsection_id != 0) { // If this page is a section (index.smd)
        const section = &variant.sections.items[page._scan.subsection_id];
        // Iterate through pages directly contained in this section
        for (section.pages.items) |child_page_id| {
            if (child_page_id == page_id) continue; // Skip self if it's the index page

            // Render child page recursively with increased depth
            try renderRecursive(gpa, variant, child_page_id, current_depth + 1, writer, build);
        }
    }

    try writer.writeAll(
        "</div>\n" // Close zine-page div
    );
}

const PageIdFormatter = struct {
    variant: *const Variant,
    page: *const context.Page,

    pub fn format(
        self: PageIdFormatter,
        writer: anytype,
    ) !void {
        const v = self.variant;
        try writer.print("{f}", .{
            self.page._scan.url.fmt(
                &v.string_table,
                &v.path_table,
                "/", // Ensure leading slash
                false, // No trailing slash
            ),
        });
    }
};

const help_message =
    \\Usage: zine export [OPTIONS]
    \\
    \\Command specific options:
    \\  --output, -o DIR                              Directory where to output the file
    \\  --force, -f                                   Overwrite existing output file
    \\  --build-asset=<NAME> <PATH> [INSTALL_OPTS]    Define a build asset
    \\  --drafts                                      Include draft content
    \\  --help, -h                                    Show this help menu
    \\
    \\
;
