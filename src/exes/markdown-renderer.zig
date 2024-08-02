const std = @import("std");
const builtin = @import("builtin");
const ziggy = @import("ziggy");
const zine = @import("zine");
const context = zine.context;
const hl = zine.highlight;
const highlightCode = hl.highlightCode;
const HtmlSafe = hl.HtmlSafe;

const log = std.log.scoped(.layout);

const asset_collector = &@import("layout.zig").asset_collector;

const c = @cImport({
    @cInclude("cmark-gfm.h");
    @cInclude("cmark-gfm-core-extensions.h");
});

extern fn cmark_list_syntax_extensions([*c]c.cmark_mem) [*c]c.cmark_llist;

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

    const in_string = try r.readAllAlloc(arena, 1024 * 1024 * 10);

    c.cmark_gfm_core_extensions_ensure_registered();
    const extensions = cmark_list_syntax_extensions(c.cmark_get_arena_mem_allocator());
    const parser = c.cmark_parser_new(c.CMARK_OPT_DEFAULT);
    defer c.cmark_parser_free(parser);

    _ = c.cmark_parser_attach_syntax_extension(parser, c.cmark_find_syntax_extension("table"));
    c.cmark_parser_feed(parser, in_string.ptr, in_string.len);
    const ast = c.cmark_parser_finish(parser).?;

    // const ast = c.cmark_parse_document(in_string.ptr, in_string.len, c.CMARK_OPT_DEFAULT).?;

    const iter = Iter.init(ast);
    defer iter.deinit();

    // Copy local images only if the page is the root page of this
    // process, pages loaded via Scripty should skip this analysis.
    if (maybe_dep_writer) |dep_writer| while (iter.next()) |ev| {
        if (ev.dir == .exit) continue;
        const node = ev.node;
        if (node.isImage()) {
            const link = node.link() orelse {
                @panic("TODO: explain that an image without url was found in the markdown file");
            };

            // Skip non-local images
            if (std.mem.startsWith(u8, link, "http")) continue;

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
        }
    };

    // const options = c.CMARK_OPT_DEFAULT | c.CMARK_OPT_UNSAFE;
    var it = Iter.init(ast);

    var html_buf = std.ArrayList(u8).init(arena);
    const w = html_buf.writer();

    while (it.next()) |ev| {
        const node = ev.node;

        if (ev.dir == .exit) {
            switch (node.nodeType()) {
                c.CMARK_NODE_DOCUMENT => {},
                c.CMARK_NODE_BLOCK_QUOTE => try w.print("</blockquote>", .{}),
                c.CMARK_NODE_LIST => try w.print("</{s}>", .{@tagName(node.listType())}),
                c.CMARK_NODE_ITEM => try w.print("</li>", .{}),
                c.CMARK_NODE_CUSTOM_BLOCK => {},
                c.CMARK_NODE_PARAGRAPH => try w.print("</p>", .{}),
                c.CMARK_NODE_HEADING => try w.print("</h{}>", .{node.headingLevel()}),
                c.CMARK_NODE_FOOTNOTE_DEFINITION => @panic("TODO: FOOTNOTE_DEFINITION"),
                c.CMARK_NODE_CUSTOM_INLINE => @panic("custom inline"),
                c.CMARK_NODE_EMPH => try w.print("</i>", .{}),
                c.CMARK_NODE_STRONG => try w.print("</strong>", .{}),
                c.CMARK_NODE_LINK => try w.print("</a>", .{}),
                c.CMARK_NODE_IMAGE => {
                    if (node.title()) |t| {
                        try w.print("\" title=\"{s}\"></figure>", .{t});
                    } else {
                        try w.print("\">", .{});
                    }
                },
                else => {
                    // const html = c.cmark_render_html(node.n, c.CMARK_OPT_DEFAULT, extensions);
                    // try w.writeAll(std.mem.span(html));
                    // std.debug.panic("TODO: implement exit for {x}", .{node.nodeType()});
                },
            }
            continue;
        }
        switch (node.nodeType()) {
            c.CMARK_NODE_DOCUMENT => {},
            c.CMARK_NODE_BLOCK_QUOTE => try w.print("<blockquote>", .{}),
            c.CMARK_NODE_LIST => try w.print("<{s}>", .{@tagName(node.listType())}),
            c.CMARK_NODE_ITEM => try w.print("<li>", .{}),
            c.CMARK_NODE_HTML_BLOCK => try w.print(
                "{s}",
                .{node.literal() orelse ""},
            ),
            c.CMARK_NODE_CUSTOM_BLOCK => {},
            c.CMARK_NODE_PARAGRAPH => try w.print("<p>", .{}),
            c.CMARK_NODE_HEADING => try w.print("<h{}>", .{node.headingLevel()}),
            c.CMARK_NODE_THEMATIC_BREAK => try w.print("<hr>", .{}),
            c.CMARK_NODE_FOOTNOTE_DEFINITION => @panic("TODO: FOOTNOTE_DEFINITION"),
            c.CMARK_NODE_HTML_INLINE => try w.print(
                "{s}",
                .{node.literal() orelse ""},
            ),
            c.CMARK_NODE_CUSTOM_INLINE => @panic("custom inline"),
            c.CMARK_NODE_TEXT => try w.print("{s}", .{node.literal() orelse ""}),
            c.CMARK_NODE_SOFTBREAK => try w.print(" ", .{}),
            c.CMARK_NODE_LINEBREAK => try w.print("<br><br>", .{}),
            c.CMARK_NODE_CODE => try w.print("<code>{s}</code>", .{
                HtmlSafe{ .bytes = node.literal() orelse "" },
            }),
            c.CMARK_NODE_EMPH => try w.print("<i>", .{}),
            c.CMARK_NODE_STRONG => try w.print("<strong>", .{}),
            c.CMARK_NODE_LINK => try w.print("<a href=\"{s}\">", .{
                node.link() orelse "",
            }),
            c.CMARK_NODE_IMAGE => {
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
            c.CMARK_NODE_CODE_BLOCK => {
                if (node.literal()) |code| {
                    const fence_info = node.fenceInfo() orelse "";
                    // if (std.mem.startsWith(u8, fence_info, "zig")) {
                    //     try syntax.highlightZigCode(
                    //         code,
                    //         arena,
                    //         w,
                    //     );
                    // } else {
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
                            arena,
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
                                    .{ md_path, line, col, lang_name },
                                );
                                std.process.exit(1);
                            },
                            else => {
                                std.debug.print(
                                    \\{s}:{}:{}
                                    \\Error while syntax highlighting: {s}
                                    \\
                                ,
                                    .{ md_path, line, col, @errorName(err) },
                                );
                                std.process.exit(1);
                            },
                        };
                        try w.writeAll("</code></pre>\n");
                    }
                    // }
                }
            },

            else => {
                const html = c.cmark_render_html(node.n, c.CMARK_OPT_DEFAULT, extensions);
                try w.writeAll(std.mem.span(html));
                it.exit(node);
                // std.debug.panic("TODO: implement support for {x}", .{node.nodeType()});
            },
        }
    }

    page._meta = .{
        // TODO: unicode this
        .word_count = @intCast(in_string.len / 6),
        .is_section = std.mem.endsWith(u8, md_path, "/index.md"),
        .md_rel_path = md_rel_path,
        .url_path_prefix = url_path_prefix,
        .index_in_section = index_in_section,
        .parent_section_path = parent_section_path,
    };
    page.content = html_buf.items;
    return page;
}

