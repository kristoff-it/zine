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

    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const w = buf_writer.writer();

    var layouts = std.ArrayList(Layout).init(arena);
    layouts.append(Layout.init(
        layout_name,
        layout_path,
        layout_html,
        arena,
        rendered_md_string,
    )) catch fatal("out of memory", .{});

    // current layout index
    var idx: usize = 0;

    // if that's not enough contact me for an enterprise license of Zine
    var quota: usize = 100_000_000;
    while (quota > 0) : (quota -= 1) {
        const l = &layouts.items[idx];

        const continuation = l.analyze(w) catch |err| switch (err) {
            error.Reported => fatalTrace(idx -| 1, layouts.items, md_name),
            error.WantInterface => {
                layouts.items[idx + 1].showInterface();
                fatalTrace(idx, layouts.items, md_name);
            },
        };
        switch (continuation) {
            .full_end => break,
            .zine => |z| {
                const path = std.fs.path.join(arena, &.{
                    templates_dir_path,
                    z.template,
                }) catch fatal("out of memory", .{});
                const template_html = readFile(path, arena) catch |err| {
                    l.reportError(
                        z.node,
                        "FILE I/O ERROR",
                        "An errror occurred while reading a file.",
                    ) catch {};
                    std.debug.print("The error encountered: {s}\n", .{
                        @errorName(err),
                    });
                    fatalTrace(idx, layouts.items, md_name);
                };
                layouts.append(Layout.init(
                    z.template,
                    path,
                    template_html,
                    arena,
                    rendered_md_string,
                )) catch fatal("out of memory", .{});
                idx += 1;
            },
            .super => |id| {
                if (idx == 0) {
                    @panic("programming error: layout acting like it has <super> in it");
                }
                idx -= 1;

                const super = &layouts.items[idx];
                super.moveCursorToBlock(id, w) catch {
                    l.showInterface();
                    fatalTrace(idx, layouts.items, md_name);
                };
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

    for (layouts.items, 0..) |l, i| l.finalCheck() catch |err| switch (err) {
        error.Reported => fatalTrace(i -| 1, layouts.items, md_name),
        error.WantInterface => {
            layouts.items[i + 1].showInterface();
            fatalTrace(i, layouts.items, md_name);
        },
    };

    buf_writer.flush() catch |err| {
        fatal("error writing to the output file: {s}", .{@errorName(err)});
    };
}

fn fatalTrace(idx: usize, items: []const Layout, md_name: []const u8) noreturn {
    std.debug.print("trace:\n", .{});
    var cursor = idx;
    while (cursor > 0) : (cursor -= 1) {
        std.debug.print("\ttemplate `{s}`,\n", .{
            items[cursor].name,
        });
    }

    std.debug.print("\tlayout `{s}`,\n", .{items[0].name});

    fatal("\tcontent `{s}`.\n", .{
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

const Layout = struct {
    name: []const u8,
    path: []const u8,
    html: []const u8,
    print_cursor: usize = 0,
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

    pub fn init(
        name: []const u8,
        path: []const u8,
        html: []const u8,
        arena: std.mem.Allocator,
        md: []const u8,
    ) Layout {
        const tree = sitter.Tree.init(html);
        return .{
            .name = name,
            .path = path,
            .html = html,
            .md = md,
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
                    const bad = block.elem.node.childAt(0).?.childAt(0).?;
                    self.reportError(bad, "UNBOUND BLOCK",
                        \\Found an unbound block, i.e. the extended template doesn't declare 
                        \\a corresponding super block. Either remove it from the current
                        \\template, or add a <super> in the extended template. 
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

    pub fn showInterface(self: Layout) void {
        std.debug.print("\nInterface for the extended template ({s}):\n", .{self.name});

        var cursor = self.tree.root().cursor();
        defer cursor.destroy();

        while (cursor.next()) |s| {
            const elem = s.node.toElement() orelse continue;
            if (!is(elem.tag(self.html), "super")) continue;
            const id = self.findSuperId(elem) orelse continue;
            std.debug.print("\t{s}\n", .{id});
        }
        std.debug.print("\n", .{});
    }

    pub fn moveCursorToBlock(self: *Layout, id: []const u8, writer: anytype) Reported!void {
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
            std.debug.print(
                \\Missing `{s}` block in {s}.
                \\All <super> blocks from the parent template ({s}) must be defined. 
                \\
            , .{ id, self.name, self.extends.? });
            return error.WantInterface;
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

            const gop = self.blocks.getOrPut(id) catch fatal("out of memory", .{});
            if (gop.found_existing) {
                @panic("TODO: explain that a duplicate id was found");
            }

            gop.value_ptr.* = .{ .elem = elem };
        }

        self.block_mode = true;
        self.cursor_busy = false;
    }

    pub const Continuation = union(enum) {
        // A <zine> was found, contains template name and the zine node
        zine: Zine,
        // A <super> was found, contains relative id
        super: []const u8,
        // The block was analyzed to completion (in block mode)
        block_end,
        // The full template was analyzed to completion (in full doc mode)
        full_end,
    };

    pub fn analyze(self: *Layout, writer: anytype) Reported!Continuation {
        if (!self.cursor_busy) {
            @panic("programming error: tried to use an unset cursor");
        }

        while (self.cursor.next()) |item| {
            const node = item.node;

            if (!is(node.nodeType(), "element")) continue;

            const elem = sitter.Element{ .node = node };

            // on zine, return template
            if (is(elem.tag(self.html), "zine")) {
                const zine = try self.analyzeZineElem(elem);
                try self.setBlockMode();
                return .{ .zine = zine };
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

    const Zine = struct {
        template: []const u8,
        node: sitter.Node,
    };
    pub fn analyzeZineElem(self: *Layout, elem: sitter.Element) !Zine {
        // validation
        {
            if (self.extends != null) {
                @panic("TODO: explain that a template can only have one zine tag");
            }

            if (elem.node.childAt(1) != null) {
                return self.reportError(elem.node.childAt(0).?, "BAD ZINE TAG",
                    \\The zine tag must be closed immediately (i.e.: <zine template="foo.html"/>).
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
                @panic("TODO: explain that the zine tag must be the first tag in the document");
            }
        }

        var state: union(enum) { template, end: Zine } = .template;
        var attrs = elem.attrs();
        while (attrs.next()) |attr| switch (state) {
            .template => {
                if (!is(attr.name(self.html), "template")) {
                    std.debug.print("TODO: explain that zine tag must have only a template attr", .{});
                    std.process.exit(1);
                }

                const value = attr.value(self.html) orelse {
                    @panic("TODO: explain that template must have a value");
                };

                state = .{
                    .end = .{
                        .template = value,
                        .node = attr.nameNode(),
                    },
                };
            },
            .end => {
                const name_node = attr.node.childAt(0).?;
                return self.reportError(name_node, "BAD ZINE TAG",
                    \\Unwanted attribute in <zine> tag: it can only contain a `template` attribute.
                );
            },
        };

        switch (state) {
            .end => |t| {
                self.extends = t.template;
                return t;
            },
            .template => {
                @panic("TODO: explain that zine tag must have a template attribute");
            },
        }
    }

    fn reportError(
        self: Layout,
        bad_node: sitter.Node,
        title: []const u8,
        msg: []const u8,
    ) Reported {
        const pos = bad_node.selection();
        const line_pos = bad_node.line(self.html);
        const offset = bad_node.offset();
        const len = offset.end - offset.start;
        const spaces_len = offset.start - line_pos.start;

        var buf: [1024]u8 = undefined;

        const highlight = if (len + spaces_len < 1024) blk: {
            const h = buf[0 .. len + spaces_len];
            @memset(h[0..spaces_len], ' ');
            @memset(h[spaces_len..][0..len], '^');
            break :blk h;
        } else "";

        std.debug.print(
            \\
            \\---------- {s} ----------
            \\{s}
            \\
            \\({s}) {s}:{}:{}:
            \\{s}
            \\{s}
            \\
        , .{
            title,         msg,
            self.name,     self.path,
            pos.start.row, pos.start.col,
            line_pos.line, highlight,
        });
        return error.Reported;
    }

    fn analyzeSuperElem(self: *Layout, elem: sitter.Element, writer: anytype) ![]const u8 {
        // Validate
        if (elem.node.childAt(1) != null) {
            return self.reportError(elem.node.childAt(0).?, "BAD SUPER TAG",
                \\The super tag must be closed immediately (i.e.: <super/>).
                \\It must be done otherwise parsers will assume that all 
                \\content after is *inside* of it.
                \\
                \\Cursed read: https://www.w3.org/TR/2014/REC-html5-20141028/syntax.html#optional-tags
            );
        }

        if (elem.node.childAt(0).?.childAt(1) != null) {
            std.debug.print("TODO: explain that super must not have attributes", .{});
            std.process.exit(1);
        }

        // Print the template up until <super>
        const offset = elem.node.offset();
        writer.writeAll(self.html[self.print_cursor..offset.start]) catch |err| {
            fatal("error writing to output file: {s}", .{@errorName(err)});
        };
        self.print_cursor = offset.end;

        return self.findSuperId(elem) orelse {
            @panic("TODO: explain that a <super> must always have an element with an id in its ancestry");
        };
    }

    fn findSuperId(self: Layout, elem: sitter.Element) ?[]const u8 {

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
        return null;
    }
    // Return true if it found a var="$page.content" attribute
    fn analyzeTag(
        self: *Layout,
        elem: sitter.Element,
        writer: anytype,
        opts: struct {
            skip_start_tag: bool = false,
        },
    ) Reported!void {
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

            self.print_cursor = end_tag.start();
        }
    }
};

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
