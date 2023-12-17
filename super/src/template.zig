const std = @import("std");
const scripty = @import("scripty");
const sitter = @import("sitter.zig");
const errors = @import("errors.zig");
const SuperTree = @import("SuperTree.zig");
const SuperNode = SuperTree.SuperNode;
const ScriptyVM = scripty.ScriptyVM;

pub fn SuperTemplate(comptime OutWriter: type) type {
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

        const EvalFrame = union(enum) {
            loop_condition: LoopCondition,
            loop_iter: LoopIter,
            default: SuperTree.SuperCursor,

            const LoopIter = struct {
                cursor: SuperTree.SuperCursor,
                loop: LoopValue,
            };

            const LoopCondition = struct {
                /// pointer to the parent print cursor
                cursor_ptr: *SuperTree.SuperCursor,
                /// start of the loop body
                print_loop_body: usize,
                // end of the loop body (ie end_tag)
                print_loop_body_end: usize,
                // previous print_end value
                print_end: usize,
                // eval result
                items: []const scripty.Value,
                // iteration progress counter
                index: usize,
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
            script_ctx: *TemplateContext,
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
            std.debug.print("({s}) activating block {s} pc={} end={}\n", .{
                self.name,
                super_id,
                self.print_cursor,
                self.print_end,
            });

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

                    if (!try self.evalIf(err_writer, script_ctx, attr.name(), code.str)) {
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
                    const string = try self.evalVar(
                        err_writer,
                        script_ctx,
                        attr.name(),
                        code.str,
                    );

                    writer.writeAll(string) catch return error.OutIO;
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
            script_ctx: *TemplateContext,
            writer: OutWriter,
            err_writer: errors.ErrWriter,
        ) errors.FatalShowOOM!Continuation {
            std.debug.print("({s}) eval \n", .{self.name});
            assert(@src(), self.eval_frame.items.len > 0);
            outer: while (self.eval_frame.items.len > 0) {
                const current_context = &self.eval_frame.items[self.eval_frame.items.len - 1];
                switch (current_context.*) {
                    .default, .loop_iter => {},
                    .loop_condition => |*l| {
                        std.debug.print("({s}) eval - creating loop_iter \n", .{self.name});
                        if (l.index < l.items.len) {
                            var cursor_copy = l.cursor_ptr.*;
                            cursor_copy.depth = 0;
                            try self.eval_frame.append(self.arena, .{
                                .loop_iter = .{
                                    .cursor = cursor_copy,
                                    .loop = .{
                                        .it = l.items[l.index],
                                        .idx = l.index,
                                        .last = l.index == l.items.len - 1,
                                        .first = l.index == 0,
                                    },
                                },
                            });
                            self.print_cursor = l.print_loop_body;
                            self.print_end = l.print_loop_body_end;
                            l.index += 1;
                            std.debug.print("({s}) eval - creating loop_iter end pc={} \n", .{
                                self.name,
                                self.print_cursor,
                            });
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
                    .loop_condition => {
                        assert(@src(), false);
                        unreachable;
                    },
                };
                while (cursor_ptr.next()) |node| {
                    std.debug.print("({s}) eval - node ({}) d={} {s} pc={}\n", .{
                        self.name,
                        @intFromPtr(node),
                        cursor_ptr.depth,
                        @tagName(node.type),
                        self.print_cursor,
                    });
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
                        .loop => {
                            std.debug.print("({s}) eval - loop 1\n", .{self.name});
                            const start_tag = node.elem.startTag();
                            const scripted_attr = node.loopAttr();
                            const attr = scripted_attr.attr;
                            const value = node.loopValue();

                            const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            self.print_cursor = start_tag.node.end();

                            std.debug.print("({s}) eval - loop 2\n", .{self.name});
                            const code = try value.unescape(self.arena, self.html);
                            errdefer code.deinit(self.arena);

                            const items = try self.evalLoop(
                                err_writer,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );
                            std.debug.print("({s}) eval - loop 3\n", .{self.name});

                            try self.eval_frame.append(self.arena, .{
                                .loop_condition = .{
                                    .print_loop_body = self.print_cursor,
                                    .print_loop_body_end = node.elem.endTag().?.start(),
                                    .print_end = self.print_end,
                                    .cursor_ptr = cursor_ptr,
                                    .items = items,
                                    .index = 0,
                                },
                            });

                            std.debug.print("({s}) eval - loop pc= {}\n", .{ self.name, self.print_cursor });
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

                            if (!try self.evalIf(err_writer, script_ctx, attr.name(), code.str)) {
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
                            const code = try value.unescape(self.arena, self.html);
                            defer code.deinit(self.arena);

                            std.debug.print("({s}) eval - var pc={} end={}\n", .{ self.name, self.print_cursor, self.print_end });

                            const string = try self.evalVar(
                                err_writer,
                                script_ctx,
                                attr.name(),
                                code.str,
                            );

                            std.debug.print("({s}) eval - var 1 \n", .{self.name});
                            const up_to_attr = self.html[self.print_cursor..attr.node.start()];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = self.html[attr.node.end()..start_tag.node.end()];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            self.print_cursor = start_tag.node.end();
                            writer.writeAll(string) catch return error.OutIO;
                        },
                        .ctx => @panic("TODO: implement ctx"),
                    }
                }

                if (self.eval_frame.popOrNull()) |ctx| {
                    std.debug.print("popping eval_frame {s}\n", .{@tagName(ctx)});
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
            script_ctx: *TemplateContext,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal![]const u8 {
            const current_eval_frame = &self.eval_frame.items[self.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |*li| &li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = loop;
            defer script_ctx.loop = old_loop;
            std.debug.print("({s}) evalVar loop: {any}\n", .{ self.name, loop });
            if (loop) |l| switch (l.it) {
                .string => std.debug.print("loop it.string = `{s}`\n", .{l.it.string}),
                else => {},
            };

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = ScriptyVM.run(
                script_ctx.externalValue(),
                code,
                self.arena,
                null,
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
            std.debug.print("({s}) evalVar end eval\n", .{self.name});

            switch (result) {
                .string => |s| return s,
                else => @panic("TODO: explain that a var attr evaluated to a non-string"),
            }
        }

        fn evalIf(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_ctx: *TemplateContext,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal!bool {
            const current_eval_frame = &self.eval_frame.items[self.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |*li| &li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = loop;
            defer script_ctx.loop = old_loop;
            std.debug.print("({s}) evalIf loop: {any}\n", .{ self.name, loop });

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = ScriptyVM.run(
                script_ctx.externalValue(),
                code,
                self.arena,
                null,
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

            switch (result) {
                .bool => |b| return b,
                else => @panic("TODO: explain that an if attr evaluated to a non-bool"),
            }
        }

        fn evalLoop(
            self: *@This(),
            err_writer: errors.ErrWriter,
            script_ctx: *TemplateContext,
            script_attr_name: sitter.Node,
            code: []const u8,
        ) errors.Fatal![]const scripty.Value {

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = ScriptyVM.run(
                script_ctx.externalValue(),
                code,
                self.arena,
                null,
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

            switch (result) {
                .array => |a| return a,
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

const LoopValue = struct {
    it: scripty.Value,
    idx: usize,
    first: bool,
    last: bool,

    pub fn externalValue(self: *LoopValue) scripty.ExternalValue {
        return .{
            .value = self,
            .dot_fn = &dot,
            .call_fn = &call,
            .value_fn = &value,
        };
    }

    fn dot(op: *anyopaque, path: []const u8, arena: std.mem.Allocator) scripty.ScriptResult {
        const self: *LoopValue = @alignCast(@ptrCast(op));
        _ = arena;
        if (std.mem.eql(u8, path, "it")) {
            return .{ .ok = self.it };
        }
        if (std.mem.eql(u8, path, "idx")) {
            return .{ .ok = .{ .int = self.idx } };
        }
        if (std.mem.eql(u8, path, "first")) {
            return .{ .ok = .{ .bool = self.first } };
        }
        if (std.mem.eql(u8, path, "last")) {
            return .{ .ok = .{ .bool = self.last } };
        }

        std.debug.panic("TODO: implement dot `{s}` for LoopValue", .{path});
    }
    fn call(op: *anyopaque, args: []const scripty.Value) scripty.ScriptResult {
        const self: *LoopValue = @alignCast(@ptrCast(op));
        _ = self;
        _ = args;
        @panic("TODO");
    }

    fn value(op: *anyopaque) scripty.ScriptResult {
        const self: *LoopValue = @alignCast(@ptrCast(op));
        _ = self;
        @panic("TODO");
    }
};

pub const TemplateContext = struct {
    ctx: scripty.ExternalValue,
    loop: ?*LoopValue = null,

    pub fn externalValue(self: *TemplateContext) scripty.ExternalValue {
        return .{
            .value = self,
            .dot_fn = &dot,
            .call_fn = &call,
            .value_fn = &value,
        };
    }

    fn dot(op: *anyopaque, path: []const u8, arena: std.mem.Allocator) scripty.ScriptResult {
        const self: *TemplateContext = @alignCast(@ptrCast(op));

        if (std.mem.eql(u8, path, "loop")) {
            const loop = self.loop orelse return .{ .err = "loop is null" };
            return .{ .ok = .{ .external = loop.externalValue() } };
        }

        return self.ctx.dot(path, arena);
    }

    fn call(op: *anyopaque, args: []const scripty.Value) scripty.ScriptResult {
        const self: *TemplateContext = @alignCast(@ptrCast(op));
        _ = self;
        _ = args;
        @panic("TODO");
    }

    fn value(op: *anyopaque) scripty.ScriptResult {
        const self: *TemplateContext = @alignCast(@ptrCast(op));
        _ = self;
        @panic("TODO");
    }
    pub fn init(context: anytype) TemplateContext {
        comptime {
            const Context = @TypeOf(context);
            const ptr_info = switch (@typeInfo(Context)) {
                .Pointer => |ptr| blk: {
                    if (ptr.is_const) {
                        @compileError("Provided context must be a mutable pointer to a struct");
                    }
                    if (ptr.size != .One) {
                        @compileError("Provided context must be a mutable pointer to a struct");
                    }
                    break :blk ptr;
                },

                else => @compileError("Provided context must be a mutable pointer to a struct"),
            };
            const info = switch (@typeInfo(ptr_info.child)) {
                .Struct => |st| st,
                else => @compileError("Provided context must be a mutable pointer to a struct"),
            };
            for (info.fields) |f| {
                if (std.mem.eql(u8, f.name, "loop")) {
                    @compileError("Provided context type cannot contain a field named `loop`");
                }
            }
        }

        return .{
            .ctx = context.externalValue(),
        };
    }
};
