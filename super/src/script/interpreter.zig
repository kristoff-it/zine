const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;

const Context = struct {
    version: []const u8,
    page: Page,
    site: Site,
};

// $loop, available when in a loop
pub const LoopContext = struct {
    it: Value,
    idx: usize,
};

const Page = struct {
    title: []const u8,
    authors: []const []const u8,
    draft: bool,
    content: []const u8,
};
const Site = struct { name: []const u8 };

const ScriptFunction = *const fn ([]const Value) ScriptResult;
const ScriptResult = union(enum) {
    ok: Value,
    err: []const u8,

    pub fn unwrap(self: ScriptResult) Value {
        switch (self) {
            .ok => |v| return v,
            .err => |e| @panic(e),
        }
    }
};

pub const Value = union(enum) {
    function: ScriptFunction,
    page: Page,
    site: Site,
    string: []const u8,
    bool: bool,
    int: usize,
    array: []const Value,

    pub fn from(
        comptime T: type,
        payload: T,
        arena: ?std.mem.Allocator,
    ) !Value {
        return switch (T) {
            []const u8 => .{ .string = payload },
            Page => .{ .page = payload },
            Site => .{ .site = payload },
            bool => .{ .bool = payload },
            ScriptFunction => .{ .function = payload },
            else => {
                const info: std.builtin.Type = @typeInfo(T);
                switch (info) {
                    .Pointer => |p| {
                        if (p.size != .Slice) @compileError("TODO");
                        const array = try arena.?.alloc(Value, payload.len);
                        for (array, payload) |*x, px| x.* = try from(p.child, px, arena);
                        return .{ .array = array };
                    },

                    else => @compileError("TODO"),
                }
            },
        };
    }
    pub fn call(self: Value, args: []const Value) ScriptResult {
        return self.function(args);
    }

    pub fn dot(self: Value, field: []const u8, arena: ?std.mem.Allocator) !Value {
        switch (self) {
            .function => unreachable,
            .int => @panic("TODO"),
            .array => {
                inline for (@typeInfo(ArrayBuiltins).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return Value.from(
                            ScriptFunction,
                            @field(ArrayBuiltins, struct_field.name),
                            arena,
                        );
                    }
                }

                return error.NotFound;
            },
            .bool => {
                inline for (@typeInfo(BoolBuiltins).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return Value.from(
                            ScriptFunction,
                            @field(BoolBuiltins, struct_field.name),
                            arena,
                        );
                    }
                }

                return error.NotFound;
            },
            .string => {
                inline for (@typeInfo(StringBuiltins).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return Value.from(
                            ScriptFunction,
                            @field(StringBuiltins, struct_field.name),
                            arena,
                        );
                    }
                }

                return error.NotFound;
            },
            inline .page, .site => |struct_value| {
                inline for (std.meta.fields(@TypeOf(struct_value))) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return Value.from(
                            struct_field.type,
                            @field(struct_value, struct_field.name),
                            arena,
                        );
                    }
                }

                return error.FieldNotFound;
            },
        }
    }

    const ArrayBuiltins = struct {
        pub fn len(args: []const Value) ScriptResult {
            if (args.len != 1) return .{ .err = "wrong number of arguments" };
            const array = switch (args[0]) {
                .array => |a| a,
                else => return .{ .err = "expected array argument" },
            };
            // TODO: arg being not a bool is actually a programming error
            return .{ .ok = .{ .int = array.len } };
        }
    };
    const BoolBuiltins = struct {
        pub fn not(args: []const Value) ScriptResult {
            if (args.len != 1) return .{ .err = "wrong number of arguments" };
            const b = switch (args[0]) {
                .bool => |b| b,
                else => return .{ .err = "expected bool argument" },
            };
            // TODO: arg being not a bool is actually a programming error
            return .{ .ok = .{ .bool = !b } };
        }
    };
    const StringBuiltins = struct {
        pub fn len(args: []const Value) ScriptResult {
            if (args.len != 1) return .{ .err = "wrong number of arguments" };
            const str = switch (args[0]) {
                .string => |s| s,
                else => return .{ .err = "expected string argument" },
            };
            return .{ .ok = .{ .int = str.len } };
        }
        pub fn startsWith(args: []const Value) ScriptResult {
            if (args.len != 2) return .{ .err = "wrong number of arguments" };
            const haystack = switch (args[0]) {
                .string => |s| s,
                else => return .{ .err = "(haystack arg) expected string argument" },
            };
            const needle = switch (args[1]) {
                .string => |s| s,
                else => return .{ .err = "(needle arg) expected string argument" },
            };

            return .{
                .ok = .{ .bool = std.mem.startsWith(u8, haystack, needle) },
            };
        }
    };
};

pub const Diagnostics = struct {
    loc: Token.Loc,
};

