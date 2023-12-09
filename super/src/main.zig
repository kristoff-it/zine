const std = @import("std");
const sitter = @import("sitter.zig");

/// Used to catch programming errors where a function fails to report
/// correctly that an error has occurred.
const Reported = error{
    /// The error has been fully reported.
    Reported,
    /// The error has been reported but we should also print the
    /// interface of the template we are extending.
    WantInterface,
};

pub fn main() void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch fatal("out of memory", .{});
    const out_path = args[1];
    const rendered_md_path = args[2];
    const md_name = args[3];
    const layout_path = args[4];
    const layout_name = args[5];
    const templates_dir_path = args[6];
    const dep_file_path = args[7];

    const rendered_md_string = readFile(rendered_md_path, arena) catch |err| {
        fatal("error while opening the rendered markdown file:\n{s}\n{s}\n", .{
            rendered_md_path,
            @errorName(err),
        });
    };

    const layout_html = readFile(layout_path, arena) catch |err| {
        fatal("error while opening the layout file:\n{s}\n{s}\n", .{
            layout_path,
            @errorName(err),
        });
    };

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        fatal("error while creating output file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };
    defer out_file.close();

    const dep_file = std.fs.cwd().createFile(dep_file_path, .{}) catch |err| {
        fatal("error while creating dep file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };
    defer dep_file.close();

    var dep_buf_writer = std.io.bufferedWriter(dep_file.writer());
    const dep_writer = dep_buf_writer.writer();
    dep_writer.print("target: {s} {s} ", .{ rendered_md_path, layout_path }) catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };

    var out_buf_writer = std.io.bufferedWriter(out_file.writer());
    const out_writer = out_buf_writer.writer();

    var templates = std.ArrayList(Template).init(arena);
    templates.append(Template.init(
        true, // is_layout
        layout_name,
        layout_path,
        layout_html,
        arena,
        rendered_md_string,
    )) catch fatal("out of memory", .{});

    // Same as Template.Extend, but it also remembers the slot in templates.
    const ExtendCtx = struct {
        extend: Template.Extend,
        idx: usize,
    };
    var names = std.StringHashMap(ExtendCtx).init(arena);

    // current template index
    var idx: usize = 0;

    // if that's not enough contact me for an enterprise license of Super
    var quota: usize = 100;
    while (quota > 0) : (quota -= 1) {
        const t = &templates.items[idx];

        const continuation = t.analyze(out_writer) catch |err| switch (err) {
            error.Reported => fatalTrace(idx -| 1, templates.items, md_name),
            error.WantInterface => {
                templates.items[idx + 1].showInterface();
                fatalTrace(idx, templates.items, md_name);
            },
        };
        switch (continuation) {
            .full_end => break,
            .extend => |e| {
                const gop = names.getOrPut(e.template) catch fatal("out of memory", .{});
                if (gop.found_existing) {
                    t.reportError(
                        e.node,
                        "EXTENSION LOOP DETECTED",
                        "We were trying to load the same template twice!",
                    ) catch {};

                    const ctx = gop.value_ptr;

                    std.debug.print("note: the template was previously found here:", .{});
                    templates.items[ctx.idx].templateDiagnostics(ctx.extend.node);

                    fatalTrace(idx, templates.items, md_name);
                }

                gop.value_ptr.* = .{ .extend = e, .idx = idx };

                const template_path = std.fs.path.join(arena, &.{
                    templates_dir_path,
                    e.template,
                }) catch fatal("out of memory", .{});
                dep_writer.print("{s} ", .{template_path}) catch |err| {
                    fatal("error writing to the dep file: {s}", .{@errorName(err)});
                };
                const template_html = readFile(template_path, arena) catch |err| {
                    t.reportError(
                        e.node,
                        "FILE I/O ERROR",
                        "An errror occurred while reading a file.",
                    ) catch {};
                    std.debug.print("The error encountered: {s}\n", .{
                        @errorName(err),
                    });
                    fatalTrace(idx, templates.items, md_name);
                };
                templates.append(Template.init(
                    false, // is_layout
                    e.template,
                    template_path,
                    template_html,
                    arena,
                    rendered_md_string,
                )) catch fatal("out of memory", .{});
                idx += 1;
            },
            .super => |s| {
                if (idx == 0) {
                    @panic("programming error: layout acting like it has <super/> in it");
                }
                idx -= 1;

                const super_template = &templates.items[idx];
                // std.debug.print("{s} -- {s} --> {s}\n", .{ t.name, id, super.name });
                super_template.moveCursorToBlock(s, out_writer) catch |err| {
                    if (err == error.ShowSuper) {
                        std.debug.print("note: extended block defined here:", .{});
                        t.templateDiagnostics(s.tag_name);
                    }

                    t.showInterface();
                    fatalTrace(idx, templates.items, md_name);
                };
            },
            .block_end => {
                idx += 1;
                if (idx == templates.items.len) {
                    @panic("programming error: bottom template acting like a block template");
                }
            },
        }
    } else {
        errorHeader("INFINITE LOOP",
            \\Super encountered a condition that caused an infinite loop.
            \\This should not have happened, please report this error to 
            \\the maintainers.
        , .{});
        std.process.exit(1);
    }

    for (templates.items, 0..) |l, i| l.finalCheck() catch |err| switch (err) {
        error.Reported => fatalTrace(i -| 1, templates.items, md_name),
        error.WantInterface => {
            templates.items[i + 1].showInterface();
            fatalTrace(i, templates.items, md_name);
        },
    };

    out_buf_writer.flush() catch |err| {
        fatal("error writing to the output file: {s}", .{@errorName(err)});
    };

    dep_writer.writeAll("\n") catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };
    dep_buf_writer.flush() catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };
}

