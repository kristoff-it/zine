const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;

const Context = struct {
    version: []const u8,
    page: Page,
    site: Site,
};
const Page = struct {
    title: []const u8,
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

const Value = union(enum) {
    function: ScriptFunction,
    page: Page,
    site: Site,
    string: []const u8,
    bool: bool,
    int: usize,

    pub fn from(comptime T: type, payload: T) !Value {
        return switch (T) {
            []const u8 => .{ .string = payload },
            Page => .{ .page = payload },
            Site => .{ .site = payload },
            bool => .{ .bool = payload },
            ScriptFunction => .{ .function = payload },
            else => @compileError("TODO"),
        };
    }
    pub fn call(self: Value, args: []const Value) ScriptResult {
        return self.function(args);
    }

    pub fn dot(self: Value, field: []const u8) !Value {
        switch (self) {
            .function => unreachable,
            .int, .bool => @panic("TODO"),
            .string => {
                inline for (@typeInfo(StringBuiltins).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return Value.from(
                            ScriptFunction,
                            @field(StringBuiltins, struct_field.name),
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
                        );
                    }
                }

                return error.FieldNotFound;
            },
        }
    }

    const StringBuiltins = struct {
        pub fn len(args: []const Value) ScriptResult {
            if (args.len != 1) return .{ .err = "wrong number of arguments" };
            const str = switch (args[0]) {
                .string => |s| s,
                else => return .{ .err = "(haystack arg) expected string argument" },
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

pub const Interpreter = struct {
    it: Tokenizer,
    ctx: Context,
    code: []const u8,

    pub fn init(code: [:0]const u8, ctx: Context) Interpreter {
        return .{
            .it = .{ .code = code },
            .ctx = ctx,
            .code = code,
        };
    }

    const State = enum {
        start,
        main,
        call_args,
        saw_dollar,
        dot,
    };

    pub fn run(self: *Interpreter, arena: std.mem.Allocator) !Value {
        var state: State = .start;
        var call_depth: usize = 0;
        var last_was_comma = false;
        var last_was_function = false;

        var stack = std.ArrayList(Value).init(arena);
        defer stack.deinit();

        while (self.it.next()) |t| {
            switch (state) {
                .start => switch (t.tag) {
                    .dollar => state = .saw_dollar,
                    else => @panic("error"),
                },
                .main => switch (t.tag) {
                    .dot => {
                        if (last_was_function) @panic("function must be called");
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
                    else => @panic("error"),
                },
                .call_args => switch (t.tag) {
                    .dollar => {
                        last_was_comma = false;
                        state = .saw_dollar;
                    },
                    .string => {
                        last_was_comma = false;
                        // TODO: this leaks memory!
                        const src = try t.unquote(self.code, arena);
                        const v = try Value.from([]const u8, src);
                        try stack.append(v);
                    },
                    .identifier => {
                        last_was_comma = false;
                        const src = t.src(self.code);
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
                        if (call_depth == 0) {
                            state = .main;
                        } else {
                            state = .call_args;
                        }
                    },
                    else => @panic("error"),
                },
                .dot => switch (t.tag) {
                    .identifier => {
                        last_was_function = false;
                        if (stack.items.len == 0) @panic("prorgramming error");
                        const src = t.src(self.code);
                        const v = stack.pop();
                        const new_value = try v.dot(src);
                        try stack.append(new_value);
                        if (new_value == .function) {
                            // the self argument
                            try stack.append(v);
                            last_was_function = true;
                        }
                        state = .main;
                    },
                    else => @panic("error"),
                },
                .saw_dollar => switch (t.tag) {
                    .identifier => {
                        const src = t.src(self.code);
                        var found = false;
                        inline for (std.meta.fields(Context)) |field| {
                            if (std.mem.eql(u8, field.name, src)) {
                                found = true;
                                const v = try Value.from(
                                    field.type,
                                    @field(self.ctx, field.name),
                                );
                                if (v == .function) {
                                    @panic("programming error: $var is a function");
                                }
                                try stack.append(v);
                            }
                        }
                        state = .main;
                    },
                    else => @panic("error"),
                },
            }
        }

        if (stack.items.len != 1) {
            for (stack.items, 0..) |v, idx| {
                std.debug.print("[{}] - {any}\n", .{ idx, v });
            }
            @panic("error");
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

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .string = "v0" };
    try std.testing.expectEqualDeep(ex, result);
}

test "struct" {
    const code = "$page";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .page = test_ctx.page };
    try std.testing.expectEqualDeep(ex, result);
}

test "dot" {
    const code = "$page.content";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .string = test_ctx.page.content };
    try std.testing.expectEqualDeep(ex, result);
}

test "string.startsWith" {
    const code = "$page.title.startsWith('Home')";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .bool = true };
    try std.testing.expectEqualDeep(ex, result);
}
test "string.len" {
    const code = "$page.title.len()";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .int = 4 };
    try std.testing.expectEqualDeep(ex, result);
}

test "should not be able to use a fn as a value" {
    const code = "$page.title.startsWith($page.title.startsWith, true)";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i = Interpreter.init(code, test_ctx);
    const result = try i.run(arena.allocator());

    const ex: Value = .{ .bool = true };
    try std.testing.expectEqualDeep(ex, result);
}
