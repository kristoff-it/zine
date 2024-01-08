const std = @import("std");
const types = @import("types.zig");
const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");

const log = std.log.scoped(.scripty_vm);

pub const Diagnostics = struct {
    loc: Tokenizer.Token.Loc,
};

pub const RunError = error{ OutOfMemory, Quota };

pub fn ScriptyVM(comptime Context: type, comptime Value: type) type {
    if (!@hasDecl(Value, "builtinsFor")) {
        @compileLog("Value type must specify builtinsFor");
    }

    return struct {
        parser: Parser = .{},
        stack: std.MultiArrayList(Result) = .{},

        pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
            self.stack.deinit(gpa);
        }

        pub const Result = struct {
            value: Value,
            loc: Tokenizer.Token.Loc,
        };

        pub const RunOptions = struct {
            diag: ?*Diagnostics = null,
            quota: usize = 0,
        };

        pub fn run(
            self: *@This(),
            gpa: std.mem.Allocator,
            ctx: *Context,
            code: []const u8,
            opts: RunOptions,
        ) RunError!Result {
            // TODO: temp hack
            self.parser = .{};
            var quota = opts.quota;

            // On error make the vm usable again.
            errdefer |err| switch (@as(RunError, err)) {
                error.Quota => {},
                else => self.stack.shrinkRetainingCapacity(0),
            };

            if (opts.diag != null) @panic("TODO: implement diagnostics");
            if (quota == 1) return error.Quota;

            while (self.parser.next(code)) |node| : ({
                if (quota == 1) return error.Quota;
                if (quota > 1) quota -= 1;
            }) {
                switch (node.tag) {
                    .syntax_error => {
                        self.stack.shrinkRetainingCapacity(0);
                        return .{
                            .loc = node.loc,
                            .value = .{ .err = "syntax error" },
                        };
                    },
                    .string => try self.stack.append(gpa, .{
                        .value = Value.fromStringLiteral(try node.loc.unquote(gpa, code)),
                        .loc = node.loc,
                    }),
                    .number => try self.stack.append(gpa, .{
                        .value = Value.fromNumberLiteral(node.loc.src(code)),
                        .loc = node.loc,
                    }),
                    .true => try self.stack.append(gpa, .{
                        .value = Value.fromBooleanLiteral(true),
                        .loc = node.loc,
                    }),
                    .false => try self.stack.append(gpa, .{
                        .value = Value.fromBooleanLiteral(false),
                        .loc = node.loc,
                    }),
                    .call => {
                        assert(@src(), code[node.loc.end] == '(');
                        try self.stack.append(gpa, .{
                            .loc = node.loc,
                            .value = undefined,
                        });
                    },

                    .path => {
                        // log.err("(vm) {any} `{s}`", .{
                        //     node.loc,
                        //     code[node.loc.start..node.loc.end],
                        // });
                        const slice = self.stack.slice();
                        const stack_locs = slice.items(.loc);
                        const stack_values = slice.items(.value);
                        const global = code[node.loc.start] == '$';
                        const start = node.loc.start + @intFromBool(global);
                        const end = node.loc.end;
                        const path = code[start..end];

                        const old_value = if (global)
                            Value.from(gpa, ctx)
                        else
                            stack_values[stack_values.len - 1];

                        const new_value = try dotPath(gpa, old_value, path);
                        if (new_value == .err) {
                            self.stack.shrinkRetainingCapacity(0);
                            return .{ .loc = node.loc, .value = new_value };
                        }
                        if (global) {
                            try self.stack.append(gpa, .{
                                .loc = node.loc,
                                .value = new_value,
                            });
                        } else {
                            stack_locs[stack_locs.len - 1] = node.loc;
                            stack_values[stack_values.len - 1] = new_value;
                        }
                    },
                    .apply => {
                        const slice = self.stack.slice();
                        const stack_locs = slice.items(.loc);
                        const stack_values = slice.items(.value);

                        var call_idx = stack_locs.len - 1;
                        const call_loc = while (true) : (call_idx -= 1) {
                            const current = stack_locs[call_idx];
                            if (code[current.end] == '(') {
                                break current;
                            }
                        };

                        const fn_name = code[call_loc.start..call_loc.end];
                        const args = stack_values[call_idx + 1 ..];
                        assert(@src(), call_idx > 0);
                        call_idx -= 1;
                        const old_value = stack_values[call_idx];
                        const new_value = try old_value.call(gpa, fn_name, args);

                        if (new_value == .err) {
                            self.stack.shrinkRetainingCapacity(0);
                            return .{ .loc = node.loc, .value = new_value };
                        }

                        // functor becomes the new result
                        stack_values[call_idx] = new_value;

                        // Extend the loc to encompass the entire expression
                        // (which also disables the value as a call path)
                        stack_locs[call_idx].end = node.loc.end;

                        // Remove arguments and fn_name
                        self.stack.shrinkRetainingCapacity(call_idx + 1);
                    },
                }
            }

            assert(@src(), self.stack.items(.loc).len == 1);
            const result = self.stack.pop();
            assert(@src(), result.value != .err);
            return result;
        }

        fn dotPath(gpa: std.mem.Allocator, value: Value, path: []const u8) !Value {
            var it = std.mem.tokenizeScalar(u8, path, '.');
            var val = value;
            while (it.next()) |component| {
                val = try val.dot(gpa, component);
                if (val == .err) break;
            }

            return val;
        }
    };
}

