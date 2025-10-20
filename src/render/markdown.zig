const std = @import("std");
const Writer = std.io.Writer;

const supermd = @import("supermd");
const c = supermd.c;
const Ast = supermd.Ast;
const Iter = Ast.Iter;
const tracy = @import("tracy");

const context = @import("../context.zig");
const PathTable = @import("../PathTable.zig");
const Path = PathTable.Path;
const PathName = PathTable.PathName;
const root = @import("../root.zig");
const StringTable = @import("../StringTable.zig");

const log = std.log.scoped(.render);

pub fn markdown(
    ctx: *const context.Template,
    page: *const context.Page,
    start: supermd.Node,
    w: *Writer,
) !void {
    const zone = tracy.traceNamed(@src(), "markdown");
    defer zone.end();

    const ast = page._parse.ast;

    const root_node = if (start.nodeType() == .FOOTNOTE_DEFINITION) start else ast.md.root;
    var it = Iter.init(root_node);

    const full_page = start.n == ast.md.root.n;
    var event: ?Iter.Event = if (!full_page) blk: {
        it.reset(start, .enter);
        break :blk .{ .node = start, .dir = .enter };
    } else it.next();

    var list_depth: u32 = 0;
    var table_in_header = false;
    var table_alignments: []const u8 = &.{};
    var table_cell_id: usize = 0;

    while (event) |ev| : (event = it.next()) {
        const node = ev.node;
        const node_is_section = if (node.getDirective()) |d|
            d.kind == .section and node.nodeType() != .LINK
        else
            false;

        if (!full_page and node_is_section and node.n != start.n) {
            break;
        }
        switch (node.nodeType()) {
            .DOCUMENT => {},
            .BLOCK_QUOTE => switch (ev.dir) {
                .enter => try w.writeAll("> "),
                .exit => try w.writeAll("\n"),
            },
            .LIST => switch (ev.dir) {
                .enter => list_depth += 1,
                .exit => {
                    list_depth -= 1;
                    if (list_depth == 0) try w.writeAll("\n");
                },
            },
            .ITEM => switch (ev.dir) {
                .enter => {
                    var i = list_depth - 1;
                    while (i > 0) : (i -= 1) {
                        try w.writeAll("  ");
                    }
                    if (node.parent().?.listType() == .ul) {
                        try w.writeAll("* ");
                    } else {
                        try w.writeAll("1. ");
                    }
                },
                .exit => try w.writeAll("\n"),
            },
            .HTML_BLOCK => switch (ev.dir) {
                .enter => try w.print("{s}", .{node.literal() orelse ""}),
                .exit => {},
            },
            .CUSTOM_BLOCK => switch (ev.dir) {
                .enter => {},
                .exit => {},
            },
            .PARAGRAPH => {
                if (node.parent()) |p|
                    if (p.parent()) |gp|
                        if (gp.listIsTight()) continue;

                switch (ev.dir) {
                    .enter => {},
                    .exit => try w.writeAll("\n\n"),
                }
            },
            .HEADING => switch (ev.dir) {
                .enter => {
                    var i: u32 = 0;
                    while (i < node.headingLevel()) : (i += 1) {
                        try w.writeAll("#");
                    }
                    try w.writeAll(" ");
                },
                .exit => try w.writeAll("\n\n"),
            },
            .THEMATIC_BREAK => switch (ev.dir) {
                .enter => try w.writeAll("---\n\n"),
                .exit => {},
            },
            .FOOTNOTE_REFERENCE => switch (ev.dir) {
                .enter => {
                    const literal = node.literal().?;
                    try w.print("[^{s}]", .{literal});
                },
                .exit => {},
            },
            .FOOTNOTE_DEFINITION => switch (ev.dir) {
                .enter => {
                    const literal = node.literal().?;
                    try w.print("[^{s}]: ", .{literal});
                },
                .exit => try w.writeAll("\n"),
            },
            .HTML_INLINE => switch (ev.dir) {
                .enter => try w.print("{s}", .{node.literal() orelse ""}),
                .exit => {},
            },
            .CUSTOM_INLINE => switch (ev.dir) {
                .enter => {},
                .exit => {},
            },
            .TEXT => switch (ev.dir) {
                .enter => try w.print("{s}", .{node.literal() orelse ""}),
                .exit => {},
            },
            .SOFTBREAK => switch (ev.dir) {
                .enter => try w.writeAll("\n"),
                .exit => {},
            },
            .LINEBREAK => switch (ev.dir) {
                .enter => try w.writeAll("  \n"),
                .exit => {},
            },
            .CODE => switch (ev.dir) {
                .enter => try w.print("`{s}`", .{node.literal() orelse ""}),
                .exit => {},
            },
            .EMPH => switch (ev.dir) {
                .enter => try w.writeAll("*"),
                .exit => try w.writeAll("*"),
            },
            .STRONG => switch (ev.dir) {
                .enter => try w.writeAll("**"),
                .exit => try w.writeAll("**"),
            },
            .LINK, .IMAGE => try renderDirective(ctx, page, ast, ev, w),
            .CODE_BLOCK => switch (ev.dir) {
                .exit => {},
                .enter => {
                    try w.writeAll("```");
                    if (node.fenceInfo()) |info| {
                        try w.writeAll(info);
                    }
                    try w.writeAll("\n");
                    if (node.literal()) |code| {
                        try w.writeAll(code);
                    }
                    try w.writeAll("\n```\n");
                    _ = it.next();
                },
            },

            else => |nt| if (@intFromEnum(nt) == c.CMARK_NODE_STRIKETHROUGH) switch (ev.dir) {
                .enter => try w.writeAll("~~"),
                .exit => try w.writeAll("~~"),
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE) switch (ev.dir) {
                .enter => {
                    table_alignments = node.getTableAlignments();
                },
                .exit => {
                    table_alignments = &.{};
                    try w.writeAll("\n");
                },
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE_ROW) switch (ev.dir) {
                .enter => {
                    table_in_header = node.isTableHeader();
                    table_cell_id = 0;
                    try w.writeAll("|");
                },
                .exit => {
                    if (table_in_header) {
                        try w.writeAll("\n|");
                        for (table_alignments) |t_align| {
                            switch (t_align) {
                                'l' => try w.writeAll(":--"),
                                'c' => try w.writeAll(":-:"),
                                'r' => try w.writeAll("--:"),
                                else => try w.writeAll("---"),
                            }
                            try w.writeAll("|");
                        }
                    }
                    try w.writeAll("\n");
                },
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE_CELL) switch (ev.dir) {
                .enter => {
                    try w.writeAll(" ");
                },
                .exit => {
                    try w.writeAll(" |");
                    table_cell_id += 1;
                },
            } else std.debug.panic(
                "TODO: implement support for {s}",
                .{@tagName(node.nodeType())},
            ),
        }
    }
}

