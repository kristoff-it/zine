const std = @import("std");
const supermd = @import("supermd");
const hl = @import("../highlight.zig");
const c = supermd.c;
const highlightCode = hl.highlightCode;
const HtmlSafe = hl.HtmlSafe;
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
    const lvl = start.headingLevel();
    var event: ?Iter.Event = .{ .node = start, .dir = .enter };
    while (event) |ev| : (event = it.next()) {
        const node = ev.node;
        const node_lvl = node.headingLevel();
        if (node_lvl > 0 and node_lvl <= lvl and node.n != start.n) break;
        switch (node.nodeType()) {
            .DOCUMENT => {},
            .BLOCK_QUOTE => switch (ev.dir) {
                .enter => try w.print("<blockquote>", .{}),
                .exit => try w.print("</blockquote>", .{}),
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
            .PARAGRAPH => switch (ev.dir) {
                .enter => try w.print("<p>", .{}),
                .exit => try w.print("</p>", .{}),
            },
            .HEADING => switch (ev.dir) {
                .enter => {
                    try w.print("<h{}", .{node.headingLevel()});
                    if (node.getDirective()) |d| {
                        try w.print(" id={s}>", .{d.id.?});
                    } else {
                        try w.print(">", .{});
                    }
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
                .enter => try w.print("<br><br>", .{}),
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
                const src = img.src.?.url;
                try w.print(" src=\"{s}\"", .{src});
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
        else => unreachable,
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
