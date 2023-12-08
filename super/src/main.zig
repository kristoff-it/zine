const std = @import("std");
const sitter = @import("sitter.zig");

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = try std.process.argsAlloc(arena);
    const out_path = args[1];
    const rendered_md_path = args[2];
    const layout_path = args[3];
    const templates_dir_path = args[4];

    const rendered_md_string = try readFile(rendered_md_path, arena);
    const layout_html = try readFile(layout_path, arena);

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        std.debug.print("Error while creating file: {s}\n", .{out_path});
        return err;
    };
    defer out_file.close();

    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const w = buf_writer.writer();

    var layouts = std.ArrayList(Layout).init(arena);
    try layouts.append(Layout.init(layout_html, arena, rendered_md_string));

    // current layout index
    var idx: usize = 0;

    // if that's not enough contact me for an enterprise license of Zine
    var quota: usize = 100_000_000;
    while (quota > 0) : (quota -= 1) {
        const l = &layouts.items[idx];

        switch (try l.analyze(w)) {
            .full_end => break,
            .zine => |t| {
                const path = try std.fs.path.join(arena, &.{ templates_dir_path, t });
                const template_html = try readFile(path, arena);
                try layouts.append(Layout.init(template_html, arena, rendered_md_string));
                idx += 1;
            },
            .super => |id| {
                if (idx == 0) {
                    @panic("programming error: layout acting like it has <super> in it");
                }
                idx -= 1;

                const super = &layouts.items[idx];
                try super.moveCursorToBlock(id, w);
            },
            .block_end => {
                idx += 1;
                if (idx == layouts.items.len) {
                    @panic("programming error: bottom template acting like a block template");
                }
            },
        }
    } else {
        @panic("TODO: explain that there probably was an infinite loop");
    }

    for (layouts.items) |l| try l.finalCheck();

    try buf_writer.flush();
}

fn readFile(path: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error while opening file: {s}\n", .{path});
        return err;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    return r.readAllAlloc(arena, 4096);
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.mem.eql(u8, str1, str2);
}

