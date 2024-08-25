const Node = @This();

const std = @import("std");
const supermd = @import("root.zig");
const c = supermd.c;
const Range = supermd.Range;
const Directive = supermd.Directive;

n: *c.cmark_node,

// pub fn deinit(n: Node) void {
//     c.cmark_node_free(n.n);
// }

pub const NodeType = enum(c_uint) {
    // Error
    NONE = c.CMARK_NODE_NONE,

    // Blocks
    DOCUMENT = c.CMARK_NODE_DOCUMENT,
    BLOCK_QUOTE = c.CMARK_NODE_BLOCK_QUOTE,
    LIST = c.CMARK_NODE_LIST,
    ITEM = c.CMARK_NODE_ITEM,
    CODE_BLOCK = c.CMARK_NODE_CODE_BLOCK,
    HTML_BLOCK = c.CMARK_NODE_HTML_BLOCK,
    CUSTOM_BLOCK = c.CMARK_NODE_CUSTOM_BLOCK,
    PARAGRAPH = c.CMARK_NODE_PARAGRAPH,
    HEADING = c.CMARK_NODE_HEADING,
    THEMATIC_BREAK = c.CMARK_NODE_THEMATIC_BREAK,
    FOOTNOTE_DEFINITION = c.CMARK_NODE_FOOTNOTE_DEFINITION,

    // Inline
    TEXT = c.CMARK_NODE_TEXT,
    SOFTBREAK = c.CMARK_NODE_SOFTBREAK,
    LINEBREAK = c.CMARK_NODE_LINEBREAK,
    CODE = c.CMARK_NODE_CODE,
    HTML_INLINE = c.CMARK_NODE_HTML_INLINE,
    CUSTOM_INLINE = c.CMARK_NODE_CUSTOM_INLINE,
    EMPH = c.CMARK_NODE_EMPH,
    STRONG = c.CMARK_NODE_STRONG,
    LINK = c.CMARK_NODE_LINK,
    IMAGE = c.CMARK_NODE_IMAGE,
    FOOTNOTE_REFERENCE = c.CMARK_NODE_FOOTNOTE_REFERENCE,

    // extensions load new node types at runtime
    _,
};

pub fn create(t: Node.NodeType) !Node {
    const n = c.cmark_node_new(@intFromEnum(t)) orelse return error.OutOfMemory;
    return .{ .n = n };
}

pub fn range(n: Node) Range {
    return .{
        .start = .{ .row = n.startLine(), .col = n.startColumn() },
        .end = .{ .row = n.endLine(), .col = n.endColumn() },
    };
}

pub fn startLine(self: Node) u32 {
    return @intCast(c.cmark_node_get_start_line(self.n));
}
pub fn startColumn(self: Node) u32 {
    return @intCast(c.cmark_node_get_start_column(self.n));
}
pub fn endLine(self: Node) u32 {
    return @intCast(c.cmark_node_get_end_line(self.n));
}
pub fn endColumn(self: Node) u32 {
    return @intCast(c.cmark_node_get_end_column(self.n));
}

pub fn nodeType(self: Node) NodeType {
    const t = c.cmark_node_get_type(self.n);
    return @enumFromInt(t);
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

pub fn listIsTight(n: Node) bool {
    return 1 == c.cmark_node_get_list_tight(n.n);
}

pub fn parent(n: Node) ?Node {
    const ptr = c.cmark_node_parent(n.n) orelse return null;
    const res: Node = .{ .n = ptr };
    if (res.nodeType() == .DOCUMENT) return null;
    return res;
}
pub fn firstChild(n: Node) ?Node {
    const ptr = c.cmark_node_first_child(n.n) orelse return null;
    return .{ .n = ptr };
}
pub fn nextSibling(n: Node) ?Node {
    const ptr = c.cmark_node_next(n.n) orelse return null;
    return .{ .n = ptr };
}
pub fn prevSibling(n: Node) ?Node {
    const ptr = c.cmark_node_previous(n.n) orelse return null;
    return .{ .n = ptr };
}

// Lightweight iterator
pub fn next(n: Node, stop: Node) ?Node {
    return n.firstChild() orelse n.nextSibling() orelse n.nextUncle(stop);
}

pub fn nextUncle(n: Node, stop: Node) ?Node {
    const p = n.parent() orelse return null;
    if (p.n == stop.n) return null;
    return p.nextSibling() orelse p.nextUncle(stop);
}

pub fn setDirective(
    n: Node,
    gpa: std.mem.Allocator,
    data: *Directive,
    copy: bool,
) !*Directive {
    const ptr = if (copy) blk: {
        const ptr = try gpa.create(Directive);
        ptr.* = data.*;
        break :blk ptr;
    } else data;

    if (c.cmark_node_set_user_data(n.n, ptr) == 0) {
        return error.OutOfMemory;
    }

    return ptr;
}

pub fn getDirective(n: Node) ?*Directive {
    const ptr = c.cmark_node_get_user_data(n.n);
    return @ptrCast(@alignCast(ptr));
}

pub fn replaceWithChild(n: Node) !void {
    const child = c.cmark_node_first_child(n.n);
    const res = c.cmark_node_replace(n.n, child);
    //TODO: check that there are no other children in debug mode
    //TODO: freeing the node requires copying the link src first
    // c.cmark_node_free(n.n);
    if (res == 0) return error.OutOfMemory;
}

pub fn prependChild(p: Node, new_child: Node) !void {
    const code = c.cmark_node_prepend_child(p.n, new_child.n);
    if (code == 0) return error.OutOfMemory;
}

pub fn unlink(n: Node) void {
    c.cmark_node_unlink(n.n);
}
