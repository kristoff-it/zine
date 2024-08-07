const std = @import("std");
const builtin = @import("builtin");
const scripty = @import("scripty");
const ziggy = @import("ziggy");
const zine = @import("zine");
const supermd = @import("supermd");
const context = zine.context;
const hl = zine.highlight;
const highlightCode = hl.highlightCode;
const HtmlSafe = hl.HtmlSafe;

const log = std.log.scoped(.layout);

const asset_collector = &@import("layout.zig").asset_collector;

pub fn render(
    arena: std.mem.Allocator,
    md_path: []const u8,
    md_rel_path: []const u8,
    url_path_prefix: []const u8,
    index_in_section: ?usize,
    parent_section_path: ?[]const u8,
    // Pass null when loading the page through Scripty,
    // assets should be referenced for real only by the
    // layout process that builds the target page.
    maybe_dep_writer: ?std.io.AnyWriter,
) !context.Page {
    var time = std.time.Timer.start() catch unreachable;

    defer log.debug(
        "Rendering '{s}' took {}ms ({}ns)\n",
        .{
            md_path,
            time.read() / std.time.ns_per_ms,
            time.read(),
        },
    );

    var is_section = false;
    var md_asset_dir_path: []const u8 = undefined;
    var md_asset_dir_rel_path: []const u8 = undefined;
    if (std.mem.endsWith(u8, md_path, "index.md")) {
        is_section = true;
        md_asset_dir_path = md_path[0 .. md_path.len - "index.md".len];
        md_asset_dir_rel_path = md_rel_path[0 .. md_rel_path.len - "index.md".len];
    } else {
        md_asset_dir_path = md_path[0 .. md_path.len - ".md".len];
        md_asset_dir_rel_path = md_rel_path[0 .. md_rel_path.len - ".md".len];
    }

    const in_file = std.fs.cwd().openFile(md_path, .{}) catch |err| {
        std.debug.print("Error while opening file: {s}\n", .{md_path});
        return err;
    };
    defer in_file.close();

    var buf_reader = std.io.bufferedReader(in_file.reader());
    const r = buf_reader.reader();
    const result = try ziggy.frontmatter.Parser(context.Page).parse(arena, r, null);
    var page = switch (result) {
        .success => |s| s.header,
        else => unreachable,
    };

    const md_src = try r.readAllAlloc(arena, 1024 * 1024 * 10);
    page._meta = .{
        // TODO: unicode this
        .word_count = @intCast(md_src.len / 6),
        .is_section = std.mem.endsWith(u8, md_path, "/index.md"),
        .md_rel_path = md_rel_path,
        .url_path_prefix = url_path_prefix,
        .index_in_section = index_in_section,
        .parent_section_path = parent_section_path,
        .src = md_src,
    };

    const dep_writer = maybe_dep_writer orelse return page;
    const ast = try supermd.Ast(arena, md_src);
    // TODO print errors

    // Only root page gets analized

    var current = ast.md.root;
    while (current.next()) |n| {
        const directive = n.getDirective() orelse continue;

        switch (directive.kind) {
            .image => |img| switch (img.src.?) {
                .url => {},
                .page => |link| {
                    const asset_path =
                        try std.fs.path.join(arena, &.{
                        md_asset_dir_path,
                        link,
                    });

                    const offset = md_asset_dir_path.len - md_asset_dir_rel_path.len;
                    const asset_rel_path = asset_path[offset..asset_path.len];

                    std.fs.cwd().access(asset_path, .{}) catch |err| {
                        std.debug.panic("while parsing page '{s}', unable to find asset '{s}': {s}\n{s}", .{
                            md_rel_path,
                            asset_rel_path,
                            @errorName(err),
                            if (is_section) "" else 
                            \\NOTE: assets for this page must be placed under a subdirectory that shares the same name with the corresponding markdown file!
                            ,
                        });
                    };

                    log.debug("markdown dep: '{s}'", .{asset_path});
                    dep_writer.print("{s} ", .{asset_path}) catch {
                        std.debug.panic(
                            "error while writing to dep file file: '{s}'",
                            .{asset_path},
                        );
                    };

                    _ = try asset_collector.collect(arena, .{
                        .kind = .{ .page = md_asset_dir_rel_path },
                        .ref = link,
                        .path = asset_path,
                    });
                },
                .site => {},
                .build => {},
            },
        }
    }
}
