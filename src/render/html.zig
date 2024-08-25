const std = @import("std");
const supermd = @import("supermd");
const hl = @import("../highlight.zig");
const c = supermd.c;
const highlightCode = hl.highlightCode;
const HtmlSafe = @import("superhtml").HtmlSafe;
const Ast = supermd.Ast;
const Iter = Ast.Iter;

const log = std.log.scoped(.layout);

pub fn html(
    gpa: std.mem.Allocator,
    ast: Ast,
    start: supermd.Node,
    // path to the file, used in error messages
    path: []const u8,
    w: anytype,
) !void {
    var it = Iter.init(ast.md.root);
    it.reset(start, .enter);

    const full_page = start.n == ast.md.root.n;

    var open_div = false;
    var event: ?Iter.Event = .{ .node = start, .dir = .enter };
    while (event) |ev| : (event = it.next()) {
        const node = ev.node;
        const node_is_block = if (node.getDirective()) |d|
            d.kind == .block
        else
            false;

        if (!full_page and node_is_block and node.n != start.n) break;
        switch (node.nodeType()) {
            .DOCUMENT => {},
            .BLOCK_QUOTE => switch (ev.dir) {
                .enter => {
                    const d = node.getDirective() orelse {
                        try w.print("<blockquote>", .{});
                        continue;
                    };

                    try w.print("<div", .{});
                    if (d.id) |id| try w.print(" id={s}", .{id});
                    if (d.attrs) |attrs| {
                        try w.print(" class=\"", .{});
                        for (attrs) |attr| try w.print("{s} ", .{attr});
                        try w.print("\"", .{});
                    }

                    try w.print(">", .{});
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
                            if (d.id) |id| try w.print(" id={s}", .{id});
                            if (d.attrs) |attrs| {
                                try w.print(" class=\"", .{});
                                for (attrs) |attr| try w.print("{s} ", .{attr});
                                try w.print("\"", .{});
                            }

                            try w.print(">", .{});
                            event = it.next();
                            event = it.next();
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
                            try w.print(" id={s}", .{d.id.?});
                            if (d.attrs) |attrs| {
                                try w.print(" class=\"", .{});
                                for (attrs) |attr| try w.print("{s} ", .{attr});
                                try w.print("\"", .{});
                            }

                            try w.print(">", .{});
                            continue;
                        },
                        .block => {
                            if (open_div) {
                                try w.print("</div>", .{});
                            }
                            open_div = true;
                            try w.print("<div", .{});
                            try w.print(" id={s}", .{d.id.?});
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
            .FOOTNOTE_DEFINITION => switch (ev.dir) {
                .enter => @panic("TODO: FOOTNOTE_DEFINITION"),
                .exit => @panic("TODO: FOOTNOTE_DEFINITION"),
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
            .LINK => try renderDirective(gpa, ast, ev, w),
            .IMAGE => switch (ev.dir) {
                .enter => {
                    const url = node.link() orelse "";
                    const title = node.title();
                    if (title) |t| {
                        try w.print(
                            "<figure data-title=\"{s}\"><img src=\"{s}\" alt=\"",
                            .{ t, url },
                        );
                    } else {
                        try w.print("<img src=\"{s}\" alt=\"", .{url});
                    }
                },
                .exit => {
                    if (node.title()) |t| {
                        try w.print("\" title=\"{s}\"></figure>", .{t});
                    } else {
                        try w.print("\">", .{});
                    }
                },
            },

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

                            const line = node.startLine();
                            const col = node.startColumn();
                            highlightCode(
                                gpa,
                                lang_name,
                                code,
                                w,
                            ) catch |err| switch (err) {
                                error.NoLanguage => {
                                    std.debug.print(
                                        \\{s}:{}:{}
                                        \\Unable to find highlighting queries for language '{s}'
                                        \\
                                    ,
                                        .{ path, line, col, lang_name },
                                    );
                                    std.process.exit(1);
                                },
                                else => {
                                    std.debug.print(
                                        \\{s}:{}:{}
                                        \\Error while syntax highlighting: {s}
                                        \\
                                    ,
                                        .{ path, line, col, @errorName(err) },
                                    );
                                    std.process.exit(1);
                                },
                            };
                            try w.writeAll("</code></pre>\n");
                        }
                    }
                },
            },

            else => switch (ev.dir) {
                .enter => {
                    const rendered_html = c.cmark_render_html(
                        node.n,
                        c.CMARK_OPT_DEFAULT,
                        ast.md.extensions,
                    );
                    try w.writeAll(std.mem.span(rendered_html));
                    it.exit(node);
                    // std.debug.panic("TODO: implement support for {x}", .{node.nodeType()});
                },
                .exit => {

                    // const html = c.cmark_render_html(node.n, c.CMARK_OPT_DEFAULT, extensions);
                    // try w.writeAll(std.mem.span(html));
                    // std.debug.panic("TODO: implement exit for {x}", .{node.nodeType()});
                },
            },
        }
    }
    if (open_div) {
        try w.writeAll("</div>");
    }
}

