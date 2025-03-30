const std = @import("std");
const supermd = @import("supermd");
const tracy = @import("tracy");
const root = @import("../root.zig");
const hl = @import("../highlight.zig");
const context = @import("../context.zig");
const StringTable = @import("../StringTable.zig");
const PathTable = @import("../PathTable.zig");
const Path = PathTable.Path;
const PathName = PathTable.PathName;
const c = supermd.c;
const highlightCode = hl.highlightCode;
const HtmlSafe = @import("superhtml").HtmlSafe;
const Ast = supermd.Ast;
const Iter = Ast.Iter;

const log = std.log.scoped(.render);

pub fn html(
    gpa: std.mem.Allocator,
    ctx: *const context.Template,
    page: *const context.Page,
    start: supermd.Node,
    w: anytype,
) !void {
    const zone = tracy.traceNamed(@src(), "html");
    defer zone.end();

    const ast = page._parse.ast;

    // Footnotes are disconnected from the main ast tree so we cannot
    // start an iterator from the document's root node when rendering
    // one (which happens on-demand by pointing `start` at a footnote node).
    const root_node = if (start.nodeType() == .FOOTNOTE_DEFINITION) start else ast.md.root;
    var it = Iter.init(root_node);

    const full_page = start.n == ast.md.root.n;
    var event: ?Iter.Event = if (!full_page) blk: {
        it.reset(start, .enter);
        break :blk .{ .node = start, .dir = .enter };
    } else it.next();

    var open_div = false;
    var table_in_header = false;
    var table_alignments: []const u8 = &.{};
    var table_cell_id: usize = 0;
    while (event) |ev| : (event = it.next()) {
        // const loop_zone = tracy.traceNamed(@src(), "html-event");
        // defer loop_zone.end();

        const node = ev.node;
        const node_is_section = if (node.getDirective()) |d|
            d.kind == .section and node.nodeType() != .LINK
        else
            false;

        // var buf: [1024]u8 = undefined;
        // tracy.messageCopy(std.fmt.bufPrint(&buf, "{} {s}", .{
        //     node.nodeType(),
        //     @tagName(ev.dir),
        // }) catch unreachable);

        log.debug("node ({}, {s}, {?s}) = {} {s} \n({*} == {*} {})", .{
            node_is_section,
            if (node.getDirective()) |d| @tagName(d.kind) else "<>",
            if (node.getDirective()) |d| d.id else null,
            node.nodeType(),
            @tagName(ev.dir),
            node.n,
            start.n,
            node.n != start.n,
        });

        if (!full_page and node_is_section and node.n != start.n) {
            log.debug("done, breaking", .{});
            break;
        }

        switch (node.nodeType()) {
            .DOCUMENT => {},
            .BLOCK_QUOTE => switch (ev.dir) {
                .enter => {
                    const d = node.getDirective() orelse {
                        try w.print("<blockquote>", .{});
                        continue;
                    };

                    try w.print("<div", .{});
                    if (d.id) |id| try w.print(" id=\"{s}\"", .{id});
                    try w.print(" class=\"block", .{});
                    if (d.attrs) |attrs| {
                        for (attrs) |attr| try w.print(" {s}", .{attr});
                    }
                    try w.print("\">", .{});
                },
                .exit => {
                    if (node.getDirective() == null) {
                        try w.print("</blockquote>", .{});
                        continue;
                    } else {
                        try w.print("</div>", .{});
                    }
                },
            },
            .LIST => switch (ev.dir) {
                .enter => try w.print("<{s}>", .{
                    @tagName(node.listType()),
                }),
                .exit => try w.print("</{s}>", .{
                    @tagName(node.listType()),
                }),
            },
            .ITEM => switch (ev.dir) {
                .enter => try w.print("<li>", .{}),
                .exit => try w.print("</li>", .{}),
            },
            .HTML_BLOCK => switch (ev.dir) {
                .enter => try w.print(
                    "{s}",
                    .{node.literal() orelse ""},
                ),
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
                    .enter => {
                        if (node.getDirective()) |d| {
                            if (open_div) {
                                try w.print("</div>", .{});
                            }
                            open_div = true;
                            try w.print("<div", .{});
                            if (d.id) |id| try w.print(" id=\"{s}\"", .{id});
                            if (d.attrs) |attrs| {
                                try w.print(" class=\"", .{});
                                for (attrs) |attr| try w.print("{s} ", .{attr});
                                try w.print("\"", .{});
                            }

                            try w.print(">", .{});
                            _ = it.next();
                            _ = it.next();
                            if (node.firstChild().?.nextSibling() == null) {
                                continue;
                            }
                        }

                        try w.print("<p>", .{});
                    },
                    .exit => {
                        if (node.getDirective() != null) {
                            if (node.firstChild().?.nextSibling() == null) {
                                continue;
                            }
                        }
                        try w.print("</p>", .{});
                    },
                }
            },
            .HEADING => switch (ev.dir) {
                .enter => {
                    if (node.getDirective()) |d| switch (d.kind) {
                        else => {},
                        .heading => {
                            try w.print("<h{}", .{node.headingLevel()});
                            try w.print(" id=\"{s}\"", .{d.id.?});
                            if (d.attrs) |attrs| {
                                try w.print(" class=\"", .{});
                                for (attrs) |attr| try w.print("{s} ", .{attr});
                                try w.print("\"", .{});
                            }

                            try w.print(">", .{});
                            continue;
                        },
                        .section => {
                            if (open_div) {
                                try w.print("</div>", .{});
                            }
                            open_div = true;
                            try w.print("<div", .{});
                            try w.print(" id=\"{s}\"", .{d.id.?});
                            if (d.attrs) |attrs| {
                                try w.print(" class=\"", .{});
                                for (attrs) |attr| try w.print("{s} ", .{attr});
                                try w.print("\"", .{});
                            }

                            try w.print(">", .{});
                        },
                    };

                    try w.print("<h{}>", .{node.headingLevel()});
                },
                .exit => try w.print("</h{}>", .{node.headingLevel()}),
            },
            .THEMATIC_BREAK => switch (ev.dir) {
                .enter => try w.print("<hr>", .{}),
                .exit => {},
            },
            .FOOTNOTE_REFERENCE => switch (ev.dir) {
                .enter => {
                    const literal = node.literal().?;
                    const def_idx = ast.footnotes.getIndex(literal).?;
                    const footnote = ast.footnotes.values()[def_idx];
                    try w.print("<sup class=\"footnote-ref\"><a href=\"#{s}\" id=\"{s}\">{d}</a></sup>", .{
                        footnote.def_id,
                        footnote.ref_ids[@intCast(node.footnoteRefIx() - 1)],
                        def_idx + 1,
                    });
                },
                .exit => {},
            },
            .FOOTNOTE_DEFINITION => switch (ev.dir) {
                .enter => {},
                .exit => {},
            },
            .HTML_INLINE => switch (ev.dir) {
                .enter => try w.print(
                    "{s}",
                    .{node.literal() orelse ""},
                ),
                .exit => @panic("custom inline"),
            },
            .CUSTOM_INLINE => switch (ev.dir) {
                .enter => @panic("custom inline"),
                .exit => {},
            },
            .TEXT => switch (ev.dir) {
                .enter => try w.print("{s}", .{
                    node.literal() orelse "",
                }),
                .exit => {},
            },
            .SOFTBREAK => switch (ev.dir) {
                .enter => try w.print(" ", .{}),
                .exit => {},
            },
            .LINEBREAK => switch (ev.dir) {
                .enter => try w.print("<br>", .{}),
                .exit => {},
            },
            .CODE => switch (ev.dir) {
                .enter => try w.print("<code>{s}</code>", .{
                    HtmlSafe{ .bytes = node.literal() orelse "" },
                }),
                .exit => {},
            },
            .EMPH => switch (ev.dir) {
                .enter => try w.print("<em>", .{}),
                .exit => try w.print("</em>", .{}),
            },
            .STRONG => switch (ev.dir) {
                .enter => try w.print("<strong>", .{}),
                .exit => try w.print("</strong>", .{}),
            },
            .LINK, .IMAGE => try renderDirective(gpa, ctx, page, ast, ev, w),
            .CODE_BLOCK => switch (ev.dir) {
                .exit => {},
                .enter => {
                    if (node.literal()) |code| {
                        const fence_info = node.fenceInfo() orelse "";
                        if (std.mem.trim(u8, fence_info, " \n").len == 0) {
                            try w.print("<pre><code>{s}</code></pre>", .{
                                HtmlSafe{ .bytes = code },
                            });
                        } else {
                            var fence_it = std.mem.tokenizeScalar(u8, fence_info, ' ');
                            const lang_name = fence_it.next().?;

                            if (std.mem.eql(u8, lang_name, "=html")) {
                                try w.writeAll(code);
                                continue;
                            }

                            try w.print("<pre><code class=\"{s}\">", .{lang_name});

                            highlightCode(
                                gpa,
                                lang_name,
                                code,
                                w,
                            ) catch |err| switch (err) {
                                error.OutOfMemory => return error.OutOfMemory,
                                // Already validated in analyzePage
                                else => unreachable,
                            };
                            try w.writeAll("</code></pre>\n");
                        }
                    }
                },
            },

            else => |nt| if (@intFromEnum(nt) == c.CMARK_NODE_STRIKETHROUGH) switch (ev.dir) {
                .enter => try w.writeAll("<del>"),
                .exit => try w.writeAll("</del>"),
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE) switch (ev.dir) {
                .enter => {
                    table_alignments = node.getTableAlignments();
                    try w.writeAll("<table>");
                },
                .exit => {
                    table_alignments = &.{};
                    try w.writeAll("</table>");
                },
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE_ROW) switch (ev.dir) {
                .enter => {
                    table_in_header = node.isTableHeader();
                    try w.writeAll("<tr>");
                },
                .exit => {
                    table_in_header = !node.isTableHeader();
                    table_cell_id = 0;
                    try w.writeAll("</tr>");
                },
            } else if (@intFromEnum(nt) == c.CMARK_NODE_TABLE_CELL) switch (ev.dir) {
                .enter => {
                    if (table_in_header) {
                        try w.writeAll("<th");
                    } else {
                        try w.writeAll("<td");
                    }

                    if (table_cell_id < table_alignments.len) {
                        const char = table_alignments[table_cell_id];
                        if (char != 0) try w.print(" align='{s}'", .{
                            switch (char) {
                                else => unreachable,
                                'l' => "left",
                                'c' => "center",
                                'r' => "right",
                            },
                        });
                    }
                    table_cell_id += 1;

                    try w.writeAll(">");
                },
                .exit => {
                    if (table_in_header) {
                        try w.writeAll("</th>");
                    } else {
                        try w.writeAll("</td>");
                    }
                },
            } else std.debug.panic(
                "TODO: implement support for {x}",
                .{node.nodeType()},
            ),
        }
    }
    if (open_div) {
        try w.writeAll("</div>");
    }
}