fn renderDirective(
    ctx: *const context.Template,
    page: *const context.Page,
    ast: Ast,
    ev: Iter.Event,
    w: *Writer,
) !void {
    _ = ast;
    const node = ev.node;
    const directive = node.getDirective() orelse return renderLink(ev, ctx, w);
    switch (directive.kind) {
        .section, .block, .heading => {},
        .mathtex => |katek| switch (ev.dir) {
            .enter => {
                try w.writeAll("$$");
                try w.writeAll(katek.formula);
                try w.writeAll("$$");
            },
            .exit => {},
        },
        .text => {},
        .image => |img| switch (ev.dir) {
            .enter => {
                if (img.linked) |l| if (l) {
                    try w.writeAll("[");
                };
                try w.writeAll("![");
            },
            .exit => {
                try w.writeAll("](");
                try printUrl(ctx, page, img.src.?, w);
                if (directive.title) |t| try w.print(" \"{s}\"", .{t});
                try w.writeAll(")");
                if (img.linked) |l| if (l) {
                    try w.writeAll("](");
                    try printUrl(ctx, page, img.src.?, w);
                    try w.writeAll(")");
                };
            },
        },
        .video => |vid| switch (ev.dir) {
            .enter => {
                try w.writeAll("<video");
                if (vid.loop) |val| if (val) try w.writeAll(" loop");
                if (vid.autoplay) |val| if (val) try w.writeAll(" autoplay");
                if (vid.muted) |val| if (val) try w.writeAll(" muted");
                if (vid.controls) |val| if (val) try w.writeAll(" controls");
                try w.writeAll("><source src=\"");
                try printUrl(ctx, page, vid.src.?, w);
                try w.writeAll("\">\n</video>");
            },
            .exit => {},
        },
        .link => |lnk| switch (ev.dir) {
            .enter => {
                try w.writeAll("[");
            },
            .exit => {
                try w.writeAll("](");
                try printUrl(ctx, page, lnk.src.?, w);
                if (lnk.ref) |r| try w.print("#{s}", .{r});
                try w.writeAll(")");
            },
        },
        .code => |code| switch (ev.dir) {
            .enter => {
                try w.writeAll("```");
                if (code.language) |lang| try w.writeAll(lang);
                try w.writeAll("\n");
                try w.writeAll(code.src.?.url);
                try w.writeAll("\n```\n");
            },
            .exit => {},
        },
    }
}

