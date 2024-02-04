const std = @import("std");
const scripty = @import("scripty");
const sitter = @import("sitter.zig");
const errors = @import("errors.zig");
const SuperTree = @import("SuperTree.zig");
const SuperNode = SuperTree.SuperNode;

const log = std.log.scoped(.supertemplate);

pub fn SuperTemplate(comptime Context: type, comptime Value: type, comptime OutWriter: type) type {
    return struct {
        name: []const u8,
        path: []const u8,
        html: []const u8,
        print_cursor: usize = 0,
        print_end: usize,
        root: *SuperNode,
        arena: std.mem.Allocator,
        role: Role,

        // Template-wide analysis
        eval_frame: std.ArrayListUnmanaged(EvalFrame) = .{},

        // Analysis of blocks
        extends: ?*SuperNode,
        blocks: std.StringHashMapUnmanaged(*const SuperNode),
        interface: std.StringArrayHashMapUnmanaged(*const SuperNode),

        const ScriptyVM = scripty.ScriptyVM(Context, Value);
        const EvalFrame = union(enum) {
            if_condition: IfCondition,
            loop_condition: LoopCondition,
            loop_iter: LoopIter,
            default: SuperTree.SuperCursor,

            const LoopIter = struct {
                cursor: SuperTree.SuperCursor,
                loop: Value.IterElement,
            };

            const LoopCondition = struct {
                /// if set, it's an inline-loop
                /// (ie container element must be duplicated)
                inloop: ?*const SuperTree.SuperNode = null,
                /// pointer to the parent print cursor
                cursor_ptr: *SuperTree.SuperCursor,
                /// start of the loop body
                print_loop_body: usize,
                // end of the loop body (ie end_tag)
                print_loop_body_end: usize,
                // previous print_end value
                print_end: usize,
                // eval result
                iter: Value.Iterator,
                // iteration progress counter
                index: usize,
            };

            const IfCondition = struct {
                /// cursor scoped to the if body
                cursor: SuperTree.SuperCursor,
                // eval result
                if_result: ?Value,
            };
        };

        const Role = enum { layout, template };

        pub fn init(
            arena: std.mem.Allocator,
            tree: SuperTree,
            role: Role,
        ) !@This() {
            var t: @This() = .{
                .arena = arena,
                .role = role,
                .name = tree.template_name,
                .path = tree.template_path,
                .root = tree.root,
                .html = tree.html,
                .print_end = tree.html.len,
                .extends = tree.extends,
                .blocks = tree.blocks,
                .interface = tree.interface,
            };
            try t.eval_frame.append(arena, .{
                .default = t.root.cursor(),
            });
            return t;
        }

        pub fn finalCheck(self: @This()) void {
            assert(@src(), self.print_cursor == self.print_end);
        }

        pub fn showBlocks(self: @This(), err_writer: errors.ErrWriter) error{ErrIO}!void {
            var found_first = false;
            var it = self.blocks.iterator();
            while (it.next()) |kv| {
                const id = kv.key_ptr.*;
                const tag_name = kv.value_ptr.*.elem.startTag().name().string(self.html);
                if (!found_first) {
                    err_writer.print("\n[missing_block]\n", .{}) catch return error.ErrIO;
                    err_writer.print("({s}) {s}:\n", .{ self.name, self.path }) catch return error.ErrIO;
                    found_first = true;
                }
                err_writer.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                    tag_name,
                    id,
                    tag_name,
                }) catch return error.ErrIO;
            }

            if (!found_first) {
                err_writer.print(
                    \\
                    \\{s} doesn't define any block! You can copy the interface 
                    \\from the extended template to get started.
                    \\
                , .{self.name}) catch return error.ErrIO;
            }
            err_writer.print("\n", .{}) catch return error.ErrIO;
        }

        pub fn showInterface(self: @This(), err_writer: errors.ErrWriter) error{ErrIO}!void {
            var found_first = false;
            var it = self.interface.iterator();
            while (it.next()) |kv| {
                const id = kv.key_ptr.*;
                const tag_name = kv.value_ptr.*.superBlock().elem.startTag().name().string(self.html);
                if (!found_first) {
                    err_writer.print("\nExtended template interface ({s}):\n", .{self.name}) catch return error.ErrIO;
                    found_first = true;
                }
                err_writer.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                    tag_name,
                    id,
                    tag_name,
                }) catch return error.ErrIO;
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

        pub fn activateBlock(
            self: *@This(),
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            super_id: []const u8,
            writer: OutWriter,
            err_writer: errors.ErrWriter,
        ) errors.FatalOOM!void {
            assert(@src(), self.extends != null);
            assert(@src(), self.eval_frame.items.len == 0);

            const block = self.blocks.get(super_id).?;

            try self.eval_frame.append(self.arena, .{
                .default = block.*.cursor(),
            });

            self.print_cursor = block.elem.startTag().node.end();
            self.print_end = block.elem.endTag().?.start();

            switch (block.type.branching()) {
                else => assert(@src(), false),
                .none => {},
                .@"if" => {
                    const scripted_attr = block.ifAttr();
                    const attr = scripted_attr.attr;
                    const value = block.ifValue();
                    // NOTE: it's fundamental to get right string memory management
                    //       semantics. In this case it doesn't matter because the
                    //       output is a bool.
                    const code = try value.unescape(self.arena, self.html);
                    defer code.deinit(self.arena);

                    const result = try self.evalIf(
                        err_writer,
                        script_vm,
                        script_ctx,
                        attr.name(),
                        code.str,
                    );
                    if (!result.bool) {
                        self.print_cursor = block.elem.endTag().?.start();
                        // TODO: void tags :^)
                        self.eval_frame.items[0].default.skipChildrenOfCurrentNode();
                    }
                },
            }

            switch (block.type.output()) {
                .@"var" => {
                    const scripted_attr = block.varAttr();
                    const attr = scripted_attr.attr;
                    const value = block.varValue();

                    // NOTE: it's fundamental to get right string memory management
                    //       semantics. In this case it doesn't matter because the
                    //       output string doesn't need to survive past this scope.
                    const code = try value.unescape(self.arena, self.html);
                    defer code.deinit(self.arena);
                    const var_value = try self.evalVar(
                        err_writer,
                        script_vm,
                        script_ctx,
                        attr.name(),
                        code.str,
                    );

                    switch (var_value) {
                        .string => |s| writer.writeAll(s) catch return error.OutIO,
                        .int => |i| writer.print("{}", .{i}) catch return error.OutIO,
                        else => {
                            @panic("TODO: explain that a var attr evaluated to a non-string");
                        },
                    }
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

        pub fn eval(
            self: *@This(),
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            writer: OutWriter,
            err_writer: errors.ErrWriter,
        ) errors.FatalShowOOM!Continuation {
            assert(@src(), self.eval_frame.items.len > 0);
            outer: while (self.eval_frame.items.len > 0) {
                const current_context = &self.eval_frame.items[self.eval_frame.items.len - 1];
                switch (current_context.*) {
                    .default, .loop_iter, .if_condition => {},
                    .loop_condition => |*l| {
                        if (l.iter.next(self.arena)) |n| {
                            var cursor_copy = l.cursor_ptr.*;
                            cursor_copy.depth = 0;
                            try self.eval_frame.append(self.arena, .{
                                .loop_iter = .{
                                    .cursor = cursor_copy,
                                    .loop = n.iter_elem,
                                },
                            });
                            self.print_cursor = l.print_loop_body;
                            self.print_end = l.print_loop_body_end;
                            l.index += 1;
                            if (l.inloop) |node| {
                                // print container element start tag
                                const start_tag = node.elem.startTag();
                                const scripted_attr = node.loopAttr();
                                const attr = scripted_attr.attr;

                                const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                                writer.writeAll(up_to_attr) catch return error.OutIO;
                                const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                                writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                                self.print_cursor = start_tag.node.end();
                            }
                            continue;
                        } else {
                            self.print_cursor = l.print_loop_body_end;
                            self.print_end = l.print_end;
                            l.cursor_ptr.skipChildrenOfCurrentNode();
                            _ = self.eval_frame.pop();
                            continue;
                        }
                    },
                }
                const cursor_ptr = switch (current_context.*) {
                    .default => |*d| d,
                    .loop_iter => |*li| &li.cursor,
                    .if_condition => |*ic| &ic.cursor,
                    .loop_condition => {
                        assert(@src(), false);
                        unreachable;
                    },
                };
                while (cursor_ptr.next()) |node| {
                    switch (node.type.role()) {
                        .root, .extend, .block, .super_block => {
                            assert(@src(), false);
                        },
                        .super => {
                            writer.writeAll(
                                self.html[self.print_cursor..node.elem.node.start()],
                            ) catch return error.OutIO;
                            self.print_cursor = node.elem.node.end();
                            return .{ .super = node };
                        },
                        .element => {},
                    }

                    switch (node.type.branching()) {
                        else => @panic("TODO: more branching support in eval"),
                        .none => {},
                        .inloop => {
                            const start_tag = node.elem.startTag();
                            const scripted_attr = node.loopAttr();
                            const attr = scripted_attr.attr;
                            const value = node.loopValue();

                            const elem_start = start_tag.node.start();
                            const up_to_elem = self.html[self.print_cursor..elem_start];
                            self.print_cursor = elem_start;
                            writer.writeAll(up_to_elem) catch return error.OutIO;

                            const code = try value.unescape(self.arena, self.html);
                            errdefer code.deinit(self.arena);

                            const iter = try self.evalLoop(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );

                            try self.eval_frame.append(self.arena, .{
                                .loop_condition = .{
                                    .inloop = node,
                                    .print_loop_body = self.print_cursor,
                                    .print_loop_body_end = node.elem.endTag().?.end(),
                                    .print_end = self.print_end,
                                    .cursor_ptr = cursor_ptr,
                                    .iter = iter,
                                    .index = 0,
                                },
                            });

                            continue :outer;
                        },
                        .loop => {
                            const start_tag = node.elem.startTag();
                            const scripted_attr = node.loopAttr();
                            const attr = scripted_attr.attr;
                            const value = node.loopValue();

                            const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            self.print_cursor = start_tag.node.end();

                            const code = try value.unescape(self.arena, self.html);
                            errdefer code.deinit(self.arena);

                            const iter = try self.evalLoop(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );

                            try self.eval_frame.append(self.arena, .{
                                .loop_condition = .{
                                    .print_loop_body = self.print_cursor,
                                    .print_loop_body_end = node.elem.endTag().?.start(),
                                    .print_end = self.print_end,
                                    .cursor_ptr = cursor_ptr,
                                    .iter = iter,
                                    .index = 0,
                                },
                            });

                            continue :outer;
                        },
                        .@"if" => {
                            const start_tag = node.elem.startTag();
                            const scripted_attr = node.ifAttr();
                            const attr = scripted_attr.attr;
                            const value = node.ifValue();

                            const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            self.print_cursor = start_tag.node.end();

                            // NOTE: it's fundamental to get right string memory management
                            //       semantics. In this case it doesn't matter because the
                            //       output is a bool.
                            const code = try value.unescape(self.arena, self.html);
                            defer code.deinit(self.arena);

                            const result = try self.evalIf(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );

                            switch (result) {
                                else => assert(@src(), false),
                                .err => |err| {
                                    std.debug.panic("TODO: explain the script returned an error: {s}\n", .{err});
                                },
                                .bool => |b| {
                                    if (!b) {
                                        self.print_cursor = node.elem.endTag().?.start();
                                        // TODO: void tags :^)
                                        cursor_ptr.skipChildrenOfCurrentNode();
                                    }
                                },
                                .optional => |opt| {
                                    if (opt) |o| {
                                        // if resulted in a non-boolean value
                                        var new_frame: EvalFrame = .{
                                            .if_condition = .{
                                                .cursor = cursor_ptr.*,
                                                .if_result = Value.from(self.arena, o),
                                            },
                                        };

                                        new_frame.if_condition.cursor.depth = 0;
                                        try self.eval_frame.append(
                                            self.arena,
                                            new_frame,
                                        );

                                        cursor_ptr.skipChildrenOfCurrentNode();
                                        continue :outer;
                                    } else {
                                        self.print_cursor = node.elem.endTag().?.start();
                                        // TODO: void tags :^)
                                        cursor_ptr.skipChildrenOfCurrentNode();
                                    }
                                },
                            }
                        },
                    }

                    for (node.scripted_attrs) |scripted_attr| {
                        const attr = scripted_attr.attr;
                        const value = attr.value().?;
                        const code = try value.unescape(self.arena, self.html);
                        defer code.deinit(self.arena);

                        const attr_value = try self.evalAttr(
                            err_writer,
                            script_vm,
                            script_ctx,
                            attr.name(),
                            code.str,
                        );

                        const attr_string = switch (attr_value) {
                            .err => |err| std.debug.panic("err: {s}\n", .{err}),
                            .string => |s| s,
                            else => @panic("TODO: explain an attr script returned a non-string value."),
                        };

                        const up_to_value = self.html[self.print_cursor .. value.node.start() + 1];
                        writer.writeAll(up_to_value) catch return error.OutIO;
                        writer.writeAll(attr_string) catch return error.OutIO;
                        self.print_cursor = value.node.end() - 1;
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
                            const code = try value.unescape(self.arena, self.html);
                            defer code.deinit(self.arena);

                            const var_value = try self.evalVar(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );

                            const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            self.print_cursor = start_tag.node.end();

                            switch (var_value) {
                                .err => |e| std.debug.panic("err: {s}", .{e}),
                                .string => |s| writer.writeAll(s) catch return error.OutIO,
                                .int => |i| writer.print("{}", .{i}) catch return error.OutIO,
                                else => {
                                    std.debug.print("got: {s}\n", .{@tagName(var_value)});
                                    @panic("TODO: explain that a var attr evaluated to a non-string");
                                },
                            }
                        },
                        .ctx => @panic("TODO: implement ctx"),
                    }
                }

                if (self.eval_frame.popOrNull()) |ctx| {
                    if (ctx == .if_condition) continue;
                    // finalization
                    assert(@src(), ctx != .loop_condition);
                    writer.writeAll(
                        self.html[self.print_cursor..self.print_end],
                    ) catch return error.OutIO;
                    self.print_cursor = self.print_end;
                }
            }

            assert(@src(), self.print_cursor == self.print_end);
            return .end;
        }

        fn evalVar(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal!Value {
            const current_eval_frame = &self.eval_frame.items[self.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if (loop) |l| switch (l.it) {
            //     .string => std.debug.print("loop it.string = `{s}`\n", .{l.it.string}),
            // };

            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };
            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                self.arena,
                script_ctx,
                code,
                .{},
            ) catch |err| {
                // set the last arg to &diag when implementing this
                self.reportError(
                    err_writer,
                    script_attr_name,
                    "script_eval",
                    "SCRIPT EVAL ERROR",
                    \\An error was encountered while evaluating a script.
                    ,
                ) catch {};

                std.debug.print("Error: {}\n", .{err});
                std.debug.print("TODO: show precise location of the error\n\n", .{});
                return error.Fatal;
            };

            return result.value;
        }
        fn evalAttr(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal!Value {
            const current_eval_frame = &self.eval_frame.items[self.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if (loop) |l| switch (l.it) {
            //     .string => std.debug.print("loop it.string = `{s}`\n", .{l.it.string}),
            // };

            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };
            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                self.arena,
                script_ctx,
                code,
                .{},
            ) catch |err| {
                // set the last arg to &diag when implementing this
                self.reportError(
                    err_writer,
                    script_attr_name,
                    "script_eval",
                    "SCRIPT EVAL ERROR",
                    \\An error was encountered while evaluating a script.
                    ,
                ) catch {};

                std.debug.print("Error: {}\n", .{err});
                std.debug.print("TODO: show precise location of the error\n\n", .{});
                return error.Fatal;
            };

            return result.value;
        }

        fn evalIf(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal!Value {
            const current_eval_frame = &self.eval_frame.items[self.eval_frame.items.len - 1];
            // loop
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };

            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;
            // std.debug.print("({s}) evalIf if: {any}\n", .{ self.name, script_ctx });
            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                self.arena,
                script_ctx,
                code,
                .{},
            ) catch |err| {
                // set the last arg to &diag when implementing this
                self.reportError(
                    err_writer,
                    script_attr_name,
                    "script_eval",
                    "SCRIPT EVAL ERROR",
                    \\An error was encountered while evaluating a script.
                    ,
                ) catch {};

                std.debug.print("Error: {}\n", .{err});
                if (true) @panic("TODO: show precise location of the error\n\n");

                return error.Fatal;
            };

            return result.value;
        }

        fn evalLoop(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal!Value.Iterator {

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                self.arena,
                script_ctx,
                code,
                .{},
            ) catch |err| {
                // set the last arg to &diag when implementing this
                self.reportError(
                    err_writer,
                    script_attr_name,
                    "script_eval",
                    "SCRIPT EVAL ERROR",
                    \\An error was encountered while evaluating a script.
                    ,
                ) catch {};

                std.debug.print("Error: {}\n", .{err});
                std.debug.print("TODO: show precise location of the error\n\n", .{});
                return error.Fatal;
            };

            switch (result.value) {
                .iterator => |i| return i,
                else => @panic("TODO: explain that a loop attr evaluated to a non-array"),
            }
        }

        pub fn reportError(
            self: @This(),
            err_writer: errors.ErrWriter,
            bad_node: sitter.Node,
            comptime error_code: []const u8,
            comptime title: []const u8,
            comptime msg: []const u8,
        ) errors.Fatal {
            return errors.report(
                err_writer,
                self.name,
                self.path,
                bad_node,
                self.html,
                error_code,
                title,
                msg,
            );
        }

        pub fn diagnostic(
            self: @This(),
            err_writer: errors.ErrWriter,
            comptime note_line: []const u8,
            bad_node: sitter.Node,
        ) errors.Fatal!void {
            try errors.diagnostic(
                err_writer,
                self.name,
                self.path,
                note_line,
                bad_node,
                self.html,
            );
        }
    };
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

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}
