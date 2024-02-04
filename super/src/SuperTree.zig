const SuperTree = @This();

const std = @import("std");
const sitter = @import("sitter.zig");
const errors = @import("errors.zig");
const ErrWriter = errors.ErrWriter;

const log = std.log.scoped(.supertree);

err: ErrWriter,
template_name: []const u8,
template_path: []const u8,
html: []const u8,
root: *SuperNode,
extends: ?*SuperNode = null,
interface: std.StringArrayHashMapUnmanaged(*const SuperNode) = .{},
blocks: std.StringHashMapUnmanaged(*const SuperNode) = .{},

pub const SuperNode = struct {
    type: Type = .element,
    elem: sitter.Element,
    depth: u32,

    parent: ?*SuperNode = null,
    child: ?*SuperNode = null,
    next: ?*SuperNode = null,
    prev: ?*SuperNode = null,

    // Evaluation
    id_template_parentid: sitter.Tag.Attr = undefined,
    if_else_loop: ScriptedAttr = undefined,
    var_ctx: ScriptedAttr = undefined,
    scripted_attrs: []ScriptedAttr = &.{},

    const ScriptedAttr = struct {
        attr: sitter.Tag.Attr,
        code: sitter.Tag.Attr.Value.Managed,
        eval: ?[]const u8 = null,
    };

    pub fn idAttr(self: SuperNode) sitter.Tag.Attr {
        assert(@src(), self.type.hasId());
        return self.id_template_parentid;
    }
    pub fn idValue(self: SuperNode) sitter.Tag.Attr.Value {
        return self.idAttr().value().?;
    }

    pub fn templateAttr(self: SuperNode) sitter.Tag.Attr {
        assert(@src(), self.type == .extend);
        return self.id_template_parentid;
    }
    pub fn templateValue(self: SuperNode) sitter.Tag.Attr.Value {
        return self.templateAttr().value().?;
    }

    pub fn branchingAttr(self: SuperNode) ScriptedAttr {
        assert(@src(), self.type.branching() != .none);
        return self.if_else_loop;
    }
    pub fn loopAttr(self: SuperNode) ScriptedAttr {
        assert(@src(), self.type.branching() == .loop or self.type.branching() == .inloop);
        return self.if_else_loop;
    }
    pub fn loopValue(self: SuperNode) sitter.Tag.Attr.Value {
        return self.loopAttr().attr.value().?;
    }
    pub fn ifAttr(self: SuperNode) ScriptedAttr {
        assert(@src(), self.type.branching() == .@"if");
        return self.if_else_loop;
    }
    pub fn ifValue(self: SuperNode) sitter.Tag.Attr.Value {
        return self.ifAttr().attr.value().?;
    }
    pub fn elseAttr(self: SuperNode) ScriptedAttr {
        assert(@src(), self.type.branching() == .@"else");
        return self.if_else_loop;
    }
    pub fn varAttr(self: SuperNode) ScriptedAttr {
        assert(@src(), self.type.output() == .@"var");
        return self.var_ctx;
    }
    pub fn varValue(self: SuperNode) sitter.Tag.Attr.Value {
        return self.varAttr().attr.value().?;
    }

    pub fn debugName(self: SuperNode, html: []const u8) []const u8 {
        return self.elem.startTag().name().string(html);
    }

    const Type = enum {
        root,
        extend,
        super,

        block,
        block_var,
        block_ctx,
        block_if,
        block_if_var,
        block_if_ctx,
        block_loop,
        block_loop_var,
        block_loop_ctx,

        super_block,
        super_block_ctx,
        // TODO: enable these types once we implement super attributes
        //super_block_if,
        //super_block_if_ctx,
        //super_block_loop,
        //super_block_loop_ctx,

        element,
        element_var,
        element_ctx,
        element_if,
        element_if_var,
        element_if_ctx,
        element_else,
        element_else_var,
        element_else_ctx,
        element_loop,
        element_loop_var,
        element_loop_ctx,
        element_inloop,
        element_inloop_var,
        element_inloop_ctx,
        element_id,
        element_id_var,
        element_id_ctx,
        element_id_if,
        element_id_if_var,
        element_id_if_ctx,
        element_id_else,
        element_id_else_var,
        element_id_else_ctx,
        element_id_loop,
        element_id_loop_var,
        element_id_loop_ctx,
        element_id_inloop,
        element_id_inloop_var,
        element_id_inloop_ctx,

        pub const Branching = enum { none, loop, inloop, @"if", @"else" };
        pub fn branching(self: Type) Branching {
            return switch (self) {
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                => .loop,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => .inloop,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                => .@"if",
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                => .@"else",
                .root,
                .extend,
                .block,
                .block_var,
                .block_ctx,
                .super_block,
                .super_block_ctx,
                .super,
                .element,
                .element_var,
                .element_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                => .none,
            };
        }

        pub const Output = enum { none, @"var", ctx };
        pub fn output(self: Type) Output {
            return switch (self) {
                .block_var,
                .block_if_var,
                .block_loop_var,
                .element_var,
                .element_if_var,
                .element_else_var,
                .element_loop_var,
                .element_inloop_var,
                .element_id_var,
                .element_id_if_var,
                .element_id_else_var,
                .element_id_loop_var,
                .element_id_inloop_var,
                => .@"var",
                .block_ctx,
                .block_if_ctx,
                .block_loop_ctx,
                .super_block_ctx,
                .element_ctx,
                .element_if_ctx,
                .element_else_ctx,
                .element_loop_ctx,
                .element_inloop_ctx,
                .element_id_ctx,
                .element_id_if_ctx,
                .element_id_else_ctx,
                .element_id_loop_ctx,
                .element_id_inloop_ctx,
                => .ctx,
                .root,
                .extend,
                .super,
                .super_block,
                .block,
                .block_if,
                .block_loop,
                .element,
                .element_if,
                .element_else,
                .element_loop,
                .element_inloop,
                .element_id,
                .element_id_if,
                .element_id_else,
                .element_id_loop,
                .element_id_inloop,
                => .none,
            };
        }

        const Role = enum { root, extend, block, super_block, super, element };
        pub fn role(self: Type) Role {
            return switch (self) {
                .root => .root,
                .extend => .extend,
                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                => .block,
                .super => .super,
                .super_block,
                .super_block_ctx,
                => .super_block,
                .element,
                .element_var,
                .element_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => .element,
            };
        }
        pub fn hasId(self: Type) bool {
            return switch (self) {
                else => false,
                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .super_block,
                .super_block_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_ctx,
                => true,
            };
        }
    };

    pub fn childrenCount(self: SuperNode) usize {
        var count: usize = 0;
        var child = self.child;
        while (child) |ch| : (child = ch.next) count += 1;
        return count;
    }

    pub const SuperBlock = struct { elem: sitter.Element, id_value: sitter.Tag.Attr.Value };
    pub fn superBlock(self: SuperNode) SuperBlock {
        assert(@src(), self.type.role() == .super);
        const id_value = self.id_template_parentid.value().?;

        return .{
            .elem = self.elem.node.parent().?.toElement().?,
            .id_value = id_value,
        };
    }

    pub fn cursor(self: *const SuperNode) SuperCursor {
        return SuperCursor.init(self);
    }

    pub fn debug(self: *const SuperNode, html: []const u8) void {
        std.debug.print("\n\n-- DEBUG --\n", .{});
        self.debugInternal(html, std.io.getStdErr().writer(), 0) catch unreachable;
    }

    // Allows passing in a writer, useful for tests
    pub fn debugWriter(self: *const SuperNode, html: []const u8, w: anytype) void {
        self.debugInternal(html, w, 0) catch unreachable;
    }

    fn debugInternal(
        self: *const SuperNode,
        html: []const u8,
        w: anytype,
        lvl: usize,
    ) !void {
        for (0..lvl) |_| try w.print("    ", .{});
        try w.print("({s} {}", .{ @tagName(self.type), self.depth });

        if (self.type.hasId()) {
            try w.print(" {s}", .{self.idValue().node.string(html)});
        } else if (self.type == .extend) {
            try w.print(" {s}", .{self.templateAttr().node.string(html)});
        } else if (self.type == .super) {
            try w.print(" {s}", .{self.superBlock().id_value.node.string(html)});
        }

        if (self.child) |ch| {
            assert(@src(), ch.parent == self);
            try w.print("\n", .{});
            try ch.debugInternal(html, w, lvl + 1);
            for (0..lvl) |_| try w.print("    ", .{});
        }
        try w.print(")\n", .{});

        if (self.next) |sibling| {
            assert(@src(), sibling.prev == self);
            assert(@src(), sibling.parent == self.parent);
            try sibling.debugInternal(html, w, lvl);
        }
    }
};

