const std = @import("std");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

const log = std.log.scoped(.sitter);

extern fn tree_sitter_html() callconv(.C) *c.TSLanguage;

pub const Tree = struct {
    t: ?*c.TSTree,

    pub fn init(html: []const u8) Tree {
        const parser = c.ts_parser_new();
        if (!c.ts_parser_set_language(parser, tree_sitter_html())) {
            @panic("error while loading treesitter_html");
        }

        const tree = c.ts_parser_parse_string(
            parser,
            null,
            html.ptr,
            @intCast(html.len),
        );

        return .{ .t = tree };
    }

    pub fn root(self: Tree) Node {
        const r = c.ts_tree_root_node(self.t);
        return .{ .n = r };
    }
};

pub const Node = struct {
    n: c.TSNode,

    pub fn debug(self: Node) void {
        const c_str = c.ts_node_string(self.n);
        const str = std.mem.span(c_str);
        log.debug("{s}", .{str});
    }

    pub fn missing(self: Node) bool {
        return c.ts_node_is_missing(self.n);
    }

    pub fn eq(self: Node, other: Node) bool {
        return c.ts_node_eq(self.n, other.n);
    }

    pub fn start(self: Node) u32 {
        return c.ts_node_start_byte(self.n);
    }
    pub fn end(self: Node) u32 {
        return c.ts_node_end_byte(self.n);
    }

    const Offset = struct { start: u32, end: u32 };
    pub fn offset(self: Node) Offset {
        return .{
            .start = self.start(),
            .end = self.end(),
        };
    }

    pub fn string(self: Node, html: []const u8) []const u8 {
        const off = self.offset();
        return html[off.start..off.end];
    }

    const LineOff = struct { line: []const u8, start: u32 };
    /// Finds the line around a Node. Choose simple nodes
    //  if you don't want unwanted newlines in the middle.
    pub fn line(self: Node, html: []const u8) LineOff {
        const off = self.offset();

        var idx = off.start;
        const s = while (idx > 0) : (idx -= 1) {
            if (html[idx] == '\n') break idx + 1;
        } else 0;

        idx = off.end;
        const e = while (idx < html.len) : (idx += 1) {
            if (html[idx] == '\n') break idx;
        } else html.len - 1;

        return .{ .line = html[s..e], .start = s };
    }

    const Point = struct { row: u32, col: u32 };
    const Selection = struct { start: Point, end: Point };
    pub fn selection(self: Node) Selection {
        const s = c.ts_node_start_point(self.n);
        const e = c.ts_node_end_point(self.n);
        return .{
            .start = .{
                .row = s.row + 1,
                .col = s.column + 1,
            },
            .end = .{
                .row = e.row + 1,
                .col = e.column + 1,
            },
        };
    }

    pub fn parent(self: Node) ?Node {
        const p = c.ts_node_parent(self.n);
        if (c.ts_node_is_null(p)) return null;
        return .{ .n = p };
    }

    pub fn childCount(self: Node) u32 {
        return c.ts_node_named_child_count(self.n);
    }

    pub fn childAt(self: Node, idx: u32) ?Node {
        const ch = c.ts_node_named_child(self.n, idx);
        if (c.ts_node_is_null(ch)) return null;
        return .{ .n = ch };
    }

    pub fn lastChild(self: Node) ?Node {
        const count = self.childCount();
        if (count == 0) return null;
        return self.childAt(count - 1);
    }

    pub fn prev(self: Node) ?Node {
        const p = c.ts_node_prev_named_sibling(self.n);
        if (c.ts_node_is_null(p)) return null;
        return .{ .n = p };
    }

    pub fn next(self: Node) ?Node {
        const n = c.ts_node_next_named_sibling(self.n);
        if (c.ts_node_is_null(n)) return null;
        return .{ .n = n };
    }

    pub fn tokenCount(self: Node) u32 {
        return c.ts_node_child_count(self.n);
    }

    pub fn tokenAt(self: Node, idx: u32) ?Node {
        const ch = c.ts_node_child(self.n, idx);
        if (c.ts_node_is_null(ch)) return null;
        return .{ .n = ch };
    }

    pub fn prevToken(self: Node) ?Node {
        const p = c.ts_node_prev_sibling(self.n);
        if (c.ts_node_is_null(p)) return null;
        return .{ .n = p };
    }

    pub fn nextToken(self: Node) ?Node {
        const n = c.ts_node_next_sibling(self.n);
        if (c.ts_node_is_null(n)) return null;
        return .{ .n = n };
    }

    pub fn nodeType(self: Node) []const u8 {
        const t = c.ts_node_type(self.n);
        return std.mem.span(t);
    }

    pub fn toElement(self: Node) ?Element {
        const t = self.nodeType();
        if (!std.mem.eql(u8, t, "element")) return null;
        return .{ .node = self };
    }

    pub fn toTag(self: Node) ?Tag {
        const t = self.nodeType();
        const is_start = std.mem.eql(u8, t, "start_tag");
        const is_self_closing = std.mem.eql(u8, t, "self_closing_tag");
        if (!is_start and !is_self_closing) return null;
        return .{ .node = self, .is_self_closing = is_self_closing };
    }

    pub fn cursor(self: Node) Cursor {
        return .{ .c = c.ts_tree_cursor_new(self.n) };
    }
};