fn fatalTrace(idx: usize, items: []const Template, md_name: []const u8) noreturn {
    std.debug.print("trace:\n", .{});
    var cursor = idx;
    while (cursor > 0) : (cursor -= 1) {
        std.debug.print("    template `{s}`,\n", .{
            items[cursor].name,
        });
    }

    std.debug.print("    layout `{s}`,\n", .{items[0].name});

    fatal("    content `{s}`.\n", .{
        md_name,
    });
}

fn readFile(path: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});

    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    return r.readAllAlloc(arena, 4096);
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.mem.eql(u8, str1, str2);
}

const Template = struct {
    is_layout: bool,
    name: []const u8,
    path: []const u8,
    html: []const u8,
    print_cursor: usize = 0,
    tree: sitter.Tree,

    // Template-wide analysis
    cursor: sitter.Cursor,
    cursor_busy: bool = true, // for programming errors

    // Analysis of `<extend/>`
    extends: ?[]const u8 = null,

    // Analysis of blocks
    blocks: std.StringHashMap(Block),
    block_mode: bool = false, // for programming errors
    current_block_id: ?[]const u8 = null, // for programming errors
    interface: std.StringHashMap(sitter.Node),

    // Scripting
    md: []const u8,

    const Block = struct {
        elem: sitter.Element,
        tag_name: sitter.Node,
        state: enum { new, analysis, done } = .new,
    };

    pub fn init(
        is_layout: bool,
        name: []const u8,
        path: []const u8,
        html: []const u8,
        arena: std.mem.Allocator,
        md: []const u8,
    ) Template {
        const tree = sitter.Tree.init(html);
        return .{
            .is_layout = is_layout,
            .name = name,
            .path = path,
            .html = html,
            .md = md,
            .tree = tree,
            .cursor = tree.root().cursor(),
            .blocks = std.StringHashMap(Block).init(arena),
            .interface = std.StringHashMap(sitter.Node).init(arena),
        };
    }

    pub fn finalCheck(self: Template) !void {
        if (self.block_mode) {
            var it = self.blocks.valueIterator();
            while (it.next()) |block| switch (block.state) {
                .new => {
                    const bad = block.elem.node.childAt(0).?.childAt(0).?;
                    self.reportError(bad, "UNBOUND BLOCK",
                        \\Found an unbound block, i.e. the extended template doesn't declare 
                        \\a corresponding super block. Either remove it from the current
                        \\template, or add a <super/> in the extended template. 
                    ) catch {};
                    return Reported.WantInterface;
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

    pub fn showInterface(self: Template) void {
        var cursor = self.tree.root().cursor();
        defer cursor.destroy();

        var found_first = false;

        while (cursor.next()) |s| {
            const elem = s.node.toElement() orelse continue;
            const tag = elem.tag();
            if (!is(tag.name().string(self.html), "super")) continue;
            const super = self.findSuperId(elem) orelse continue;
            const super_tag_name = super.tag_name.string(super.html);
            if (!found_first) {
                found_first = true;
                std.debug.print("\nExtended template interface ({s}):\n", .{self.name});
            }
            std.debug.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                super_tag_name,
                super.id,
                super_tag_name,
            });
        }
        if (!found_first) {
            std.debug.print(
                \\The extended template has no interface!
                \\Add <super/> tags to `{s}` to make it extensible. 
                \\
            , .{self.name});
        }
        std.debug.print("\n", .{});
    }

    const MoveCursorError = error{ShowSuper} || Reported;
    pub fn moveCursorToBlock(
        self: *Template,
        super: Super,
        writer: anytype,
    ) MoveCursorError!void {
        if (!self.block_mode) {
            @panic("programming error: layout is not in block mode");
        }
        if (self.cursor_busy) {
            @panic("programming error: tried to move cursor while busy");
        }
        if (self.current_block_id != null) {
            @panic("programming error: setting block when current block is active");
        }

        const block = self.blocks.getPtr(super.id) orelse {
            errorHeader("MISSING BLOCK",
                \\Missing `{s}` block in {s}.
                \\All <super/> blocks from the parent template must be defined. 
            , .{ super.id, self.name });
            return error.ShowSuper;
        };

        if (!is(block.tag_name.string(self.html), super.tag_name.string(super.html))) {
            self.reportError(block.tag_name, "TAG MISMATCH",
                \\The extended template defines a block with this same id,
                \\but with a different tag. The tags must match.
                \\Ensuring that tags between templates match reduces mistakes.
            ) catch {};

            return error.ShowSuper;
        }

        switch (block.state) {
            .new => {},
            .analysis => @panic("programming error: starting analysis of a block that was already being analyzed"),
            .done => @panic("programming error: starting analysis of a block that was already fully analyzed before"),
        }

        // TODO: analize the block tag for correctness.
        try self.analyzeTag(block.elem, writer, .{ .skip_start_tag = true });

        block.state = .analysis;
        self.cursor.reset(block.elem.node);

        // cursor.next() in self.analyze must yield the
        // first element in the body of the block.
        const tag = self.cursor.child().?; // start_tag
        _ = self.cursor.lastChild(); // last element in start_tag

        self.print_cursor = tag.end();
        self.cursor_busy = true;
        self.current_block_id = super.id;
    }

    fn setBlockMode(self: *Template) !void {
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

            if (!is(elem.tag().name().string(self.html), "extend")) {
                @panic("programming error: setBlockMode expects a cursor centered over <extend/>");
            }
        }

        while (self.cursor.nextSibling()) |s| {
            if (is(s.nodeType(), "comment")) continue;
            const elem = s.toElement() orelse {
                return self.reportError(s, "TODO: choose title", "bad blocks");
            };

            const tag = elem.tag();
            if (is(tag.name().string(self.html), "extend")) {
                self.unexpectedExtendTag(tag.name()) catch {};
                std.debug.print("Additionally, this template already has an <extend/> tag at\nthe top.\n\n", .{});
                return error.Reported;
            }

            const id_attr = tag.findAttr(self.html, "id") orelse {
                @panic("TODO: explain that in a template with <extend> all top-level elements must have an id");
            };

            const id = id_attr.value(self.html) orelse {
                @panic("TODO: explain that an id attribute must always have a value");
            };

            const gop = self.blocks.getOrPut(id) catch fatal("out of memory", .{});
            if (gop.found_existing) {
                self.reportError(tag.name(), "DUPLICATE BLOCK", "A duplicate block was found.") catch {};
                std.debug.print("note: previous definition found here:", .{});
                self.templateDiagnostics(gop.value_ptr.elem.tag().name());
                return Reported.Reported;
            }

            gop.value_ptr.* = .{
                .elem = elem,
                .tag_name = tag.name(),
            };
        }

        self.block_mode = true;
        self.cursor_busy = false;
    }

    pub const Continuation = union(enum) {
        // A <extend/> was found, contains template name and the extend node
        extend: Extend,
        // A <super/> was found, contains relative id
        super: Super,
        // The block was analyzed to completion (in block mode)
        block_end,
        // The full template was analyzed to completion (in full doc mode)
        full_end,
    };

    pub fn analyze(self: *Template, writer: anytype) Reported!Continuation {
        // std.debug.print("\n Analyzing: {s}\n", .{self.name});
        // self.debug(self.cursor.node(), "current node", .{});
        if (!self.cursor_busy) {
            @panic("programming error: tried to use an unset cursor");
        }

        while (self.cursor.next()) |item| {
            // self.debug(item.node, "analyzing", .{});

            if (is(item.node.nodeType(), "erroneous_end_tag")) {
                return self.reportError(item.node, "HTML SYNTAX ERROR",
                    \\An HTML syntax error was found in a template.
                );
            }

            if (is(item.node.nodeType(), "MISSING _implicit_end_tag")) {
                return self.reportError(item.node, "HTML SYNTAX ERROR",
                    \\An HTML syntax error was found in a template.
                );
            }

            const elem = item.node.toElement() orelse continue;
            const elem_name = elem.tag().name();
            const name = elem_name.string(self.html);

            // on extend, return template
            if (is(name, "extend")) {
                const extend = try self.analyzeExtend(elem);
                try self.setBlockMode();
                return .{ .extend = extend };
            }

            // on super, return relative id
            if (is(name, "super")) {
                const s = try self.analyzeSuper(elem, writer);
                const gop = self.interface.getOrPut(s.id) catch fatal("out of memory", .{});
                if (gop.found_existing) {
                    self.reportError(elem_name, "UNEXPECTED SUPER TAG",
                        \\All <super/> tags must have an ancestor element with an id,
                        \\which is what defines a block, and each block can only have
                        \\one <super/> tag.
                        \\
                        \\Add an `id` attribute to a new element to split them into
                        \\two blocks, or remove one. 
                    ) catch {};
                    std.debug.print("note: this is where the other tag is:", .{});
                    self.templateDiagnostics(gop.value_ptr.*);
                    std.debug.print("note: both refer to this ancestor:", .{});
                    self.templateDiagnostics(s.tag_name);
                    return error.Reported;
                }

                gop.value_ptr.* = elem_name;
                return .{ .super = s };
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

            const end = block.elem.node.end();

            writer.writeAll(self.html[self.print_cursor..end]) catch |err| {
                fatal("error writing to output file: {s}", .{@errorName(err)});
            };
            self.print_cursor = end;
            self.current_block_id = null;
            return .block_end;
        }

        writer.writeAll(self.html[self.print_cursor..]) catch |err| {
            fatal("error writing to output file: {s}", .{@errorName(err)});
        };

        self.print_cursor = self.html.len - 1;
        self.cursor_busy = false;
        return .full_end;
    }

    pub const Extend = struct {
        template: []const u8,
        node: sitter.Node,
    };
    pub fn analyzeExtend(self: *Template, elem: sitter.Element) !Extend {
        const tag = elem.tag();
        // validation
        {
            if (self.extends != null) {
                return self.unexpectedExtendTag(tag.name());
            }

            if (!tag.is_self_closing) {
                return self.reportError(tag.name(), "OPEN EXTEND TAG",
                    \\The extend tag must be closed immediately (i.e.: <extend template="foo.html"/>).
                    \\It must be done otherwise parsers will assume that all 
                    \\content after is *inside* of it.
                    \\
                    \\Cursed read: https://www.w3.org/TR/2014/REC-html5-20141028/syntax.html#optional-tags
                );
            }

            const parent_isnt_root = !self.tree.root().eq(elem.node.parent().?);
            var prev = elem.node.prev();
            const any_elem_before = while (prev) |p| : (prev = p.prev()) {
                if (!is(p.nodeType(), "comment")) break true;
            } else false;

            if (parent_isnt_root or any_elem_before) {
                return self.unexpectedExtendTag(tag.name());
            }
        }

        var state: union(enum) { template, end: Extend } = .template;
        var attrs = tag.attrs();
        while (attrs.next()) |attr| switch (state) {
            .template => {
                const attr_name = attr.name();
                if (!is(attr_name.string(self.html), "template")) {
                    std.debug.print("TODO: explain that extend tag must have only a template attr", .{});
                    std.process.exit(1);
                }

                const value = attr.value(self.html) orelse {
                    @panic("TODO: explain that template must have a value");
                };

                state = .{
                    .end = .{
                        .template = value,
                        .node = attr_name,
                    },
                };
            },
            .end => {
                const attr_name = attr.name();
                return self.reportError(attr_name, "BAD EXTEND TAG",
                    \\Unwanted attribute in <extend/> tag
                    \\Extend tags are expected to only contain a `template` attribute.
                );
            },
        };

        switch (state) {
            .end => |t| {
                self.extends = t.template;
                return t;
            },
            .template => {
                @panic("TODO: explain that extend tag must have a template attribute");
            },
        }
    }

    fn reportError(
        self: Template,
        bad_node: sitter.Node,
        comptime title: []const u8,
        comptime msg: []const u8,
    ) Reported {
        errorHeader(title, msg, .{});
        self.templateDiagnostics(bad_node);
        return error.Reported;
    }

    fn templateDiagnostics(
        self: Template,
        node: sitter.Node,
    ) void {
        const pos = node.selection();
        const line_off = node.line(self.html);
        const offset = node.offset();

        // trim spaces
        const line_trim_left = std.mem.trimLeft(u8, line_off.line, &std.ascii.whitespace);
        const start_trim_left = line_off.start + line_off.line.len - line_trim_left.len;

        const caret_len = offset.end - offset.start;
        const caret_spaces_len = offset.start - start_trim_left;

        const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

        var buf: [1024]u8 = undefined;

        const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
            const h = buf[0 .. caret_len + caret_spaces_len];
            @memset(h[0..caret_spaces_len], ' ');
            @memset(h[caret_spaces_len..][0..caret_len], '^');
            break :blk h;
        } else "";

        std.debug.print(
            \\
            \\({s}) {s}:{}:{}:
            \\    {s}
            \\    {s}
            \\
        , .{
            self.name,     self.path,
            pos.start.row, pos.start.col,
            line_trim,     highlight,
        });
    }

    const Super = struct {
        id: []const u8,
        tag_name: sitter.Node,
        html: []const u8,
    };

    fn analyzeSuper(self: *Template, elem: sitter.Element, writer: anytype) !Super {
        // Validate
        {
            if (self.is_layout) {
                return self.reportError(elem.node.childAt(0).?, "LAYOUT WITH SUPER TAG",
                    \\A layout cannot have <super/> in it. If you want to turn this
                    \\file into an extensible template, you must move it to 
                    \\`templates/` and have your content reference a different layout.
                );
            }
            const sct = elem.node.childAt(0).?;
            if (!is(sct.nodeType(), "self_closing_tag")) {
                return self.reportError(elem.node.childAt(0).?, "BAD SUPER TAG",
                    \\Super tags must be closed immediately (i.e.: <super/>).
                    \\It must be done otherwise parsers will assume that all 
                    \\subsequent content is *inside* of it.
                    \\
                    \\Cursed read: https://www.w3.org/TR/2014/REC-html5-20141028/syntax.html#optional-tags
                );
            }

            if (sct.childAt(1) != null) {
                std.debug.print("TODO: explain that super must not have attributes", .{});
                std.process.exit(1);
            }
        }

        // Print the template up until <super/>
        const offset = elem.node.offset();
        writer.writeAll(self.html[self.print_cursor..offset.start]) catch |err| {
            fatal("error writing to output file: {s}", .{@errorName(err)});
        };
        self.print_cursor = offset.end;

        return self.findSuperId(elem) orelse {
            @panic("TODO: explain that a <super/> must always have an element with an id in its ancestry");
        };
    }

    fn findSuperId(self: Template, elem: sitter.Element) ?Super {
        // Find relative id
        var parent = elem.node.parent();
        while (parent) |p| : (parent = p.parent()) {
            const parent_element = p.toElement() orelse {
                @panic("programming error: unexpected node type");
            };
            const tag = parent_element.tag();
            const id_attr = tag.findAttr(self.html, "id") orelse continue;
            const id = id_attr.value(self.html) orelse {
                @panic("TODO: explain that id must have a value");
            };

            return .{ .id = id, .tag_name = tag.name(), .html = self.html };
        }
        return null;
    }
    // Return true if it found a var="$page.content" attribute
    fn analyzeTag(
        self: *Template,
        elem: sitter.Element,
        writer: anytype,
        opts: struct {
            skip_start_tag: bool = false,
        },
    ) Reported!void {
        const tag = elem.tag();
        var attrs = tag.attrs();
        var before_var_attr = tag.node.end();
        while (attrs.next()) |attr| : (before_var_attr = attr.node.end()) {
            if (is(attr.name().string(self.html), "debug")) {
                self.debug(elem.node, "found debug attribute", .{});
                fatal("debug attribute found, aborting", .{});
            }
            if (!is(attr.name().string(self.html), "var")) continue;

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
            // const end_tag = elem.node.childAt(1) orelse {
            //     @panic("TODO: explain why var tags cannot be placed in void tags");
            // };

            // if (!is(end_tag.nodeType(), "end_tag")) {
            //     @panic("TODO: explain why var bodies must be empty");
            // }

            // Print everything up (but not including) the var attribute.
            {
                if (!opts.skip_start_tag) {
                    writer.writeAll(self.html[self.print_cursor..before_var_attr]) catch |err| {
                        fatal("error writing to output file: {s}", .{@errorName(err)});
                    };
                    writer.writeByte('>') catch |err| {
                        fatal("error writing to output file: {s}", .{@errorName(err)});
                    };
                }
                writer.writeAll(self.md) catch |err| {
                    fatal("error writing to output file: {s}", .{@errorName(err)});
                };
            }

            self.print_cursor = elem.node.end();
        }
    }

    fn unexpectedExtendTag(self: Template, tag_name: sitter.Node) Reported {
        return self.reportError(tag_name, "UNEXPECTED EXTEND TAG",
            \\The <extend/> tag can only be present at the beginning of a 
            \\template and it can only be preceeded by HTML comments and
            \\whitespace. 
        );
    }

    fn debug(self: Template, node: ?sitter.Node, comptime fmt: []const u8, args: anytype) void {
        std.debug.print("\n", .{});
        std.debug.print(fmt, args);
        if (node) |n| {
            std.debug.print("\n{s}\n", .{
                n.string(self.html),
            });
            n.debug();
            std.debug.print("\n", .{});
        }
    }
};

fn errorHeader(
    comptime title: []const u8,
    comptime msg: []const u8,
    msg_args: anytype,
) void {
    std.debug.print(
        \\
        \\---------- {s} ----------
        \\
    , .{title});
    std.debug.print(msg, msg_args);
    std.debug.print("\n", .{});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