pub const SuperCursor = struct {
    depth: usize,
    current: *const SuperNode,
    skip_children_of_current_node: bool = false,

    pub fn init(node: *const SuperNode) SuperCursor {
        return .{ .depth = 0, .current = node };
    }
    pub fn skipChildrenOfCurrentNode(self: *SuperCursor) void {
        self.skip_children_of_current_node = true;
    }
    pub fn next(self: *SuperCursor) ?*const SuperNode {
        if (self.skip_children_of_current_node) {
            self.skip_children_of_current_node = false;
        } else {
            if (self.current.child) |ch| {
                self.depth += 1;
                self.current = ch;
                return ch;
            }
        }

        if (self.depth == 0) return null;

        if (self.current.next) |sb| {
            self.current = sb;
            return sb;
        }

        self.depth -= 1;
        if (self.depth == 0) return null;

        const parent = self.current.parent.?;
        if (parent.next) |un| {
            self.current = un;
            return un;
        }

        return null;
    }

    pub fn reset(self: *SuperCursor, node: *const SuperNode) void {
        self.* = SuperCursor.init(node);
    }
};

pub fn init(
    arena: std.mem.Allocator,
    err_writer: ErrWriter,
    template_name: []const u8,
    template_path: []const u8,
    html: []const u8,
) errors.FatalOOM!SuperTree {
    const html_tree = sitter.Tree.init(html);
    const html_root = html_tree.root();
    var self: SuperTree = .{
        .err = err_writer,
        .template_name = template_name,
        .template_path = template_path,
        .html = html,
        .root = try arena.create(SuperNode),
    };

    self.root.* = .{
        .type = .root,
        .elem = .{ .node = html_root },
        .depth = 0,
    };

    var cursor = html_root.cursor();
    defer cursor.deinit();
    var node = self.root;
    var low_mark: u32 = 1;
    while (cursor.next()) |item| {
        if (is(item.node.nodeType(), "erroneous_end_tag") or
            is(item.node.nodeType(), "MISSING _implicit_end_tag"))
        {
            return self.reportError(
                item.node,
                "html_syntax_error",
                "HTML SYNTAX ERROR",
                \\An HTML syntax error was found in a template.
                ,
            );
        }

        const depth = cursor.depth();
        const elem = item.node.toElement() orelse continue;

        // Ensure that node always points at a node not more deeply nested
        // than our current html_node.
        if (low_mark > depth) low_mark = depth;
        while (node.parent) |p| {
            if (low_mark > p.depth) break;
            node = p;
        }

        const new_node = try self.buildNode(arena, elem, depth) orelse continue;

        new_node.elem.node.debug();

        // Iterface and block mode
        switch (new_node.type.role()) {
            .root, .super_block => unreachable,
            .super, .element => {},
            .extend => {
                // sets block mode
                assert(@src(), self.extends == null);
                self.extends = new_node;
            },
            .block => {
                const id_value = new_node.idValue();
                const gop = try self.blocks.getOrPut(arena, id_value.unquote(html));
                if (gop.found_existing) {
                    self.reportError(
                        id_value.node,
                        "duplicate_block",
                        "DUPLICATE BLOCK DEFINITION",
                        \\When a template extends another, top level elements
                        \\are called "blocks" and define the value of a corresponding
                        \\<super/> tag in the extended template by having the 
                        \\same id of the <super/> tag's parent container.
                        ,
                    ) catch {};
                    const other = gop.value_ptr.*.idValue().node;
                    try self.diagnostic("note: previous definition:", other);
                    return error.Fatal;
                }

                gop.value_ptr.* = new_node;
            },
        }

        //ast

        // var html_node = new_node.elem.node;
        // var html_node_depth = new_node.depth;
        // var last_same_depth = true;
        // while (!html_node.eq(node.elem.node)) {
        //     last_same_depth = html_node_depth == node.depth;

        //     if (html_node.prev()) |p| {
        //         html_node = p;
        //         continue;
        //     }

        //     const html_parent = html_node.parent() orelse unreachable;
        //     html_node = html_parent;
        //     html_node_depth -= 1;
        // }

        if (low_mark <= node.depth) {
            assert(@src(), node.next == null);
            node.next = new_node;
            new_node.prev = node;
            new_node.parent = node.parent;
        } else {
            if (node.child) |c| {
                var sibling = c;
                while (sibling.next) |n| sibling = n;
                sibling.next = new_node;
                new_node.prev = sibling;
                new_node.parent = node;
            } else {
                node.child = new_node;
                new_node.parent = node;
            }
        }

        try self.validateNodeInTree(new_node);

        node = new_node;
        low_mark = new_node.depth + 1;
    }

    return self;
}