pub const Cursor = struct {
    c: c.TSTreeCursor,

    pub fn node(self: Cursor) ?Node {
        const n = c.ts_tree_cursor_current_node(&self.c);
        if (c.ts_node_is_null(n)) return null;
        return .{ .n = n };
    }

    pub fn fieldName(self: Cursor) []const u8 {
        const str = c.ts_tree_cursor_current_field_name(&self.c);
        return std.mem.span(str);
    }

    pub fn fieldId(self: Cursor) c.TSFieldId {
        return c.ts_tree_cursor_current_field_id(&self.c);
    }

    pub fn parent(self: *Cursor) ?Node {
        if (c.ts_tree_cursor_goto_parent(&self.c))
            return self.node();
        return null;
    }
    pub fn nextSibling(self: *Cursor) ?Node {
        if (c.ts_tree_cursor_goto_next_sibling(&self.c))
            return self.node();
        return null;
    }

    pub fn lastChild(self: *Cursor) ?Node {
        if (c.ts_tree_cursor_goto_last_child(&self.c))
            return self.node();
        return null;
    }

    pub fn child(self: *Cursor) ?Node {
        if (c.ts_tree_cursor_goto_first_child(&self.c))
            return self.node();
        return null;
    }

    pub fn depth(self: *Cursor) u32 {
        return c.ts_tree_cursor_current_depth(&self.c);
    }

    pub fn reset(self: *Cursor, n: Node) void {
        c.ts_tree_cursor_reset(&self.c, n.n);
    }

    pub fn copy(self: *Cursor) Cursor {
        return .{ .c = c.ts_tree_cursor_copy(&self.c) };
    }

    pub fn deinit(self: *Cursor) void {
        c.ts_tree_cursor_delete(&self.c);
    }

    // Allows to use Cursor as a DFS-style iterator
    const IterItem = struct { node: Node, dir: enum { in, next, out } };
    pub fn next(self: *Cursor) ?IterItem {
        if (self.child()) |ch| return .{ .node = ch, .dir = .in };
        if (self.nextSibling()) |s| return .{ .node = s, .dir = .next };

        return while (c.ts_tree_cursor_goto_parent(&self.c)) {
            const uncle = self.nextSibling() orelse continue;
            break .{ .node = uncle, .dir = .out };
        } else null;
    }
};

pub const Element = struct {
    node: Node,

    pub const voidTagMap = std.StaticStringMapWithEql(
        void,
        std.ascii.eqlIgnoreCase,
    ).initComptime(void_tags);

    pub fn startTag(self: Element) Tag {
        return self.node.childAt(0).?.toTag().?;
    }
    pub fn endTag(self: Element) ?Node {
        const last = self.node.childAt(self.node.childCount() - 1).?;
        if (!std.mem.eql(u8, last.nodeType(), "end_tag")) return null;
        return last;
    }

    pub fn isVoid(self: Element, html: []const u8) bool {
        const tag_name = self.startTag().name().string(html);
        return voidTagMap.has(tag_name);
    }
};

pub const Tag = struct {
    node: Node,
    is_self_closing: bool,

    pub fn name(self: Tag) Node {
        return self.node.childAt(0).?;
    }

    pub fn attrs(self: Tag) AttrIterator {
        const maybe_attr = self.node.childAt(1) orelse {
            return .{ .current = null };
        };

        if (!std.mem.eql(u8, "attribute", maybe_attr.nodeType())) {
            return .{ .current = null };
        }

        return .{ .current = maybe_attr };
    }

    pub fn findAttr(self: Tag, html: []const u8, attr_name: []const u8) ?Attr {
        var it = self.attrs();
        return while (it.next()) |attr| {
            if (std.mem.eql(u8, attr.name().string(html), attr_name)) {
                break attr;
            }
        } else null;
    }

    pub const Attr = struct {
        node: Node,

        pub const Value = struct {
            node: Node,

            pub const Managed = struct {
                must_free: bool = false,
                str: []const u8 = &.{},

                pub fn deinit(self: Managed, allocator: std.mem.Allocator) void {
                    if (self.must_free) allocator.free(self.str);
                }
            };

            pub fn unescape(
                self: Value,
                allocator: std.mem.Allocator,
                html: []const u8,
            ) !Managed {
                const str = blk: {
                    if (std.mem.eql(u8, self.node.nodeType(), "quoted_attribute_value")) {
                        const content = self.node.childAt(0) orelse break :blk "";
                        break :blk content.string(html);
                    } else {
                        break :blk self.node.string(html);
                    }
                };

                // TODO: html entities
                _ = allocator;

                return .{ .must_free = false, .str = str };
            }

            pub fn unquote(
                self: Value,
                html: []const u8,
            ) []const u8 {
                const str = if (std.mem.eql(u8, self.node.nodeType(), "quoted_attribute_value"))
                    self.node.childAt(0).?.string(html)
                else
                    self.node.string(html);

                return str;
            }
        };

        pub fn name(self: Attr) Node {
            return self.node.childAt(0).?;
        }

        pub fn value(self: Attr) ?Value {
            const n = self.node.childAt(1) orelse return null;
            return .{ .node = n };
        }
    };

    const AttrIterator = struct {
        current: ?Node,

        pub fn next(self: *AttrIterator) ?Attr {
            const cur = self.current orelse return null;
            self.current = cur.next();

            return .{ .node = cur };
        }
    };
};

const void_tags = .{
    .{"area"},
    .{"base"},
    .{"basefont"},
    .{"bgsound"},
    .{"br"},
    .{"col"},
    .{"command"},
    .{"embed"},
    .{"frame"},
    .{"hr"},
    .{"image"},
    .{"img"},
    .{"input"},
    .{"isindex"},
    .{"keygen"},
    .{"link"},
    .{"menuitem"},
    .{"meta"},
    .{"nextid"},
    .{"param"},
    .{"source"},
    .{"track"},
    .{"wbr"},
};
