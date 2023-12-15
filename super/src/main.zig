const std = @import("std");
const SuperTree = @import("SuperTree.zig");
const SuperNode = SuperTree.SuperNode;
const sitter = @import("sitter.zig");
const script = @import("script.zig");
const errors = @import("errors.zig");
const fatal = errors.fatal;
const oom = errors.oom;

const Reported = errors.Reported;
pub const Block = struct {
    node: *const SuperNode,
    state: enum { new, analysis, done } = .new,
};

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
    const layout_tree = SuperTree.init(
        arena,
        layout_name,
        layout_path,
        layout_html,
    ) catch |err| {
        assert(@src(), err == error.Reported);
        var t: Template = undefined;
        t.name = layout_name;
        fatalTrace(0, &.{t}, md_name);
    };

    const layout = Template.init(
        arena,
        layout_name,
        layout_path,
        layout_tree,
        rendered_md_string,
        .layout,
    ) catch oom();
    templates.append(layout) catch oom();

    // load all templates, detect import loops
    {
        var names = std.StringHashMap(
            struct { extend: *SuperNode, idx: usize },
        ).init(arena);
        defer names.deinit();

        while (templates.items[templates.items.len - 1].extends) |ext| {
            const current_idx = templates.items.len - 1;
            const current = templates.items[current_idx];
            const template_value = ext.templateValue();
            const template_name = template_value.unquote(current.html);

            const gop = names.getOrPut(template_name) catch oom();
            if (gop.found_existing) {
                current.reportError(
                    template_value.node,
                    "infinite_loop",
                    "EXTENSION LOOP DETECTED",
                    "We were trying to load the same template twice!",
                ) catch {};

                const ctx = gop.value_ptr;
                templates.items[ctx.idx].diagnostic(
                    "note: the template was previously found here:",
                    ctx.extend.templateValue().node,
                );

                fatalTrace(templates.items.len - 1, templates.items, md_name);
            }

            gop.value_ptr.* = .{ .extend = ext, .idx = current_idx };

            const template_path = std.fs.path.join(
                arena,
                &.{ templates_dir_path, template_name },
            ) catch oom();
            dep_writer.print("{s} ", .{template_path}) catch |err| {
                fatal("error writing to the dep file: {s}", .{@errorName(err)});
            };
            const template_html = readFile(template_path, arena) catch |err| {
                current.reportError(
                    template_value.node,
                    "io_error",
                    "FILE I/O ERROR",
                    "An errror occurred while reading a file.",
                ) catch {};
                std.debug.print("The error encountered: {s}\n", .{
                    @errorName(err),
                });
                fatalTrace(current_idx, templates.items, md_name);
            };

            const tree = SuperTree.init(
                arena,
                template_name,
                template_path,
                template_html,
            ) catch |err| {
                assert(@src(), err == error.Reported);
                std.process.exit(1);
            };

            const t = Template.init(
                arena,
                template_name,
                template_path,
                tree,
                rendered_md_string,
                .template,
            ) catch oom();
            templates.append(t) catch oom();
        }
    }

    // validate that all interfaces match
    validateInterfaces(arena, templates.items, md_name);

    // current template index
    var idx: usize = templates.items.len - 1;

    // if that's not enough contact me for an enterprise license of Super
    var quota: usize = 100;
    while (quota > 0) : (quota -= 1) {
        const t = &templates.items[idx];

        const continuation = t.eval(out_writer) catch |err| switch (err) {
            error.Reported => fatalTrace(idx -| 1, templates.items, md_name),
            error.WantInterface => {
                templates.items[idx + 1].showInterface();
                fatalTrace(idx, templates.items, md_name);
            },
        };

        switch (continuation) {
            .super => |s| {
                if (idx == 0) {
                    @panic("programming error: layout acting like it has <super/> in it");
                }
                idx -= 1;

                const super_template = &templates.items[idx];
                super_template.activateBlock(
                    s.superBlock().id_value.unquote(t.html),
                    out_writer,
                ) catch {
                    @panic("TODO: error reporting");
                };
            },
            .end => {
                if (t.extends == null) break;
                idx += 1;
                assert(@src(), idx < templates.items.len);
            },
        }
    } else {
        errors.header("INFINITE LOOP",
            \\Super encountered a condition that caused an infinite loop.
            \\This should not have happened, please report this error to 
            \\the maintainers.
        );
        std.process.exit(1);
    }

    for (templates.items) |l| l.finalCheck();

    out_buf_writer.flush() catch |err| out(err) catch fatal("", .{});

    dep_writer.writeAll("\n") catch |err| dep(err) catch fatal("", .{});
    dep_buf_writer.flush() catch |err| dep(err) catch fatal("", .{});
}