fn buildNode(
    self: *SuperTree,
    arena: std.mem.Allocator,
    elem: sitter.Element,
    depth: u32,
    // id_map: std.StringHashMapUnmanaged(sitter.Node),
) !?*SuperNode {
    const block_mode = self.extends != null;
    var tmp_result: SuperNode = .{
        .elem = elem,
        .depth = depth,
    };

    assert(@src(), depth > 0);
    const block_context = block_mode and depth == 1;
    if (block_context) tmp_result.type = .block;

    const start_tag = elem.startTag();
    const tag_name = start_tag.name();
    // is it a special tag
    {
        const tag_name_string = tag_name.string(self.html);
        if (is(tag_name_string, "extend")) {
            tmp_result.type = switch (tmp_result.type) {
                else => unreachable,
                .element => .extend,
                .block => blk: {
                    // this is an error, but we're going to let it through
                    // in order to report it as a duplicate extend tag error.
                    break :blk .extend;
                },
            };

            // validation
            {
                const parent_isnt_root = depth != 1;
                var prev = elem.node.prev();
                const any_elem_before = while (prev) |p| : (prev = p.prev()) {
                    if (!is(p.nodeType(), "comment")) break true;
                } else false;

                if (parent_isnt_root or any_elem_before) {
                    return self.reportError(
                        tag_name,
                        "unexpected_extend",
                        "UNEXPECTED EXTEND TAG",
                        \\The <extend/> tag can only be present at the beginning of a 
                        \\template and it can only be preceeded by HTML comments and
                        \\whitespace. 
                        ,
                    );
                }

                if (!start_tag.is_self_closing) {
                    return self.reportError(
                        tag_name,
                        "open_tag",
                        "OPEN EXTEND TAG",
                        \\The extend tag must be closed immediately (i.e.: <extend template="foo.html"/>).
                        \\It must be done otherwise parsers will assume that all 
                        \\content after is *inside* of it.
                        \\
                        \\Cursed read: https://www.w3.org/TR/2014/REC-html5-20141028/syntax.html#optional-tags
                        ,
                    );
                }

                var extend_attrs = start_tag.attrs();
                const template_attr = extend_attrs.next() orelse {
                    @panic("TODO: explain that super must have a template attr");
                };

                tmp_result.id_template_parentid = template_attr;

                if (extend_attrs.next()) |a| {
                    _ = a;
                    @panic("TODO: explain that extend can't have attrs other than `template`");
                }

                const new_node = try arena.create(SuperNode);
                new_node.* = tmp_result;
                return new_node;
            }
        } else if (is(tag_name_string, "super")) {
            tmp_result.type = switch (tmp_result.type) {
                else => unreachable,
                .element => .super,
                .block => {
                    return self.reportError(
                        tag_name,
                        "bad_super_tag",
                        "TOP LEVEL <SUPER/>",
                        \\This template extends another template and as such it
                        \\must only have block definitions at the top level.
                        \\
                        \\You *can* use <super/>, but it must be nested in a block. 
                        \\Using <super/> will make this template extendable in turn.
                        ,
                    );
                },
            };

            if (!start_tag.is_self_closing) {
                return self.reportError(
                    tag_name,
                    "bad_super_tag",
                    "BAD SUPER TAG",
                    \\Super tags must be closed immediately (i.e.: <super/>).
                    \\It must be done otherwise parsers will assume that all 
                    \\subsequent content is *inside* of it.
                    \\
                    \\Cursed read: https://www.w3.org/TR/2014/REC-html5-20141028/syntax.html#optional-tags
                    ,
                );
            }

            var super_attrs = start_tag.attrs();
            if (super_attrs.next()) |a| {
                _ = a;
                @panic("TODO: explain that super can't have attrs");
            }

            //The immediate parent must have an id
            const parent = tmp_result.elem.node.parent().?.toElement() orelse {
                return self.reportError(
                    tag_name,
                    "bad_super_tag",
                    "<SUPER/> NOT IN AN ELEMENT",
                    \\The <super/> tag can only exist nested inside another
                    \\element, as that's how the templating system defines 
                    \\extension points.
                    ,
                );
            };

            const parent_start_tag = parent.startTag();
            var parent_attrs = parent_start_tag.attrs();
            while (parent_attrs.next()) |attr| {
                if (is(attr.name().string(self.html), "id")) {
                    // We can assert that the value is present because
                    // the parent element has already been validated.
                    const value = attr.value().?;
                    const gop = try self.interface.getOrPut(
                        arena,
                        value.unquote(self.html),
                    );
                    if (gop.found_existing) {
                        @panic("TODO: explain that the interface of this template has a collision");
                    }

                    tmp_result.id_template_parentid = attr;
                    const new_node = try arena.create(SuperNode);
                    new_node.* = tmp_result;
                    gop.value_ptr.* = new_node;
                    return new_node;
                }
            } else {
                self.reportError(
                    tag_name,
                    "super_block_missing_id",
                    "<SUPER/> BLOCK HAS NO ID",
                    \\The <super/> tag must exist directly under an element
                    \\that specifies an `id` attribute.
                    ,
                ) catch {};
                try self.diagnostic(
                    "note: the parent element:",
                    parent_start_tag.name(),
                );
                return error.Fatal;
            }
        }
    }

    // programming errors
    switch (tmp_result.type.role()) {
        else => {},
        .root, .extend, .super_block, .super => unreachable,
    }

    if (!start_tag.is_self_closing and !elem.isVoid(self.html) and elem.endTag() == null) {
        return self.reportError(
            tag_name,
            "closing_tag_missing",
            "ELEMENT MISSING CLOSING TAG",
            \\While it is technically correct in HTML to have a non-void element 
            \\that doesn't have a closing tag, it's much more probable for
            \\it to be a programming error than to be intended. For this
            \\reason, this is a syntax error.
            ,
        );
    }

    var attrs_seen = std.StringHashMap(sitter.Node).init(arena);
    defer attrs_seen.deinit();

    var scripted_attrs = std.ArrayList(SuperNode.ScriptedAttr).init(arena);
    errdefer scripted_attrs.deinit();

    var last_attr_end = tag_name.end();
    var attrs = start_tag.attrs();
    while (attrs.next()) |attr| : (last_attr_end = attr.node.end()) {
        const name = attr.name();
        const name_string = name.string(self.html);
        // validation
        {
            const gop = try attrs_seen.getOrPut(name_string);
            if (gop.found_existing) {
                self.reportError(
                    name,
                    "duplicate_attr",
                    "DUPLICATE ATTRIBUTE",
                    \\HTML elements cannot contain duplicate attributes.
                    ,
                ) catch {};
                try self.diagnostic(
                    "node: previous instance was here:",
                    gop.value_ptr.*,
                );
                return error.Fatal;
            }
            gop.value_ptr.* = name;
        }

        if (is(name_string, "id")) {
            tmp_result.type = switch (tmp_result.type) {
                .element => .element_id,
                .element_var => .element_id_var,
                .element_ctx => .element_id_ctx,
                .element_if => .element_id_if,
                .element_if_var => .element_id_if_var,
                .element_if_ctx => .element_id_if_ctx,
                .element_else => .element_id_else,
                .element_else_var => .element_id_else_var,
                .element_else_ctx => .element_id_else_ctx,
                .element_loop => .element_id_loop,
                .element_loop_var => .element_id_loop_var,
                .element_loop_ctx => .element_id_loop_ctx,
                .element_inloop => .element_id_inloop,
                .element_inloop_var => .element_id_inloop_var,
                .element_inloop_ctx => .element_id_inloop_ctx,

                // no state transition
                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                => |s| s,

                .root,
                .extend,
                .super,
                // never discovered yet
                .super_block,
                .super_block_ctx,
                // duplicate detection
                .element_id,
                .element_id_var,
                .element_id_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => unreachable,
            };

            const value = attr.value() orelse {
                @panic("TODO: explain that id must have a value");
            };

            const maybe_code = try value.unescape(arena, self.html);
            defer maybe_code.deinit(arena);

            if (std.mem.indexOfScalar(u8, maybe_code.str, '$') != null) {
                switch (tmp_result.type.role()) {
                    .root, .extend, .super_block, .super => unreachable,
                    .block => @panic("TODO: explain blocks can't have scripted id attrs"),
                    .element => {},
                }
            } else {
                // we can only statically analyze non-scripted ids

                // TODO: implement this in a way that can account for branching

                // const id_str = value.unquote(self.html);
                // const gop = id_map.getOrPut(arena, id_str) catch oom();
                // if (gop.found_existing) {
                //     return errors.report(
                //         template_name,
                //         template_path,
                //         attr.node,
                //         self.html,
                //         "DUPLICATE ID",
                //         \\TODO: explain
                //         ,
                //     );
                // }
            }

            tmp_result.id_template_parentid = attr;

            continue;
        }
        if (is(name_string, "debug")) {
            log.debug("\nfound debug attribute", .{});
            log.debug("\n{s}\n", .{
                name.string(self.html),
            });
            name.debug();
            log.debug("\n", .{});

            return self.fatal("debug attribute found, aborting", .{});
        }

        // var
        if (is(name_string, "var")) {
            if (attr.node.next() != null) {
                return self.reportError(
                    name,
                    "var_must_be_last",
                    "MISPLACED VAR ATTRIBUTE",
                    \\An element that prints the content of a variable must place
                    \\the `var` attribute at the very end of the opening tag.
                    ,
                );
            }

            tmp_result.type = switch (tmp_result.type) {
                .block => .block_var,
                .block_if => .block_if_var,
                .block_loop => .block_loop_var,
                .element => .element_var,
                .element_if => .element_if_var,
                .element_else => .element_else_var,
                .element_loop => .element_loop_var,
                .element_inloop => .element_inloop_var,
                .element_id => .element_id_var,
                .element_id_if => .element_id_if_var,
                .element_id_else => .element_id_else_var,
                .element_id_loop => .element_id_loop_var,
                .element_id_inloop => .element_id_inloop_var,

                .block_ctx,
                .block_if_ctx,
                .block_loop_var,
                .block_loop_ctx,
                .element_ctx,
                .element_if_ctx,
                .element_else_ctx,
                .element_loop_ctx,
                .element_inloop_ctx,
                .element_id_ctx,
                .element_id_if_ctx,
                .element_id_else_ctx,
                .element_id_loop_ctx,
                .element_id_inloop_ctx,
                => {
                    @panic("TODO: explain that a tag combination is wrong");
                },

                .root,
                .extend,
                .super,
                // never discorvered yet
                .super_block,
                .super_block_ctx,
                // duplicate attr detection
                .block_var,
                .block_if_var,
                .element_var,
                .element_if_var,
                .element_else_var,
                .element_loop_var,
                .element_inloop_var,
                .element_id_var,
                .element_id_if_var,
                .element_id_else_var,
                .element_id_loop_var,
                .element_id_inloop_var,
                => unreachable,
            };

            const value = attr.value() orelse {
                return self.reportError(
                    name,
                    "var_no_value",
                    "VAR MISSING VALUE",
                    \\A `var` attribute requires a value that scripts what 
                    \\to put in the relative element's body.
                    ,
                );
            };

            const code = try value.unescape(arena, self.html);
            // TODO: typecheck the expression
            if (std.mem.indexOfScalar(u8, code.str, '$') == null) {
                return self.reportError(
                    name,
                    "unscripted_var",
                    "UNSCRIPTED VAR",
                    \\A `var` attribute requires a value that scripts what 
                    \\to put in the relative element's body.
                    ,
                );
            }
            tmp_result.var_ctx = .{ .attr = attr, .code = code };

            continue;
        }

        // template outside of <extend/>
        if (is(name_string, "template")) {
            @panic("TODO: explain that `template` can only go in extend tags");
        }

        // if
        if (is(name_string, "if")) {
            tmp_result.type = switch (tmp_result.type) {
                .block => .block_if,
                .block_var => .block_if_var,
                .block_ctx => .block_if_ctx,
                .element => .element_if,
                .element_var => .element_if_var,
                .element_ctx => .element_if_ctx,
                .element_id => .element_id_if,
                .element_id_var => .element_id_if_var,
                .element_id_ctx => .element_id_if_ctx,

                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => {
                    self.reportError(
                        name,
                        "bad_attr",
                        "ALREADY BRANCHING",
                        \\Elements can't have multiple branching attributes defined 
                        \\at the same time.
                        ,
                    ) catch {};
                    try self.diagnostic(
                        "note: this is the previous branching attribute:",
                        tmp_result.branchingAttr().attr.name(),
                    );
                    return error.Fatal;
                },

                .root,
                .extend,
                .super,
                // never discovered yet
                .super_block,
                .super_block_ctx,
                // duplicate attribute
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                => unreachable,
            };

            if (last_attr_end != tag_name.end()) {
                return self.reportError(
                    name,
                    "bad_attr",
                    "IF ATTRIBUTE MUST COME FIRST",
                    \\When giving an 'if' attribute to an element, you must always place it 
                    \\first in the attribute list.
                    ,
                );
            }

            const value = attr.value() orelse {
                return self.reportError(
                    name,
                    "bad_attr",
                    "IF ATTRIBUTE WIHTOUT VALUE",
                    \\When giving an `if` attribute to an element, you must always
                    \\also provide a condition in the form of a value.
                    ,
                );
            };

            const code = try value.unescape(arena, self.html);
            // TODO: typecheck the expression
            tmp_result.if_else_loop = .{ .attr = attr, .code = code };

            continue;
        }

        // else
        if (is(name_string, "else")) {
            tmp_result.type = switch (tmp_result.type) {
                .element => .element_else,
                .element_var => .element_else_var,
                .element_ctx => .element_else_ctx,
                .element_id => .element_id_else,
                .element_id_var => .element_id_else_var,
                .element_id_ctx => .element_id_else_ctx,

                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => {
                    @panic("TODO: explain why these blocks can't have an else attr");
                },

                .root,
                .extend,
                .super,
                // never discovered yet
                .super_block,
                .super_block_ctx,
                => unreachable,
            };

            if (last_attr_end != tag_name.end()) {
                @panic("TODO: explain that else must be the first attr");
            }
            if (attr.value()) |v| {
                return self.reportError(
                    v.node,
                    "bad_attr",
                    "ELSE ATTRIBUTE WITH VALUE",
                    "`else` attributes cannot have a value.",
                );
            }

            tmp_result.if_else_loop = .{ .attr = attr, .code = .{} };

            continue;
        }

        // loop
        if (is(name_string, "loop")) {
            if (last_attr_end != tag_name.end()) {
                @panic("TODO: explain that loop must be the first attr");
            }

            tmp_result.type = switch (tmp_result.type) {
                .block => .block_loop,
                .block_var => .block_loop_var,
                .block_ctx => .block_loop_ctx,
                .element => .element_loop,
                .element_var => .element_loop_var,
                .element_ctx => .element_loop_ctx,
                .element_id => .element_id_loop,
                .element_id_var => .element_id_loop_var,
                .element_id_ctx => .element_id_loop_ctx,

                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => {
                    // TODO: some of these cases should be unreachable
                    @panic("TODO: explain why these blocks can't have an loop attr");
                },

                .root,
                .extend,
                .super,
                // never discovered yet
                .super_block,
                .super_block_ctx,
                => unreachable,
            };

            const value = attr.value() orelse {
                @panic("TODO: explain that loop must have a value");
            };

            const code = try value.unescape(arena, self.html);
            // TODO: typecheck the expression
            tmp_result.if_else_loop = .{ .attr = attr, .code = code };

            continue;
        }

        // inline-loop
        if (is(name_string, "inline-loop")) {
            if (last_attr_end != tag_name.end()) {
                @panic("TODO: explain that loop must be the first attr");
            }

            tmp_result.type = switch (tmp_result.type) {
                .element => .element_inloop,
                .element_var => .element_inloop_var,
                .element_ctx => .element_inloop_ctx,
                .element_id => .element_id_inloop,
                .element_id_var => .element_id_inloop_var,
                .element_id_ctx => .element_id_inloop_ctx,

                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => {
                    @panic("TODO: explain why these blocks can't have an inline-loop attr");
                },

                .root,
                .extend,
                .super,
                .block,
                .block_var,
                .block_ctx,
                // never discovered yet
                .super_block,
                .super_block_ctx,
                => unreachable,
            };

            const value = attr.value() orelse {
                @panic("TODO: explain that loop must have a value");
            };

            const code = try value.unescape(arena, self.html);
            // TODO: typecheck the expression
            tmp_result.if_else_loop = .{ .attr = attr, .code = code };

            continue;
        }

        // normal attribute
        if (attr.value()) |value| {
            const code = try value.unescape(arena, self.html);
            if (std.mem.startsWith(u8, code.str, "$")) {
                try scripted_attrs.append(.{
                    .attr = attr,
                    .code = code,
                });
            }
        }
    }

    switch (tmp_result.type) {
        .element, .element_id => if (scripted_attrs.items.len == 0) return null,
        else => {},
    }

    // TODO: see if the error reporting order makes sense
    if (tmp_result.type.role() == .block and !attrs_seen.contains("id")) {
        const name = tmp_result.elem.startTag().name();
        return self.reportError(
            name,
            "block_missing_id",
            "BLOCK MISSING ID ATTRIBUTE",
            \\When a template extends another template, all top level 
            \\elements must specify an `id` that matches with a corresponding 
            \\super block (i.e. the element parent of a <super/> tag in 
            \\the extended template). 
            ,
        );
    }

    const new_node = try arena.create(SuperNode);
    new_node.* = tmp_result;
    new_node.scripted_attrs = try scripted_attrs.toOwnedSlice();
    return new_node;
}