fn printUrl(
    ctx: *const context.Template,
    page: *const context.Page,
    src: supermd.context.Src,
    w: *Writer,
) !void {
    switch (src) {
        .url => |url| try w.writeAll(url),
        .self_page => |alt| if (alt) |a| {
            try ctx.printLinkPrefix(
                w,
                page._scan.variant_id,
                page != ctx.page,
            );

            if (a[0] != '/') {
                const v = ctx._meta.build.variants[page._scan.variant_id];
                try w.print("{f}", .{page._scan.url.fmt(
                    &v.string_table,
                    &v.path_table,
                    null,
                    true,
                )});
            }

            try w.writeAll(std.mem.trimLeft(u8, a, "/"));
        },
        .page => |p| {
            try ctx.printLinkPrefix(
                w,
                p.resolved.variant_id,
                page != ctx.page,
            );

            const path: Path = @enumFromInt(p.resolved.path);
            const v = ctx._meta.build.variants[p.resolved.variant_id];
            if (p.resolved.alt) |a| {
                if (a[0] != '/') {
                    try w.print("{f}", .{path.fmt(
                        &v.string_table,
                        &v.path_table,
                        null,
                        true,
                    )});
                }
                try w.writeAll(a);
            } else {
                try w.print("{f}", .{path.fmt(
                    &v.string_table,
                    &v.path_table,
                    null,
                    true,
                )});
            }
        },
        .page_asset => |pa| {
            try ctx.printLinkPrefix(
                w,
                page._scan.variant_id,
                page != ctx.page,
            );

            const pn: PathName = .{
                .path = @enumFromInt(pa.resolved.path),
                .name = @enumFromInt(pa.resolved.name),
            };

            const v = ctx._meta.build.variants[page._scan.variant_id];
            try w.print("{f}", .{pn.fmt(
                &v.string_table,
                &v.path_table,
                null,
                "/",
            )});
        },
        .site_asset => |sa| {
            try printAssetUrlPrefix(ctx, page, w);

            const pn: PathName = .{
                .path = @enumFromInt(sa.resolved.path),
                .name = @enumFromInt(sa.resolved.name),
            };

            try w.print("{f}", .{pn.fmt(
                &ctx._meta.build.st,
                &ctx._meta.build.pt,
                null,
                "/",
            )});
        },
        .build_asset => |ba| {
            try printAssetUrlPrefix(ctx, page, w);
            try w.print("{s}", .{ba.ref});
        },
    }
}

pub fn printAssetUrlPrefix(
    ctx: *const context.Template,
    page: *const context.Page,
    w: *Writer,
) !void {
    switch (ctx.site._meta.kind) {
        .simple => |url_prefix_path| {
            if (ctx.page != page) {
                try w.print("{f}/", .{
                    root.fmtJoin('/', &.{
                        ctx.site.host_url,
                        url_prefix_path,
                    }),
                });
            } else if (url_prefix_path.len > 0) {
                try w.print("/{s}/", .{url_prefix_path});
            } else {
                try w.writeAll("/");
            }
        },
        .multi => |locale| {
            const assets_prefix_path = ctx._meta.build.cfg.Multilingual.assets_prefix_path;
            if (ctx.page != page or locale.host_url_override != null) {
                try w.print("{f}", .{
                    root.fmtJoin('/', &.{
                        ctx.site.host_url,
                        assets_prefix_path,
                    }),
                });
            } else {
                try w.writeAll("/");
                if (assets_prefix_path.len > 0) {
                    try w.print("{s}/", .{assets_prefix_path});
                }
            }
        },
    }
}
fn renderLink(
    ev: Iter.Event,
    ctx: *const context.Template,
    w: *Writer,
) !void {
    _ = ctx;
    const node = ev.node;
    switch (ev.dir) {
        .enter => {
            try w.writeAll("[");
        },
        .exit => try w.print("]({s})", .{
            node.link() orelse "",
        }),
    }
}