const Layout = struct {
    html: []const u8,
    print_cursor: usize,
    tree: sitter.Tree,

    // Template-wide analysis
    cursor: sitter.Cursor,
    cursor_busy: bool = true, // for programming errors

    // Analysis of `<zine>`
    extends: ?[]const u8 = null,

    // Analysis of blocks
    blocks: std.StringHashMap(Block),
    block_mode: bool = false, // for programming errors
    current_block_id: ?[]const u8 = null, // for programming errors

    // Scripting
    md: []const u8,

    const Block = struct {
        elem: sitter.Element,
        state: enum { new, analysis, done } = .new,
    };

    pub fn init(html: []const u8, arena: std.mem.Allocator, md: []const u8) Layout {
        const tree = sitter.Tree.init(html);
        return .{
            .html = html,
            .md = md,
            .print_cursor = 0,
            .tree = tree,
            .cursor = tree.root().cursor(),
            .blocks = std.StringHashMap(Block).init(arena),
        };
    }

    pub fn finalCheck(self: Layout) !void {
        if (self.block_mode) {
            var it = self.blocks.valueIterator();
            while (it.next()) |block| switch (block.state) {
                .new => {
                    @panic("TODO: explain a template has a superfluous block");
                },
                .analysis => {
                    @panic("programming error: a block was never analyzed fully");
                },
                .done => {},
            };
        } else {
            if (self.print_cursor != self.html.len - 1) {
                @panic("programming error: the root template was not printed fully");
            }
        }
    }

    pub fn moveCursorToBlock(self: *Layout, id: []const u8, writer: anytype) !void {
        if (!self.block_mode) {
            @panic("programming error: layout is not in block mode");
        }
        if (self.cursor_busy) {
            @panic("programming error: tried to move cursor while busy");
        }
        if (self.current_block_id != null) {
            @panic("programming error: setting block when current block is active");
        }

        const block = self.blocks.getPtr(id) orelse {
            @panic("TODO: explain we couldn't find a block that we were supposed to extend");
        };

        if (block.state != .new) {
            @panic("programming error: starting analysis of a block that was aleady being analyzed");
        }

        // TODO: analize the block tag for correctness.

        const body = block.elem.node.childAt(1).?;
        try self.analyzeTag(block.elem, writer, .{ .skip_start_tag = true });

        block.state = .analysis;
        self.print_cursor = body.start();
        self.cursor.reset(body);
        self.cursor_busy = true;
        self.current_block_id = id;
    }

    fn setBlockMode(self: *Layout) !void {
        // validation
        {
            if (self.block_mode) {
                @panic("programming error: layout was already in block mode");
            }

            if (!self.cursor_busy) {
                @panic("programming error: tried to use an unset cursor");
            }

            const current = self.cursor.node() orelse {
                @panic("programming error: trying to scan for blocks but current node is null");
            };

            const elem = current.toElement() orelse {
                @panic("programming error: expected element, found something else");
            };

            if (!is(elem.tag(self.html), "zine")) {
                @panic("programming error: setBlockMode expects a cursor centered over <zine>");
            }
        }

        while (self.cursor.nextSibling()) |s| {
            if (is(s.nodeType(), "comment")) continue;
            const elem = s.toElement() orelse {
                @panic("TODO: explain that if <zine> is present, only comments and elements are ok");
            };

            const id_attr = elem.findAttr(self.html, "id") orelse {
                @panic("TODO: explain that in a template with <zine> all top-level elements must have an id");
            };

            const id = id_attr.value(self.html) orelse {
                @panic("TODO: explain that an id attribute must always have a value");
            };

            const gop = try self.blocks.getOrPut(id);
            if (gop.found_existing) {
                @panic("TODO: explain that a duplicate id was found");
            }

            gop.value_ptr.* = .{ .elem = elem };
        }

        self.block_mode = true;
        self.cursor_busy = false;
    }

    pub const Continuation = union(enum) {
        // A <zine> was found, contains template name
        zine: []const u8,
        // A <super> was found, contains relative id
        super: []const u8,
        // The block was analyzed to completion (in block mode)
        block_end,
        // The full template was analyzed to completion (in full doc mode)
        full_end,
    };

    pub fn analyze(self: *Layout, writer: anytype) !Continuation {
        if (!self.cursor_busy) {
            @panic("programming error: tried to use an unset cursor");
        }

        while (self.cursor.next()) |item| {
            const node = item.node;

            if (!is(node.nodeType(), "element")) continue;

            const elem = sitter.Element{ .node = node };

            // on zine, return template
            if (is(elem.tag(self.html), "zine")) {
                const template = try self.analyzeZineElem(elem);
                try self.setBlockMode();
                return .{ .zine = template };
            }

            // on super, return relative id
            if (is(elem.tag(self.html), "super")) {
                const id = try self.analyzeSuperElem(elem, writer);
                return .{ .super = id };
            }

            try self.analyzeTag(elem, writer, .{});
        }

        if (self.block_mode) {
            const id = self.current_block_id orelse {
                @panic("programming error: analysis was called in block mode but no block was active");
            };

            self.cursor_busy = false;
            const block = self.blocks.getPtr(id).?;
            if (block.state != .analysis) {
                @panic("programming error: analysis of a block not in analysis state");
            }
            block.state = .done;

            const end = blk: {
                const count = block.elem.node.childCount();
                const last = block.elem.node.childAt(count - 1).?;
                if (!is(last.nodeType(), "end_tag")) {
                    @panic("programming error: expected to find an end tag");
                }

                break :blk last.start();
            };

            try writer.writeAll(self.html[self.print_cursor..end]);
            self.print_cursor = end;
            self.current_block_id = null;
            return .block_end;
        }

        try writer.writeAll(self.html[self.print_cursor..]);

        self.print_cursor = self.html.len - 1;
        self.cursor_busy = false;
        return .full_end;
    }

    pub fn analyzeZineElem(self: *Layout, elem: sitter.Element) ![]const u8 {
        if (self.extends != null) {
            @panic("TODO: explain that a template can only have one zine tag");
        }

        {
            const parent_isnt_root = !self.tree.root().eq(elem.node.parent().?);
            var prev = elem.node.prev();
            const any_elem_before = while (prev) |p| : (prev = p.prev()) {
                if (!is(p.nodeType(), "comment")) break true;
            } else false;

            if (parent_isnt_root or any_elem_before) {
                @panic("TODO: explain that the zine tag must be the first tag in the document");
            }
        }

        var state: union(enum) { template, end: []const u8 } = .template;
        var attrs = elem.attrs();
        while (attrs.next()) |attr| switch (state) {
            .template => {
                if (!is(attr.name(self.html), "template")) {
                    @panic("TODO: explain that zine tag must have only a template attr");
                }

                const value = attr.value(self.html) orelse {
                    @panic("TODO: explain that template must have a value");
                };

                state = .{ .end = value };
            },
            .end => {
                @panic("TODO: explain that zine must only have the template attribute");
            },
        };

        switch (state) {
            .end => |t| {
                self.extends = t;
                return t;
            },
            .template => {
                @panic("TODO: explain that zine tag must have a template attribute");
            },
        }
    }

    fn analyzeSuperElem(self: *Layout, elem: sitter.Element, writer: anytype) ![]const u8 {
        // Validate
        if (elem.node.childAt(1) != null) {
            @panic("TODO: explain that super is a void tag");
        }

        if (elem.node.childAt(0).?.childAt(1) != null) {
            @panic("TODO: explain that super must not have attributes");
        }

        // Print the template up until <super>
        const offset = elem.node.offset();
        try writer.writeAll(self.html[self.print_cursor..offset.start]);
        self.print_cursor = offset.end;

        // Find relative id
        var parent = elem.node.parent();
        while (parent) |p| : (parent = p.parent()) {
            const parent_element = p.toElement() orelse {
                @panic("programming error: unexpected node type");
            };
            const id_attr = parent_element.findAttr(self.html, "id") orelse continue;
            const id = id_attr.value(self.html) orelse {
                @panic("TODO: explain that id must have a value");
            };

            return id;
        }

        @panic("TODO: explain that a <super> must always have an element with an id in its ancestry");
    }

    // Return true if it found a var="$page.content" attribute
    fn analyzeTag(
        self: *Layout,
        elem: sitter.Element,
        writer: anytype,
        opts: struct {
            skip_start_tag: bool = false,
        },
    ) !void {
        var attrs = elem.attrs();
        var before_var_attr = elem.tagNode().end();
        while (attrs.next()) |attr| : (before_var_attr = attr.node.end()) {
            if (!is(attr.name(self.html), "var")) continue;

            if (attrs.next() != null) {
                @panic("TODO: explain that var must be the last attr");
            }

            const value = attr.value(self.html) orelse {
                @panic("TODO: explain what was wrong");
            };

            if (!is(value, "$page.content")) {
                @panic("TODO: implement var attrs");
            }

            // We expect the node to not have any children and to have a closing tag.
            const end_tag = elem.node.childAt(1) orelse {
                @panic("TODO: explain why var tags cannot be placed in void tags");
            };

            if (!is(end_tag.nodeType(), "end_tag")) {
                @panic("TODO: explain why var bodies must be empty");
            }

            // Print everything up (but not including) the var attribute.
            {
                if (!opts.skip_start_tag) {
                    try writer.writeAll(self.html[self.print_cursor..before_var_attr]);
                    try writer.writeByte('>');
                }
                try writer.writeAll(self.md);
            }

            self.print_cursor = end_tag.start();
        }
    }
};