fn renderDirective(
    gpa: std.mem.Allocator,
    ctx: *const context.Template,
    page: *const context.Page,
    ast: Ast,
    ev: Iter.Event,
    w: anytype,
) !void {
    const zone = tracy.trace(@src());
    defer zone.end();
    _ = ast;
    const node = ev.node;
    const directive = node.getDirective() orelse return renderLink(ev, ctx, w);
    switch (directive.kind) {
        .section, .block, .heading => {},
        .text => switch (ev.dir) {
            .enter => {
                try w.print("<span", .{});
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.print(" class=\"", .{});
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.print("\"", .{});
                }
                if (directive.title) |t| try w.print(" title=\"{s}\"", .{t});
                try w.print(">", .{});
            },
            .exit => {
                try w.print("</span>", .{});
            },
        },
        .image => |img| switch (ev.dir) {
            .enter => {
                const caption = node.firstChild();
                if (caption != null) try w.writeAll("<figure>");
                if (img.linked) |l| if (l) {
                    try w.writeAll("<a href=\"");
                    try printUrl(ctx, page, img.src.?, w);
                    try w.writeAll("\">");
                };

                try w.writeAll("<img");
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.writeAll(" class=\"");
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.writeAll("\"");
                }
                if (directive.title) |t| try w.print(" title=\"{s}\"", .{t});
                try w.writeAll(" src=\"");
                try printUrl(ctx, page, img.src.?, w);
                try w.writeAll("\"");

                if (img.alt) |alt| try w.print(" alt=\"{s}\"", .{alt});
                if (img.size) |size| try w.print(" width=\"{d}\" height=\"{d}\"", .{ size.w, size.h });
                try w.writeAll(">");
                if (img.linked) |l| if (l) try w.writeAll("</a>");
                if (caption != null) try w.writeAll("\n<figcaption>");
            },
            .exit => {
                const caption = node.firstChild();
                if (caption != null) {
                    try w.writeAll("</figcaption></figure>");
                }
            },
        },
        .video => |vid| switch (ev.dir) {
            .enter => {
                const caption = node.firstChild();
                if (caption != null) try w.writeAll("<figure>");
                try w.writeAll("<video");
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.writeAll(" class=\"");
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.writeAll("\"");
                }
                if (directive.title) |t| try w.print(" title=\"{s}\"", .{t});
                if (vid.loop) |val| if (val) try w.writeAll(" loop");
                if (vid.autoplay) |val| if (val) try w.writeAll(" autoplay");
                if (vid.muted) |val| if (val) try w.writeAll(" muted");
                if (vid.controls) |val| if (val) try w.writeAll(" controls");
                if (vid.pip) |val| if (!val) {
                    try w.writeAll(" disablepictureinpicture");
                };
                try w.writeAll(">\n<source src=\"");
                try printUrl(ctx, page, vid.src.?, w);
                try w.writeAll("\">\n</video>");
                if (caption != null) try w.writeAll("\n<figcaption>");
            },
            .exit => {
                const caption = node.firstChild();
                if (caption != null) {
                    try w.writeAll("</figcaption></figure>");
                }
            },
        },
        .link => |lnk| switch (ev.dir) {
            .enter => {
                try w.writeAll("<a");
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.writeAll(" class=\"");
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.writeAll("\"");
                }

                if (directive.title) |t| try w.print(" title=\"{s}\"", .{t});
                try w.writeAll(" href=\"");
                try printUrl(ctx, page, lnk.src.?, w);
                if (lnk.ref) |r| try w.print("#{s}", .{r});
                try w.writeAll("\"");

                if (lnk.new) |n| if (n) try w.writeAll(" target=\"_blank\"");
                try w.writeAll(">");
            },
            .exit => try w.writeAll("</a>"),
        },
        .code => |code| switch (ev.dir) {
            .enter => {
                const caption = node.firstChild();
                if (caption != null) try w.writeAll("<figure>");
                if (std.mem.eql(u8, code.language orelse "", "=html")) {
                    try w.writeAll(code.src.?.url);
                } else {
                    try w.writeAll("<pre");
                    if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                    if (directive.attrs) |attrs| {
                        if (code.language == null) try w.writeAll(" class=\"");
                        for (attrs) |attr| try w.print("{s} ", .{attr});
                    }

                    if (directive.title) |t| try w.print(" title=\"{s}\"", .{t});
                    try w.print("><code class=\"{?s}\">", .{code.language});

                    if (code.language) |lang| {
                        highlightCode(
                            gpa,
                            lang,
                            code.src.?.url,
                            w,
                        ) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            // We assert success because the language code was
                            // validated during the page analysis phase.
                            else => unreachable,
                        };
                    } else {
                        try w.print("{s}", .{HtmlSafe{ .bytes = code.src.?.url }});
                    }

                    try w.writeAll("</code></pre>");
                }
                if (caption != null) try w.writeAll("\n<figcaption>");
            },
            .exit => {
                const caption = node.firstChild();
                if (caption != null) {
                    try w.writeAll("</figcaption></figure>");
                }
            },
        },
    }
}

