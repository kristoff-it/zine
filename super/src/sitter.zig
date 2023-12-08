const std = @import("std");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

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

    const LinePos = struct { line: []const u8, start: u32 };
    /// Finds the line around a Node. Choose simple nodes
    //  if you don't want unwanted newlines in the middle.
    pub fn line(self: Node, html: []const u8) LinePos {
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
        if (!std.mem.eql(u8, "element", self.nodeType())) return null;
        return .{ .node = self };
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
    pub fn child(self: *Cursor) ?Node {
        if (c.ts_tree_cursor_goto_first_child(&self.c))
            return self.node();
        return null;
    }

    pub fn reset(self: *Cursor, n: Node) void {
        c.ts_tree_cursor_reset(&self.c, n.n);
    }

    pub fn copy(self: *Cursor) Cursor {
        return .{ .c = c.ts_tree_cursor_copy(&self.c) };
    }

    pub fn destroy(self: *Cursor) void {
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

    pub fn tag(self: Element, html: []const u8) []const u8 {
        return self.tagNode().string(html);
    }
    pub fn tagNode(self: Element) Node {
        return self.node.childAt(0).?.childAt(0).?;
    }

    pub fn attrs(self: Element) AttrIterator {
        const maybe_attr = self.node.childAt(0).?.childAt(1) orelse {
            return .{ .current = null };
        };

        if (!std.mem.eql(u8, "attribute", maybe_attr.nodeType())) {
            return .{ .current = null };
        }

        return .{ .current = maybe_attr };
    }

    pub fn findAttr(self: Element, html: []const u8, name: []const u8) ?Attr {
        var it = self.attrs();
        return while (it.next()) |attr| {
            if (std.mem.eql(u8, attr.name(html), name)) {
                break attr;
            }
        } else null;
    }

    const Attr = struct {
        node: Node,

        pub fn nameNode(self: Attr) Node {
            return self.node.childAt(0).?;
        }

        pub fn name(self: Attr, html: []const u8) []const u8 {
            return self.nameNode().string(html);
        }

        pub fn value(self: Attr, html: []const u8) ?[]const u8 {
            var next = self.node.childAt(1) orelse return null;
            if (std.mem.eql(u8, next.nodeType(), "quoted_attribute_value")) {
                return next.childAt(0).?.string(html);
            }
            return next.string(html);
        }

        // Unescapes a quoted value
        pub fn parseValue(self: Attr, allocator: std.mem.Allocator) []const u8 {
            _ = self;
            _ = allocator;

            return "todo";
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