fn validateNodeInTree(self: SuperTree, node: *const SuperNode) !void {
    // NOTE: This function should only validate rules that require
    //       having inserted the node in the tree. anything that
    //       can be tested sooner should go in self.buildNode().
    //
    // NOTE: We can only validate constraints *upwards* with regards
    //       to the SuperTree.

    switch (node.type.role()) {
        .root => unreachable,
        .element => {},

        .extend => {
            // if present, <extend/> must be the first tag in the document
            // (validated on creation)
            // TODO: check for empty body
        },
        .block => {
            // blocks must have an id
            // (validated on creation)

            // blocks must be at depth = 1
            // (validated on creation)
        },

        .super_block => {
            // must have an id
            // (validated on creation)

            // must have a <super/> inside
            // (validated when validating the <super/>)
        },
        .super => {
            // <super/> must have super_block right above
            // (validated on creation)

            // // <super/> can't be inside any subtree with branching in it
            // var out = node.parent;
            // while (out) |o| : (out = o.parent) if (o.type.branching() != .none) {
            //     self.reportError(node.elem.node, "<SUPER/> UNDER BRANCHING",
            //         \\The <super/> tag is used to define a static template
            //         \\extension hierarchy, and as such should not be placed
            //         \\inside of elements that feature branching logic.
            //     ) catch {};
            //     std.debug.print("note: branching happening here:\n", .{});
            //     self.diagnostic(o.branchingAttr().attr.name());
            //     return error.Reported;
            // };

            // each super_block can only have one <super/> in it.

            // TODO: this only catches the simplest case,
            //       it needs to also enter prev nodes.

            var html_up = node.elem.node.prev();
            while (html_up) |u| : (html_up = u.prev()) {
                const elem = u.toElement() orelse continue;
                const start_tag = elem.startTag();
                if (is(start_tag.name().string(self.html), "super")) {
                    self.reportError(
                        node.elem.node,
                        "too_many_supers",
                        "MULTIPLE SUPER TAGS UNDER SAME ID",
                        \\TODO: write explanation
                        ,
                    ) catch {};
                    try self.diagnostic(
                        "note: the other tag:",
                        start_tag.name(),
                    );
                    try self.diagnostic(
                        "note: both are relative to:",
                        node.superBlock().id_value.node,
                    );
                    return error.Fatal;

                    // self.reportError(elem_name, "UNEXPECTED SUPER TAG",
                    //     \\All <super/> tags must have a parent element with an id,
                    //     \\which is what defines a block, and each block can only have
                    //     \\one <super/> tag.
                    //     \\
                    //     \\Add an `id` attribute to a new element to split them into
                    //     \\two blocks, or remove one.
                    // ) catch {};
                    // std.debug.print("note: this is where the other tag is:", .{});
                    // self.templateDiagnostics(gop.value_ptr.*);
                    // std.debug.print("note: both refer to this ancestor:", .{});
                    // self.templateDiagnostics(s.tag_name);
                    // return error.Reported;
                }
            }
        },
    }

    // nodes under a loop can't have ids
    if (node.type.hasId()) {
        var parent = node.parent;
        while (parent) |p| : (parent = p.parent) switch (p.type.branching()) {
            else => continue,
            .loop, .inloop => {
                self.reportError(
                    node.idAttr().name(),
                    "id_under_loop",
                    "ID UNDER LOOP",
                    \\In a valid HTML document all `id` attributes must 
                    \\have unique values.
                    \\
                    \\Giving an `id` attribute to elements under a loop
                    \\makes that impossible. 
                    ,
                ) catch {};
                try self.diagnostic("note: the loop:\n", p.loopAttr().attr.name());
                return error.Fatal;
            },
        };
    }

    // switch (node.type.branching()) {
    //     else => {},
    //     // `inline-else` must be right after `if`
    //     .@"inline-else" => {
    //         // compute distance
    //         var distance: usize = 1;
    //         var html_node = if (node.prev) |p| blk: {
    //             break :blk if (p.type.branching() == .@"if") p.elem.node.next() else null;
    //         } else null;

    //         while (html_node) |n| : (html_node = n.next()) {
    //             if (n.eq(node.elem.node)) break;
    //             distance += 1;
    //         } else {
    //             // either the previous node was not an if, or, if it was,
    //             // it did not connect to us.
    //             const name = node.if_else_loop.attr.name();
    //             return self.reportError(name, "LONELY ELSE",
    //                 \\Elements with an `else` attribute must come right after
    //                 \\an element with an `if` attribute. Make sure to nest them
    //                 \\correctly.
    //             );
    //         }
    //         // prev was set and it was an if node (html_node is set)
    //         if (distance > 1) {
    //             const name = node.if_else_loop.attr.name();
    //             self.reportError(name, "STRANDED ELSE",
    //                 \\Elements with an `else` attribute must come right after
    //                 \\an element with an `if` attribute. Make sure to nest them
    //                 \\correctly.
    //             ) catch {};
    //             std.debug.print("\nnote: potentially corresponding if: ", .{});
    //             self.diagnostic(name);

    //             if (distance == 2) {
    //                 std.debug.print("note: inbetween: ", .{});
    //             } else {
    //                 std.debug.print("note: inbetween (plus {} more): ", .{distance - 1});
    //             }
    //             const inbetween = html_node.?.toElement();
    //             const bad = if (inbetween) |e| e.startTag().name() else html_node.?;
    //             self.diagnostic(bad);
    //             return error.Reported;
    //         }
    //     },
    // }
}