fn renderDirective(
    gpa: std.mem.Allocator,
    ast: Ast,
    ev: Iter.Event,
    w: anytype,
) !void {
    _ = gpa;
    _ = ast;
    const node = ev.node;
    const directive = node.getDirective() orelse return renderLink(ev, w);
    switch (directive.kind) {
        .block, .heading, .box => {},
        .image => |img| switch (ev.dir) {
            .enter => {
                if (img.caption != null) try w.print("<figure>", .{});
                try w.print("<img", .{});
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.print(" class=\"", .{});
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.print("\"", .{});
                }
                try w.print(" src=\"{s}\"", .{img.src.?.url});
                if (img.alt) |alt| try w.print(" alt=\"{s}\"", .{alt});
                try w.print(">", .{});
                if (img.caption) |caption| try w.print(
                    "\n<figcaption>{s}</figcaption>\n</figure>",
                    .{caption},
                );
            },
            .exit => {},
        },
        .video => |vid| switch (ev.dir) {
            .enter => {
                try w.print("<video", .{});
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.print(" class=\"", .{});
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.print("\"", .{});
                }
                if (vid.loop) |val| if (val) try w.print(" loop", .{});
                if (vid.autoplay) |val| if (val) try w.print(" autoplay", .{});
                if (vid.muted) |val| if (val) try w.print(" muted", .{});
                if (vid.controls) |val| if (val) try w.print(" controls", .{});
                if (vid.pip) |val| if (!val) {
                    try w.print(" disablepictureinpicture", .{});
                };
                const src = vid.src.?.url;
                try w.print(">\n<source src=\"{s}\">\n</video>", .{src});
            },
            .exit => {},
        },
        .link => |lnk| switch (ev.dir) {
            .enter => {
                try w.print("<a", .{});
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    try w.print(" class=\"", .{});
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                    try w.print("\"", .{});
                }

                try w.print(" href=\"{s}", .{lnk.src.?.url});
                if (lnk.ref) |r| try w.print("#{s}", .{r});
                try w.print("\"", .{});

                if (lnk.target) |t| try w.print(" target=\"{s}\"", .{t});
                try w.print(">", .{});
            },
            .exit => try w.print("</a>", .{}),
        },
        .code => |code| switch (ev.dir) {
            .enter => {
                try w.print("<pre", .{});
                if (directive.id) |id| try w.print(" id=\"{s}\"", .{id});
                if (directive.attrs) |attrs| {
                    if (code.language == null) try w.print(" class=\"", .{});
                    for (attrs) |attr| try w.print("{s} ", .{attr});
                }

                try w.print("><code class=\"{?s}\">", .{code.language});

                // In this case src.url contains the prerendered source code
                try w.writeAll(code.src.?.url);
            },
            .exit => try w.print("</code></pre>", .{}),
        },
    }
}

fn renderLink(
    ev: Iter.Event,
    w: anytype,
) !void {
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

        // skip blocks with no heading text
        if (n.getDirective()) |d| {
            if (d.kind == .block) {
                const link = n.firstChild().?;
                if (link.firstChild() == null) continue;
            }
        }

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
    var event: ?Iter.Event = .{ .node = heading, .dir = .enter };
    while (event) |ev| : (event = it.next()) {
        const node = ev.node;
        switch (node.nodeType()) {
            else => std.debug.panic(
                "TODO: implement toc '{s}' inline rendering",
                .{@tagName(node.nodeType())},
            ),
            .HEADING => switch (ev.dir) {
                .enter => {
                    const dir = node.getDirective() orelse continue;
                    if (dir.kind == .block) {
                        if (dir.id) |id| {
                            try w.print("<a href=\"#{s}\">", .{id});
                        }
                    }
                },
                .exit => {
                    const dir = node.getDirective() orelse continue;
                    if (dir.kind == .block) {
                        if (dir.id != null) {
                            try w.print("</a>", .{});
                        }
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

// ## Foo
// ### bar

// <ul>
//   <li>
//     <ul>
//       <li> foo
//          <ul>
//            <li> bar </li>
//          </ul>
//       </li>
//     </ul>
//   </li>
// </ul>