const Iter = struct {
    it: *c.cmark_iter,

    pub fn init(ast: *c.cmark_node) Iter {
        return .{ .it = c.cmark_iter_new(ast).? };
    }

    pub fn deinit(self: Iter) void {
        c.cmark_iter_free(self.it);
    }

    const Event = struct { dir: enum { enter, exit }, node: Node };
    pub fn next(self: Iter) ?Event {
        var exited = false;
        while (true) switch (c.cmark_iter_next(self.it)) {
            c.CMARK_EVENT_DONE => return null,
            c.CMARK_EVENT_EXIT => {
                exited = true;
                break;
            },
            c.CMARK_EVENT_ENTER => break,
            else => unreachable,
        };

        return .{
            .dir = if (exited) .exit else .enter,
            .node = .{ .n = c.cmark_iter_get_node(self.it).? },
        };
    }

    pub fn exit(self: Iter, node: Node) void {
        c.cmark_iter_reset(self.it, node.n, c.CMARK_EVENT_EXIT);
    }
};

const Node = struct {
    n: *c.cmark_node,

    pub fn nodeType(self: Node) u32 {
        return c.cmark_node_get_type(self.n);
    }

    pub fn startLine(self: Node) u32 {
        return @intCast(c.cmark_node_get_start_line(self.n));
    }
    pub fn startColumn(self: Node) u32 {
        return @intCast(c.cmark_node_get_start_column(self.n));
    }

    pub fn isImage(self: Node) bool {
        const t = c.cmark_node_get_type(self.n);
        return t == (0x8000 | 0x4000 | 0x000a);
    }
    pub fn isCodeBlock(self: Node) bool {
        const t = c.cmark_node_get_type(self.n);
        return t == c.CMARK_NODE_CODE_BLOCK;
    }

    pub fn link(self: Node) ?[:0]const u8 {
        const ptr = c.cmark_node_get_url(self.n) orelse return null;
        return std.mem.span(ptr);
    }
    pub fn title(self: Node) ?[:0]const u8 {
        const ptr = c.cmark_node_get_title(self.n) orelse return null;
        return std.mem.span(ptr);
    }
    pub fn literal(self: Node) ?[:0]const u8 {
        const ptr = c.cmark_node_get_literal(self.n) orelse return null;
        return std.mem.span(ptr);
    }
    pub fn fenceInfo(self: Node) ?[:0]const u8 {
        const ptr = c.cmark_node_get_fence_info(self.n) orelse return null;
        return std.mem.span(ptr);
    }
    pub fn headingLevel(self: Node) i32 {
        return c.cmark_node_get_heading_level(self.n);
    }
    pub const ListType = enum { ul, ol };
    pub fn listType(self: Node) ListType {
        return switch (c.cmark_node_get_list_type(self.n)) {
            1 => .ul,
            2 => .ol,
            else => unreachable,
        };
    }
};