fn fatal(self: SuperTree, comptime msg: []const u8, args: anytype) errors.Fatal {
    return errors.fatal(self.err, msg, args);
}

fn reportError(
    self: SuperTree,
    node: sitter.Node,
    comptime error_code: []const u8,
    comptime title: []const u8,
    comptime msg: []const u8,
) errors.Fatal {
    return errors.report(
        self.err,
        self.template_name,
        self.template_path,
        node,
        self.html,
        error_code,
        title,
        msg,
    );
}

fn diagnostic(
    self: SuperTree,
    comptime note_line: []const u8,
    node: sitter.Node,
) !void {
    return errors.diagnostic(
        self.err,
        self.template_name,
        self.template_path,
        note_line,
        node,
        self.html,
    );
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}

test "basics" {
    const case =
        \\<div>Hello World!</div>
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );

    const root = tree.root;
    try std.testing.expectEqual(SuperNode.Type.root, root.type);

    errdefer root.debug(case);

    const null_ptr = @as(?*SuperNode, null);
    try std.testing.expectEqual(null_ptr, root.parent);
    try std.testing.expectEqual(null_ptr, root.next);
    try std.testing.expectEqual(null_ptr, root.prev);
    try std.testing.expectEqual(null_ptr, root.child);
}

test "var - errors" {
    const cases =
        \\<div var></div>
        \\<div var="$page.content" else></div>
        \\<div var="$page.content" if></div>
        \\<div var="$page.content" loop></div>
        \\<div var="$page.content" var></div>
        \\<div var="not scripted"></div>
    ;

    var it = std.mem.tokenizeScalar(u8, cases, '\n');
    while (it.next()) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const tree = SuperTree.init(
            arena.allocator(),
            "foo.html",
            "path/to/foo.html",
            case,
        );

        try std.testing.expectError(error.Fatal, tree);
    }
}