pub const TestValue = union(Tag) {
    global: *TestContext,
    site: *TestContext.Site,
    page: *TestContext.Page,
    string: types.String,
    bool: bool,
    int: usize,
    float: f64,
    err: []const u8, // error message
    nil,

    pub const Tag = enum {
        global,
        site,
        page,
        string,
        bool,
        int,
        float,
        err,
        nil,
    };
    pub fn dot(
        self: TestValue,
        gpa: std.mem.Allocator,
        path: []const u8,
    ) error{OutOfMemory}!TestValue {
        switch (self) {
            .string,
            .bool,
            .int,
            .float,
            .err,
            .nil,
            => return .{ .err = "primitive value" },
            inline else => |v| return v.dot(gpa, path),
        }
    }

    pub const call = types.defaultCall(TestValue);

    pub fn builtinsFor(comptime tag: Tag) type {
        const StringBuiltins = struct {
            pub fn len(str: types.String, gpa: std.mem.Allocator, args: []const TestValue) TestValue {
                if (args.len != 0) return .{ .err = "'len' wants no arguments" };
                return TestValue.from(gpa, str.bytes.len);
            }
        };
        return switch (tag) {
            .string => StringBuiltins,
            else => struct {},
        };
    }

    pub fn fromStringLiteral(bytes: types.String) TestValue {
        return .{ .string = bytes };
    }

    pub fn fromNumberLiteral(bytes: []const u8) TestValue {
        _ = bytes;
        return .{ .int = 0 };
    }

    pub fn fromBooleanLiteral(b: bool) TestValue {
        return .{ .bool = b };
    }

    pub fn from(gpa: std.mem.Allocator, value: anytype) TestValue {
        _ = gpa;
        const T = @TypeOf(value);
        switch (T) {
            *TestContext => return .{ .global = value },
            *TestContext.Site => return .{ .site = value },
            *TestContext.Page => return .{ .page = value },
            []const u8 => return .{ .string = .{ .bytes = value, .must_free = false } },
            usize => return .{ .int = value },
            else => @compileError("TODO: add support for " ++ @typeName(T)),
        }
    }
};

const TestContext = struct {
    version: []const u8,
    page: Page,
    site: Site,

    pub const Site = struct {
        name: []const u8,

        pub const PassByRef = true;
        pub const dot = types.defaultDot(Site, TestValue);
    };
    pub const Page = struct {
        title: []const u8,
        content: []const u8,

        pub const PassByRef = true;
        pub const dot = types.defaultDot(Page, TestValue);
    };

    pub const PassByRef = true;
    pub const dot = types.defaultDot(TestContext, TestValue);
};

const test_ctx: TestContext = .{
    .version = "v0",
    .page = .{
        .title = "Home",
        .content = "<p>Welcome!</p>",
    },
    .site = .{
        .name = "Loris Cro's Personal Blog",
    },
};

const TestInterpreter = ScriptyVM(TestContext, TestValue);

test "basic" {
    const code = "$page.title";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var t = test_ctx;
    var vm: TestInterpreter = .{};
    const result = try vm.run(arena.allocator(), &t, code, .{});

    const ex: TestInterpreter.Result = .{
        .loc = .{ .start = 0, .end = code.len },
        .value = .{
            .string = .{
                .must_free = false,
                .bytes = "Home",
            },
        },
    };

    errdefer std.debug.print("result = `{s}`\n", .{result.value.string.bytes});

    try std.testing.expectEqualDeep(ex, result);
}

test "builtin" {
    const code = "$page.title.len()";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var t = test_ctx;
    var vm: TestInterpreter = .{};
    const result = try vm.run(arena.allocator(), &t, code, .{});

    const ex: TestInterpreter.Result = .{
        .loc = .{ .start = 0, .end = code.len },
        .value = .{ .int = 4 },
    };

    errdefer std.debug.print("result = `{s}`\n", .{result.value.string.bytes});

    try std.testing.expectEqualDeep(ex, result);
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