fn printUrl(
    ctx: *const context.Template,
    page: *const context.Page,
    src: supermd.context.Src,
    w: anytype,
) !void {
    switch (src) {
        .url => |url| try w.writeAll(url),
        .self_page => |alt| if (alt) |a| {
            try ctx.printLinkPrefix(
                w,
                page._scan.variant_id,
                // We are not checking the variant id so two different pages
                // might have the same id in different variant arrays, but we
                // don't care because, when the variant is different, the full
                // host url will be printed anyway.
                // NOTE: `p.resolved.page_id` is not the same as `page._scan.page_id`
                page != ctx.page,
            );

            if (a[0] != '/') {
                const v = ctx._meta.build.variants[page._scan.variant_id];
                try w.print("{}", .{page._scan.url.fmt(
                    &v.string_table,
                    &v.path_table,
                    null,
                    true,
                )});
            }

            try w.writeAll(a);
        },
        .page => |p| {
            try ctx.printLinkPrefix(
                w,
                p.resolved.variant_id,
                // We are not checking the variant id so two different pages
                // might have the same id in different variant arrays, but we
                // don't care because, when the variant is different, the full
                // host url will be printed anyway.
                // NOTE: `p.resolved.page_id` is not the same as `page._scan.page_id`
                page != ctx.page,
            );

            const path: Path = @enumFromInt(p.resolved.path);
            const v = ctx._meta.build.variants[p.resolved.variant_id];
            if (p.resolved.alt) |a| {
                if (a[0] != '/') {
                    try w.print("{}", .{path.fmt(
                        &v.string_table,
                        &v.path_table,
                        null,
                        true,
                    )});
                }
                try w.writeAll(a);
            } else {
                try w.print("{}", .{path.fmt(
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
            try w.print("{/}", .{pn.fmt(
                &v.string_table,
                &v.path_table,
                null,
            )});
        },
        .site_asset => |sa| {
            try printAssetUrlPrefix(ctx, page, w);

            const pn: PathName = .{
                .path = @enumFromInt(sa.resolved.path),
                .name = @enumFromInt(sa.resolved.name),
            };

            try w.print("{/}", .{pn.fmt(
                &ctx._meta.build.st,
                &ctx._meta.build.pt,
                null,
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
    w: anytype,
) !void {
    switch (ctx.site._meta.kind) {
        .simple => |url_prefix_path| {
            if (ctx.page != page) {
                try w.print("{/}/", .{
                    root.fmtJoin(&.{
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
                try w.print("{/}", .{
                    std.fs.path.fmtJoin(&.{
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
    w: anytype,
) !void {
    _ = ctx;
    const node = ev.node;
    switch (ev.dir) {
        .enter => {
            try w.print("<a href=\"{s}\">", .{
                node.link() orelse "",
            });
        },
        .exit => try w.print("</a>", .{}),
    }
}

pub fn htmlToc(ast: Ast, w: anytype) !void {
    try w.print("<ul>\n", .{});
    var lvl: i32 = 1;
    var first_item = true;
    var node: ?supermd.Node = ast.md.root.firstChild();
    while (node) |n| : (node = n.nextSibling()) {
        if (n.nodeType() != .HEADING) continue;
        defer first_item = false;

        const new_lvl = n.headingLevel();
        if (new_lvl > lvl) {
            if (first_item) {
                try w.print("<li>\n", .{});
            }
            while (new_lvl > lvl) : (lvl += 1) {
                try w.print("<ul><li>\n", .{});
            }

            try tocRenderHeading(n, w);
        } else if (new_lvl < lvl) {
            try w.print("</li>", .{});
            while (new_lvl < lvl) : (lvl -= 1) {
                try w.print("</ul></li>", .{});
            }
            try w.print("<li>", .{});
            try tocRenderHeading(n, w);
        } else {
            if (first_item) {
                try w.print("<li>", .{});
                try tocRenderHeading(n, w);
            } else {
                try w.print("</li><li>", .{});
                try tocRenderHeading(n, w);
            }
        }
    }

    while (lvl > 1) : (lvl -= 1) {
        try w.print("</li></ul>", .{});
    }

    try w.print("</ul>", .{});
}

fn tocRenderHeading(heading: supermd.Node, w: anytype) !void {
    var it = Iter.init(heading);
    while (it.next()) |ev| {
        const node = ev.node;
        switch (node.nodeType()) {
            else => std.debug.panic(
                "TODO: implement toc '{s}' inline rendering",
                .{@tagName(node.nodeType())},
            ),
            .HEADING => switch (ev.dir) {
                .enter => {
                    const dir = node.getDirective() orelse continue;
                    if (dir.id) |id| {
                        std.debug.assert(id.len > 0);
                        std.debug.assert(std.mem.trim(u8, id, "\t\n\r ").len > 0);
                        try w.print("<a href=\"#{s}\">", .{id});
                    }
                },
                .exit => {
                    const dir = node.getDirective() orelse continue;
                    if (dir.id != null) {
                        try w.print("</a>", .{});
                    }
                },
            },
            .TEXT => switch (ev.dir) {
                .enter => try w.print("{s}", .{
                    node.literal() orelse "",
                }),
                .exit => {},
            },
            .SOFTBREAK => switch (ev.dir) {
                .enter => try w.print(" ", .{}),
                .exit => {},
            },
            .LINEBREAK => switch (ev.dir) {
                .enter => try w.print("<br>", .{}),
                .exit => {},
            },
            .CODE => switch (ev.dir) {
                .enter => try w.print("<code>{s}</code>", .{
                    HtmlSafe{ .bytes = node.literal() orelse "" },
                }),
                .exit => {},
            },
            .EMPH => switch (ev.dir) {
                .enter => try w.print("<em>", .{}),
                .exit => try w.print("</em>", .{}),
            },
            .STRONG => switch (ev.dir) {
                .enter => try w.print("<strong>", .{}),
                .exit => try w.print("</strong>", .{}),
            },
            .LINK => {},
        }
    }
}