pub const Interpreter = struct {
    ctx: Context,

    pub fn init(ctx: Context) Interpreter {
        return .{ .ctx = ctx };
    }

    const State = enum {
        start,
        main,
        call_args,
        saw_dollar,
        dot,
    };

    pub fn run(
        self: *Interpreter,
        code: []const u8,
        arena: std.mem.Allocator,
        diag: ?*Diagnostics,
    ) !Value {
        if (diag != null) @panic("TODO: implement diagnostics");

        var it: Tokenizer = .{};
        var state: State = .start;
        var call_depth: usize = 0;
        var last_was_comma = false;
        var last_was_function = false;

        var stack = std.ArrayList(Value).init(arena);
        defer stack.deinit();

        while (it.next(code)) |t| {
            switch (state) {
                .start => switch (t.tag) {
                    .dollar => state = .saw_dollar,
                    else => return error.Eval,
                },
                .main => switch (t.tag) {
                    .dot => {
                        if (last_was_function) {
                            return error.FunctionMustBeCalled;
                        }
                        state = .dot;
                    },
                    .lparen => {
                        if (!last_was_function) @panic("calling a non-function");
                        if (stack.items.len < 2) return error.BadLParen;
                        if (stack.items[stack.items.len - 2] != .function) {
                            @panic("programming error: expected function");
                        }
                        state = .call_args;
                        call_depth += 1;
                    },
                    .rparen => {
                        if (call_depth == 0) {
                            @panic("too many rparen");
                        }

                        try apply(&stack);

                        call_depth -= 1;
                        last_was_comma = false;
                        last_was_function = false;
                        if (call_depth == 0) {
                            state = .main;
                        } else {
                            state = .call_args;
                        }
                    },
                    .comma => {
                        if (call_depth == 0) @panic("comma not in fn call");
                        if (last_was_comma) {
                            @panic("two commas");
                        }
                        last_was_comma = true;
                        state = .call_args;
                    },
                    else => return error.Eval,
                },
                .call_args => switch (t.tag) {
                    .dollar => {
                        last_was_comma = false;
                        state = .saw_dollar;
                    },
                    .string => {
                        last_was_comma = false;
                        // TODO: this leaks memory!
                        const src = try t.unquote(code, arena);
                        const v = try Value.from([]const u8, src, arena);
                        try stack.append(v);
                    },
                    .identifier => {
                        last_was_comma = false;
                        const src = t.src(code);
                        if (std.mem.eql(u8, "true", src)) {
                            const v = .{ .bool = true };
                            try stack.append(v);
                        } else if (std.mem.eql(u8, "false", src)) {
                            const v = .{ .bool = false };
                            try stack.append(v);
                        } else {
                            @panic("not a bool");
                        }
                    },
                    .rparen => {
                        if (call_depth == 0) {
                            @panic("too many rparen");
                        }

                        try apply(&stack);

                        call_depth -= 1;
                        last_was_comma = false;
                        last_was_function = false;
                        if (call_depth == 0) {
                            state = .main;
                        } else {
                            state = .call_args;
                        }
                    },
                    else => return error.Eval,
                },
                .dot => switch (t.tag) {
                    .identifier => {
                        last_was_function = false;
                        if (stack.items.len == 0) @panic("prorgramming error");
                        const src = t.src(code);
                        const v = stack.pop();
                        const new_value = try v.dot(src, arena);
                        try stack.append(new_value);
                        if (new_value == .function) {
                            // the self argument
                            try stack.append(v);
                            last_was_function = true;
                        }
                        state = .main;
                    },
                    else => return error.Eval,
                },
                .saw_dollar => switch (t.tag) {
                    .identifier => {
                        const src = t.src(code);
                        var found = false;
                        inline for (std.meta.fields(Context)) |field| {
                            if (std.mem.eql(u8, field.name, src)) {
                                found = true;
                                const v = try Value.from(
                                    field.type,
                                    @field(self.ctx, field.name),
                                    null,
                                );
                                if (v == .function) {
                                    @panic("programming error: $var is a function");
                                }
                                try stack.append(v);
                            }
                        }
                        state = .main;
                    },
                    else => return error.Eval,
                },
            }
        }

        if (last_was_function) {
            return error.FunctionMustBeCalled;
        }
        if (stack.items.len != 1) {
            for (stack.items, 0..) |v, idx| {
                std.debug.print("[{}] - {any}\n", .{ idx, v });
            }
            return error.Eval;
        }
        return stack.pop();
    }

    fn apply(stack: *std.ArrayList(Value)) !void {
        const original_len = stack.items.len;
        var cur = original_len - 1;
        while (cur < stack.items.len) : (cur -%= 1) {
            const v = stack.items[cur];
            if (v == .function) {
                const result = v.call(stack.items[cur + 1 ..]).unwrap();
                stack.shrinkRetainingCapacity(cur);
                try stack.append(result);
                break;
            }
        } else {
            @panic("no functions?");
        }
    }
};

const test_ctx: Context = .{
    .version = "v0",
    .page = .{
        .title = "Home",
        .authors = &.{ "loris cro", "andrew kelley" },
        .draft = false,
        .content = "<p>Welcome!</p>",
    },
    .site = .{
        .name = "Loris Cro's Personal Blog",
    },
};

test "basic" {
    const code = "$version";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .string = "v0" };
    try std.testing.expectEqualDeep(ex, result);
}

test "struct" {
    const code = "$page";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .page = test_ctx.page };
    try std.testing.expectEqualDeep(ex, result);
}

test "dot" {
    const code = "$page.content";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .string = test_ctx.page.content };
    try std.testing.expectEqualDeep(ex, result);
}

test "string.startsWith" {
    const code = "$page.title.startsWith('Home')";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .bool = true };
    try std.testing.expectEqualDeep(ex, result);
}
test "string.len" {
    const code = "$page.title.len()";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .int = 4 };
    try std.testing.expectEqualDeep(ex, result);
}

test "should not be able to use a fn as a value" {
    const code = "$page.title.startsWith($page.title.startsWith, true)";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = i.run(code, arena.allocator(), null);

    try std.testing.expectError(error.FunctionMustBeCalled, result);
}

test "array" {
    const code = "$page.authors";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(test_ctx);
    const result = try i.run(code, arena.allocator(), null);

    const ex: Value = .{ .array = &.{
        .{ .string = "loris cro" },
        .{ .string = "andrew kelley" },
    } };
    try std.testing.expectEqualDeep(ex, result);
}