fn readFile(path: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});

    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    return r.readAllAlloc(arena, 4096);
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}

const Template = struct {
    name: []const u8,
    path: []const u8,
    html: []const u8,
    print_cursor: usize = 0,
    print_end: usize,
    root: *SuperNode,
    arena: std.mem.Allocator,
    role: Role,

    // Template-wide analysis
    eval_context: std.ArrayListUnmanaged(EvalContext) = .{},
    script_vm: script.Interpreter,

    // Analysis of blocks
    extends: ?*SuperNode,
    blocks: std.StringHashMapUnmanaged(Block),
    interface: std.StringArrayHashMapUnmanaged(*SuperNode),

    // Scripting
    md: []const u8,

    const EvalContext = union(enum) {
        loop_condition: LoopCondition,
        loop_iter: LoopIter,
        default: SuperTree.SuperCursor,

        const LoopIter = struct {
            cursor: SuperTree.SuperCursor,
            loop: script.LoopContext,
        };

        const LoopCondition = struct {
            cursor_ptr: *SuperTree.SuperCursor,
            print_cursor: usize,
            items: []const script.Value,
            index: usize,
        };
    };

    const Role = enum { layout, template };

    pub fn init(
        arena: std.mem.Allocator,
        name: []const u8,
        path: []const u8,
        tree: SuperTree,
        md: []const u8,
        role: Role,
    ) !Template {
        var t: Template = .{
            .arena = arena,
            .role = role,
            .name = name,
            .path = path,
            .md = md,
            .root = tree.root,
            .html = tree.html,
            .print_end = tree.html.len,
            .extends = tree.extends,
            .blocks = tree.blocks,
            .interface = tree.interface,
            .script_vm = script.Interpreter.init(.{
                .version = "v0",
                .page = .{
                    .title = "test",
                    .authors = &.{ "loris cro", "andrew kelley" },
                    .draft = false,
                    .content = md,
                },
                .site = .{
                    .name = "my website",
                },
            }),
        };
        try t.eval_context.append(arena, .{
            .default = t.root.cursor(),
        });
        return t;
    }

    pub fn finalCheck(self: Template) void {
        assert(@src(), self.print_cursor == self.print_end);
    }

    pub fn showBlocks(self: Template) void {
        var found_first = false;
        var it = self.blocks.iterator();
        while (it.next()) |kv| {
            const id = kv.key_ptr.*;
            const tag_name = kv.value_ptr.*.node.elem.startTag().name().string(self.html);
            if (!found_first) {
                std.debug.print("\n[missing_block]\n", .{});
                std.debug.print("({s}) {s}:\n", .{ self.name, self.path });
                found_first = true;
            }
            std.debug.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                tag_name,
                id,
                tag_name,
            });
        }

        if (!found_first) {
            std.debug.print(
                \\
                \\{s} doesn't define any block! You can copy the interface 
                \\from the extended template to get started.
                \\
            , .{self.name});
        }
        std.debug.print("\n", .{});
    }

    pub fn showInterface(self: Template) void {
        var found_first = false;
        var it = self.interface.iterator();
        while (it.next()) |kv| {
            const id = kv.key_ptr.*;
            const tag_name = kv.value_ptr.*.superBlock().elem.startTag().name().string(self.html);
            if (!found_first) {
                std.debug.print("\nExtended template interface ({s}):\n", .{self.name});
                found_first = true;
            }
            std.debug.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                tag_name,
                id,
                tag_name,
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

    pub fn activateBlock(self: *Template, super_id: []const u8, writer: anytype) Reported!void {
        assert(@src(), self.extends != null);
        std.debug.assert(self.eval_context.items.len == 0);

        const block = self.blocks.getPtr(super_id).?;

        self.eval_context.append(self.arena, .{
            .default = block.node.cursor(),
        }) catch oom();

        self.print_cursor = block.node.elem.startTag().node.end();
        self.print_end = block.node.elem.endTag().?.start();

        switch (block.node.type.branching()) {
            else => assert(@src(), false),
            .none => {},
            .@"if" => {
                const scripted_attr = block.node.ifAttr();
                const attr = scripted_attr.attr;
                const value = block.node.ifValue();
                // NOTE: it's fundamental to get right string memory management
                //       semantics. In this case it doesn't matter because the
                //       output is a bool.
                const code = value.unescape(self.arena, self.html) catch oom();
                defer code.deinit(self.arena);

                if (!try self.evalIf(attr.name(), code.str)) {
                    self.print_cursor = block.node.elem.endTag().?.start();
                    // TODO: void tags :^)
                    self.eval_context.items[0].default.skipChildrenOfCurrentNode();
                }
            },
        }

        switch (block.node.type.output()) {
            .@"var" => {
                const scripted_attr = block.node.varAttr();
                const attr = scripted_attr.attr;
                const value = block.node.varValue();

                // NOTE: it's fundamental to get right string memory management
                //       semantics. In this case it doesn't matter because the
                //       output string doesn't need to survive past this scope.
                const code = value.unescape(self.arena, self.html) catch oom();
                defer code.deinit(self.arena);
                try self.evalVar(
                    attr.name(),
                    code.str,
                    writer,
                );
            },
            else => {},
        }
        // TODO: void tag dude
    }

    pub const Continuation = union(enum) {
        // A <super/> was found, contains relative id
        super: *const SuperNode,
        end,
    };

    pub fn eval(self: *Template, writer: anytype) Reported!Continuation {
        while (self.eval_context.items.len > 0) {
            const current_context = &self.eval_context.items[self.eval_context.items.len - 1];
            switch (current_context.*) {
                .default, .loop_iter => {},
                .loop_condition => |*l| {
                    self.print_cursor = l.print_cursor;
                    if (l.index < l.items.len) {
                        self.eval_context.append(self.arena, .{
                            .loop_iter = .{
                                .cursor = l.cursor_ptr.*,
                                .loop = .{
                                    .it = l.items[l.index],
                                    .idx = l.index,
                                },
                            },
                        }) catch oom();
                        l.index += 1;
                        continue;
                    } else {
                        l.cursor_ptr.skipChildrenOfCurrentNode();
                        _ = self.eval_context.pop();
                        continue;
                    }
                },
            }
            const cursor_ptr = switch (current_context.*) {
                .default => |*d| d,
                .loop_iter => |*li| &li.cursor,
                .loop_condition => unreachable,
            };
            while (cursor_ptr.next()) |node| {
                switch (node.type.role()) {
                    .root, .extend, .block, .super_block => {
                        assert(@src(), false);
                    },
                    .super => {
                        writer.writeAll(
                            self.html[self.print_cursor..node.elem.node.start()],
                        ) catch |err| return out(err);
                        self.print_cursor = node.elem.node.end();
                        return .{ .super = node };
                    },
                    .element => {},
                }

                switch (node.type.branching()) {
                    else => @panic("TODO: more branching support in eval"),
                    .none => {},
                    .loop => {
                        const start_tag = node.elem.startTag();
                        const scripted_attr = node.ifAttr();
                        const attr = scripted_attr.attr;
                        const value = node.ifValue();

                        const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                        writer.writeAll(up_to_attr) catch |err| return out(err);
                        const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                        writer.writeAll(rest_of_start_tag) catch |err| return out(err);
                        self.print_cursor = start_tag.node.end();

                        const code = value.unescape(self.arena, self.html) catch oom();
                        errdefer code.deinit(self.arena);

                        const items = try self.evalLoop(attr.name(), code.str);

                        self.eval_context.append(self.arena, .{
                            .loop_condition = .{
                                .print_cursor = self.print_cursor,
                                .cursor_ptr = cursor_ptr,
                                .items = items,
                                .index = 0,
                            },
                        }) catch oom();
                    },
                    .@"if" => {
                        const start_tag = node.elem.startTag();
                        const scripted_attr = node.ifAttr();
                        const attr = scripted_attr.attr;
                        const value = node.ifValue();

                        const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                        writer.writeAll(up_to_attr) catch |err| return out(err);
                        const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                        writer.writeAll(rest_of_start_tag) catch |err| return out(err);
                        self.print_cursor = start_tag.node.end();

                        // NOTE: it's fundamental to get right string memory management
                        //       semantics. In this case it doesn't matter because the
                        //       output is a bool.
                        const code = value.unescape(self.arena, self.html) catch oom();
                        defer code.deinit(self.arena);

                        if (!try self.evalIf(attr.name(), code.str)) {
                            self.print_cursor = node.elem.endTag().?.start();
                            // TODO: void tags :^)
                            cursor_ptr.skipChildrenOfCurrentNode();
                        }
                    },
                }

                switch (node.type.output()) {
                    .none => {},
                    .@"var" => {
                        const start_tag = node.elem.startTag();
                        const scripted_attr = node.varAttr();
                        const attr = scripted_attr.attr;
                        const value = node.varValue();

                        // NOTE: it's fundamental to get right string memory management
                        //       semantics. In this case it doesn't matter because the
                        //       output string doesn't need to survive past this scope.
                        const code = value.unescape(self.arena, self.html) catch oom();
                        defer code.deinit(self.arena);

                        try self.evalVar(attr.name(), code.str, writer);

                        const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                        writer.writeAll(up_to_attr) catch |err| return out(err);
                        writer.writeByte('>') catch |err| return out(err);
                        self.print_cursor = start_tag.node.end();
                    },
                    .ctx => @panic("TODO: implement ctx"),
                }
            }

            if (self.eval_context.popOrNull()) |ctx| {
                std.debug.assert(ctx != .loop_condition);
            }
        }

        // finalization
        writer.writeAll(
            self.html[self.print_cursor..self.print_end],
        ) catch |err| return out(err);

        self.print_cursor = self.print_end;
        return .end;
    }

    fn evalVar(
        self: *Template,
        script_attr_name: sitter.Node,
        code: []const u8,
        writer: anytype,
    ) Reported!void {

        // const diag: script.Interpreter.Diagnostics = .{};
        const result = self.script_vm.run(code, self.arena, null) catch |err| {
            // set the last arg to &diag when implementing this
            self.reportError(
                script_attr_name,
                "script_eval",
                "SCRIPT EVAL ERROR",
                \\An error was encountered while evaluating a script.
                ,
            ) catch {};

            std.debug.print("Error: {}\n", .{err});
            std.debug.print("TODO: show precise location of the error\n\n", .{});
            return error.Reported;
        };

        const string = switch (result) {
            .string => |s| s,
            else => @panic("TODO: explain that a var attr evaluated to a non-string"),
        };

        writer.writeAll(string) catch |err| return out(err);
    }

    fn evalIf(
        self: *Template,
        script_attr_name: sitter.Node,
        code: []const u8,
    ) Reported!bool {

        // const diag: script.Interpreter.Diagnostics = .{};
        const result = self.script_vm.run(code, self.arena, null) catch |err| {
            // set the last arg to &diag when implementing this
            self.reportError(
                script_attr_name,
                "script_eval",
                "SCRIPT EVAL ERROR",
                \\An error was encountered while evaluating a script.
                ,
            ) catch {};

            std.debug.print("Error: {}\n", .{err});
            std.debug.print("TODO: show precise location of the error\n\n", .{});
            return error.Reported;
        };

        switch (result) {
            .bool => |b| return b,
            else => @panic("TODO: explain that an if attr evaluated to a non-bool"),
        }
    }

    fn evalLoop(
        self: *Template,
        script_attr_name: sitter.Node,
        code: []const u8,
    ) Reported![]const script.Value {

        // const diag: script.Interpreter.Diagnostics = .{};
        const result = self.script_vm.run(code, self.arena, null) catch |err| {
            // set the last arg to &diag when implementing this
            self.reportError(
                script_attr_name,
                "script_eval",
                "SCRIPT EVAL ERROR",
                \\An error was encountered while evaluating a script.
                ,
            ) catch {};

            std.debug.print("Error: {}\n", .{err});
            std.debug.print("TODO: show precise location of the error\n\n", .{});
            return error.Reported;
        };

        switch (result) {
            .array => |a| return a,
            else => @panic("TODO: explain that a loop attr evaluated to a non-array"),
        }
    }

    fn analyzeSuper(self: *Template, elem: sitter.Element) !void {
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
    }

    fn reportError(
        self: Template,
        bad_node: sitter.Node,
        comptime error_code: []const u8,
        comptime title: []const u8,
        comptime msg: []const u8,
    ) Reported {
        return errors.report(
            self.name,
            self.path,
            bad_node,
            self.html,
            error_code,
            title,
            msg,
        );
    }

    fn diagnostic(
        self: Template,
        comptime note_line: []const u8,
        bad_node: sitter.Node,
    ) void {
        errors.diagnostic(self.name, self.path, note_line, bad_node, self.html);
    }
};

fn validateInterfaces(
    arena: std.mem.Allocator,
    templates: []const Template,
    md_name: []const u8,
) void {
    assert(@src(), templates.len > 0);
    if (templates.len == 1) return;
    var idx = templates.len - 1;
    while (idx > 0) : (idx -= 1) {
        const extended = templates[idx];
        const super = templates[idx - 1];

        var it = extended.interface.iterator();
        var blocks = super.blocks.clone(arena) catch oom();
        defer blocks.deinit(arena);
        while (it.next()) |kv| {
            const block = blocks.fetchRemove(kv.key_ptr.*) orelse {
                errors.header("MISSING BLOCK",
                    \\Missing block in super template.
                    \\All <super/> blocks from the parent template must be defined. 
                );
                super.showBlocks();

                const super_tag_name = kv.value_ptr.*.elem.startTag().name();
                const extended_block_id = kv.value_ptr.*.superBlock().id_value;
                extended.diagnostic("note: extendend template super tag:", super_tag_name);
                extended.diagnostic("note: extended block defined here:", extended_block_id.node);
                extended.showInterface();
                fatalTrace(idx, templates, md_name);
            };

            const super_block_tag = kv.value_ptr.*.superBlock().elem.startTag().name().string(extended.html);
            const block_tag = block.value.node.elem.startTag().name().string(super.html);
            if (!is(super_block_tag, block_tag)) {
                @panic("TODO: explain that two blocks don't have matching tags");
            }
        }

        var unbound_it = blocks.iterator();
        var unbound_idx: usize = 0;
        while (unbound_it.next()) |kv| : (unbound_idx += 1) {
            const bad = kv.value_ptr.*.node.elem.node.childAt(0).?.childAt(0).?;
            if (unbound_idx == 0) {
                super.reportError(bad, "unbound_block", "UNBOUND BLOCK",
                    \\Found an unbound block, i.e. the extended template doesn't declare 
                    \\a corresponding super block. Either remove it from the current
                    \\template, or add a <super/> in the extended template. 
                ) catch {};
            } else {
                super.diagnostic(
                    "error: another unbound block is here:",
                    bad,
                );
            }
        }
        if (unbound_idx > 0) fatalTrace(idx - 1, templates, md_name);

        // Should already been validated by the parser.
        const layout = templates[0];
        assert(@src(), layout.interface.count() == 0);
    }
}

fn fatalTrace(idx: usize, items: []const Template, md_name: []const u8) noreturn {
    std.debug.print("trace:\n", .{});
    var cursor = idx;
    while (cursor > 0) : (cursor -= 1) {
        std.debug.print("    template `{s}`,\n", .{
            items[cursor].name,
        });
    }

    if (items.len > 0) std.debug.print("    layout `{s}`,\n", .{items[0].name});

    fatal("    content `{s}`.\n", .{
        md_name,
    });
}

fn out(err: anyerror) Reported {
    std.debug.print(
        "error while writing to the output file: {s}\n",
        .{@errorName(err)},
    );
    return error.Reported;
}

fn dep(err: anyerror) Reported {
    std.debug.print(
        "error while writing to the output file: {s}\n",
        .{@errorName(err)},
    );
    return error.Reported;
}

test {
    _ = SuperTree;
}

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