test "siblings" {
    const case =
        \\<div>
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <p var="$bar"></p>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );
    var out = std.ArrayList(u8).init(arena.allocator());

    const root = tree.root;
    root.debugWriter(case, out.writer());

    const ex =
        \\(root
        \\    (element_if)
        \\    (element_var)
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "nesting" {
    const case =
        \\<div loop="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <p var="$bar"></p>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );

    var out = std.ArrayList(u8).init(arena.allocator());

    const root = tree.root;
    root.debugWriter(case, out.writer());

    const ex =
        \\(root
        \\    (element_loop
        \\        (element_if)
        \\        (element_var)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "deeper nesting" {
    const case =
        \\<div loop="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <div><p var="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );

    var out = std.ArrayList(u8).init(arena.allocator());

    const root = tree.root;
    root.debugWriter(case, out.writer());

    const ex =
        \\(root
        \\    (element_loop
        \\        (element_if)
        \\        (element_var)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "complex example" {
    const case =
        \\<div if="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <span else>
        \\    <p loop="foo" id="p-loop">
        \\      <span var="$bar"></span>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" var="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );

    var out = std.ArrayList(u8).init(arena.allocator());

    const root = tree.root;
    root.debugWriter(case, out.writer());

    const cex: usize = 3;
    try std.testing.expectEqual(cex, root.child.?.childrenCount());

    const ex =
        \\(root
        \\    (element_if
        \\        (element_if)
        \\        (element_else
        \\            (element_id_loop "p-loop"
        \\                (element_var)
        \\            )
        \\        )
        \\        (element_id_var "last")
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "if-else-loop errors" {
    const cases =
        \\<div if></div>
        \\<div else="$foo"></div>
        \\<div else="bar"></div>
        \\<div else if></div>
        \\<div else if="$foo"></div>
        \\<div else if="bar"></div>
    ;

    var it = std.mem.tokenizeScalar(u8, cases, '\n');
    while (it.next()) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const tree = SuperTree.init(
            arena.allocator(),
            "foo.html",
            "path/to/foo.html",
            case,
        );

        try std.testing.expectError(error.Fatal, tree);
    }
}

test "super" {
    const case =
        \\<div if="$page.authors">
        \\  Hello World!
        \\  <span>
        \\    <p loop="$page.authors" id="p-loop">
        \\      <span id="oops" var="$loop.it.name"></span>
        \\      <super/>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" var="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // foo
    const tree = try SuperTree.init(
        arena.allocator(),
        "foo.html",
        "path/to/foo.html",
        case,
    );

    var out = std.ArrayList(u8).init(arena.allocator());

    const root = tree.root;
    root.debugWriter(case, out.writer());

    const ex =
        \\(root
        \\    (element_if
        \\        (element_id_loop "p-loop"
        \\            (element_id_var "oops")
        \\            (super "p-loop")
        \\        )
        \\        (element_id_var "last")
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);

    const cex: usize = 2;
    try std.testing.expectEqual(cex, root.child.?.childrenCount());
}
// TODO: get rid of this once stack traces on arm64 work again
fn assert(loc: std.builtin.SourceLocation, condition: bool) void {
    if (!condition) {
        std.debug.print("assertion error in {s} at {s}:{}:{}\n", .{
            loc.fn_name,
            loc.file,
            loc.line,
            loc.column,
        });
        std.process.exit(1);
    }
}
