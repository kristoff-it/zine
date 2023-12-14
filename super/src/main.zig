const std = @import("std");
const sitter = @import("sitter.zig");
const script = @import("script.zig");
const errors = @import("errors.zig");
const fatal = errors.fatal;
const oom = errors.oom;

const Reported = errors.Reported;

pub fn main() void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
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
    )) catch oom();

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
                const gop = names.getOrPut(e.template) catch oom();
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
                }) catch oom();
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
                )) catch oom();
                idx += 1;
            },
            .super => |s| {
                if (idx == 0) {
                    @panic("programming error: layout acting like it has <super/> in it");
                }
                idx -= 1;

                const super_template = &templates.items[idx];
                // std.debug.print("{s} -- {s} --> {s}\n", .{ t.name, id, super.name });
                super_template.moveCursorToBlock(s, out_writer) catch |err| switch (err) {
                    error.ShowSuper => {
                        std.debug.print("note: extended block defined here:", .{});
                        t.templateDiagnostics(s.tag_name);
                        t.showInterface();
                        fatalTrace(idx, templates.items, md_name);
                    },
                    error.WantInterface => {
                        t.showInterface();
                        fatalTrace(idx, templates.items, md_name);
                    },

                    error.Reported => {
                        fatalTrace(idx, templates.items, md_name);
                    },
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
        errors.header("INFINITE LOOP",
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
    arena: std.mem.Allocator,

    // Template-wide analysis
    cursor: sitter.Cursor,
    cursor_busy: bool = true, // for programming errors
    script_vm: script.Interpreter,
    if_stack: std.ArrayListUnmanaged(IfBlock) = .{},

    // Analysis of `<extend/>`
    extends: ?[]const u8 = null,

    // Analysis of blocks
    blocks: std.StringHashMapUnmanaged(Block) = .{},
    block_mode: bool = false, // for programming errors
    current_block_id: ?[]const u8 = null, // for programming errors
    interface: std.StringHashMapUnmanaged(sitter.Node) = .{},

    // Scripting
    md: []const u8,

    const Block = struct {
        elem: sitter.Element,
        tag_name: sitter.Node,
        state: enum { new, analysis, done } = .new,
    };

    const IfBlock = struct {
        result: bool,
        node: sitter.Node,
        name: sitter.Node,
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
            .arena = arena,
            .script_vm = script.Interpreter.init(.{
                .version = "v0",
                .page = .{
                    .title = "test",
                    .draft = false,
                    .content = md,
                },
                .site = .{
                    .name = "my website",
                },
            }),
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
            errors.header("MISSING BLOCK",
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

            const id_value = id_attr.value() orelse {
                @panic("TODO: explain that an id attribute must always have a value");
            };

            const id = id_value.unquote(self.html);

            if (std.mem.indexOfScalar(u8, id, '$')) |_| {
                @panic("TODO: explain that you can't put any scripting stuff in id");
            }

            const gop = self.blocks.getOrPut(self.arena, id) catch oom();
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

            if (is(item.node.nodeType(), "erroneous_end_tag") or
                is(item.node.nodeType(), "MISSING _implicit_end_tag"))
            {
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
                const gop = self.interface.getOrPut(self.arena, s.id) catch oom();
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

            // programming errors
            self.cursor_busy = false;
            const block = self.blocks.getPtr(id).?;
            if (block.state != .analysis) {
                @panic("programming error: analysis of a block not in analysis state");
            }
            block.state = .done;

            const end = block.elem.node.lastChild().?.start();

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

                const value = attr.value() orelse {
                    @panic("TODO: explain that template must have a value");
                };

                const template_name = value.unquote(self.html);

                state = .{
                    .end = .{
                        .template = template_name,
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
            const value = id_attr.value() orelse {
                @panic("TODO: explain that id must have a value");
            };

            const id = value.unquote(self.html);
            if (std.mem.indexOfScalar(u8, id, '$')) |_| {
                @panic("TODO: explain that ids should not contain scripting");
            }

            return .{ .id = id, .tag_name = tag.name(), .html = self.html };
        }
        return null;
    }

    const AnalyzeOpts = struct {
        skip_start_tag: bool = false,
    };
    // Return true if it found a var="$page.content" attribute
    fn analyzeTag(
        self: *Template,
        elem: sitter.Element,
        writer: anytype,
        opts: AnalyzeOpts,
    ) Reported!void {
        const tag = elem.tag();
        var attrs = tag.attrs();
        var last_attr_end = tag.name().end();

        var attrs_seen = std.StringHashMap(sitter.Node).init(self.arena);
        while (attrs.next()) |attr| : (last_attr_end = attr.node.end()) {
            const name = attr.name();
            const name_string = name.string(self.html);
            // validation
            {
                const gop = attrs_seen.getOrPut(name_string) catch oom();
                if (gop.found_existing) {
                    self.reportError(name, "DUPLICATE ATTRIBUTE",
                        \\HTML elements cannot contain duplicated attributes
                    ) catch {};
                    std.debug.print("node: previous instance was here:", .{});
                    self.templateDiagnostics(gop.value_ptr.*);
                    return error.Reported;
                }
                gop.value_ptr.* = name;
            }
            if (is(name_string, "debug")) {
                self.debug(elem.node, "found debug attribute", .{});
                fatal("debug attribute found, aborting", .{});
            }

            // var
            if (is(name_string, "var")) {
                if (attr.node.next() != null) {
                    @panic("TODO: explain that var must be the last attr");
                }
                try self.analyzeVarAttr(attr, opts, writer, last_attr_end);
                self.print_cursor = elem.node.end();
                continue;
            }

            // if
            if (is(name_string, "if")) {
                if (attr.node.next() != null) {
                    @panic("TODO: explain that var must be the last attr");
                }
                const result = try self.analyzeIfAttr(elem, attr, opts, writer, last_attr_end);
                self.if_stack.append(self.arena, .{
                    .result = result,
                    .node = elem.node,
                    .name = name,
                }) catch
                    oom();

                continue;
            }
            // else
            if (is(name_string, "else")) {
                if (attr.value()) |v| {
                    return self.reportError(v.node, "ELSE ATTRIBUTE WITH VALUE",
                        \\`else` attributes cannot have a value.
                    );
                }
                if (attr.node.next() != null) {
                    @panic("TODO: explain that var must be the last attr");
                }

                const last_if = self.if_stack.popOrNull() orelse {
                    return self.reportError(name, "LONELY ELSE",
                        \\Elements with an `else` attribute must come right after
                        \\an element with an `if` attribute. Make sure to nest them
                        \\correctly.
                    );
                };

                var current = last_if.node.next();
                var distance: usize = 0;
                while (current) |c| : (current = c.next()) {
                    distance += 1;
                    if (c.eq(elem.node)) break;
                } else {
                    return self.reportError(name, "LONELY ELSE",
                        \\Elements with an `else` attribute must come right after
                        \\an element with an `if` attribute. Make sure to nest them
                        \\correctly.
                    );
                }

                if (distance > 1) {
                    self.reportError(name, "STRANDED ELSE",
                        \\Elements with an `else` attribute must come right after
                        \\an element with an `if` attribute. Make sure to nest them
                        \\correctly.
                    ) catch {};
                    std.debug.print("\nnote: corresponding if: ", .{});
                    self.templateDiagnostics(last_if.name);
                    if (distance == 2) {
                        std.debug.print("note: inbetween: ", .{});
                    } else {
                        std.debug.print("note: inbetween (plus {} more): ", .{distance - 1});
                    }
                    const inbetween = last_if.node.next().?;
                    const bad = if (inbetween.toElement()) |e|
                        e.tag().name()
                    else
                        inbetween;
                    self.templateDiagnostics(bad);
                    return error.Reported;
                }

                if (!last_if.result) {
                    // Print everything up (but not including) the var attribute.
                    if (!opts.skip_start_tag) {
                        writer.writeAll(self.html[self.print_cursor..last_attr_end]) catch |err| {
                            fatal("error writing to output file: {s}", .{@errorName(err)});
                        };
                        self.print_cursor = attr.node.end();
                    }
                } else {
                    // Print everything up to the element start
                    if (!opts.skip_start_tag) {
                        writer.writeAll(self.html[self.print_cursor..elem.node.start()]) catch |err| {
                            fatal("error writing to output file: {s}", .{@errorName(err)});
                        };
                        self.print_cursor = elem.node.end();
                    }
                }

                continue;
            }
        }
    }

    fn analyzeVarAttr(
        self: *Template,
        attr: sitter.Tag.Attr,
        opts: AnalyzeOpts,
        writer: anytype,
        last_attr_end: u32,
    ) !void {
        const value = attr.value() orelse {
            @panic("TODO: explain that var needs a value");
        };

        // NOTE: it's fundamental to get right string memory management
        //       semantics. In this case it doesn't matter because the
        //       output string doesn't need to survive past this scope.
        const code = value.unescape(self.html, self.arena) catch oom();
        defer code.free(self.arena);

        // const diag: script.Interpreter.Diagnostics = .{};
        const result = self.script_vm.run(code.str, self.arena, null) catch |err| {
            // set the last arg to &diag when implementing this
            self.reportError(value.node, "SCRIPT EVAL ERROR",
                \\An error was encountered while evaluating a script.
            ) catch {};

            std.debug.print("Error: {}\n", .{err});
            std.debug.print("TODO: show precise location of the error\n\n", .{});
            return error.Reported;
        };

        const string = switch (result) {
            .string => |s| s,
            else => @panic("TODO: explain that a var tag evaluated to a non-string"),
        };

        // We expect the node to not have any children and to have a closing tag.
        // const end_tag = elem.node.childAt(1) orelse {
        //     @panic("TODO: explain why var tags cannot be placed in void tags");
        // };

        // if (!is(end_tag.nodeType(), "end_tag")) {
        //     @panic("TODO: explain why var bodies must be empty");
        // }

        // Print everything up (but not including) the var attribute.
        if (!opts.skip_start_tag) {
            writer.writeAll(self.html[self.print_cursor..last_attr_end]) catch |err| {
                fatal("error writing to output file: {s}", .{@errorName(err)});
            };
            writer.writeByte('>') catch |err| {
                fatal("error writing to output file: {s}", .{@errorName(err)});
            };
        }
        writer.writeAll(string) catch |err| {
            fatal("error writing to output file: {s}", .{@errorName(err)});
        };
    }
    fn analyzeIfAttr(
        self: *Template,
        elem: sitter.Element,
        attr: sitter.Tag.Attr,
        opts: AnalyzeOpts,
        writer: anytype,
        last_attr_end: u32,
    ) !bool {
        const value = attr.value() orelse {
            @panic("TODO: explain that if needs a value");
        };

        // NOTE: it's fundamental to get right string memory management
        //       semantics. In this case it doesn't matter because the
        //       correct output is going to be a boolean.
        const code = value.unescape(self.html, self.arena) catch oom();
        defer code.free(self.arena);

        // const diag: script.Interpreter.Diagnostics = .{};
        const result = self.script_vm.run(code.str, self.arena, null) catch |err| {
            // set the last arg to &diag when implementing this
            self.reportError(value.node, "SCRIPT EVAL ERROR",
                \\An error was encountered while evaluating a script.
            ) catch {};

            std.debug.print("Error: {}\n", .{err});
            std.debug.print("TODO: show precise location of the error\n\n", .{});
            return error.Reported;
        };

        const should_print_element = switch (result) {
            .bool => |b| b,
            else => @panic("TODO: explain that an if tag evaluated to a non-bool"),
        };

        if (should_print_element) {
            // Print everything up (but not including) the var attribute.
            if (!opts.skip_start_tag) {
                writer.writeAll(self.html[self.print_cursor..last_attr_end]) catch |err| {
                    fatal("error writing to output file: {s}", .{@errorName(err)});
                };
                self.print_cursor = attr.node.end();
            }
        } else {
            // Print everything up to the element start
            if (!opts.skip_start_tag) {
                writer.writeAll(self.html[self.print_cursor..elem.node.start()]) catch |err| {
                    fatal("error writing to output file: {s}", .{@errorName(err)});
                };
                self.print_cursor = elem.node.end();
            }
        }

        return should_print_element;
    }

    fn unexpectedExtendTag(self: Template, tag_name: sitter.Node) Reported {
        return self.reportError(tag_name, "UNEXPECTED EXTEND TAG",
            \\The <extend/> tag can only be present at the beginning of a 
            \\template and it can only be preceeded by HTML comments and
            \\whitespace. 
        );
    }

    fn reportError(
        self: Template,
        bad_node: sitter.Node,
        comptime title: []const u8,
        comptime msg: []const u8,
    ) Reported {
        return errors.report(
            self.name,
            self.path,
            bad_node,
            self.html,
            title,
            msg,
        );
    }

    fn templateDiagnostics(self: Template, bad_node: sitter.Node) Reported {
        return errors.diagnostics(self.name, self.path, bad_node, self.html);
    }
};

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

test {
    _ = @import("parser.zig");
}
