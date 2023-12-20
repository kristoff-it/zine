const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");
const types = @import("types.zig");
const Result = types.Result;
const Value = types.Value;

const log = std.log.scoped(.scripty_vm);

pub const Diagnostics = struct {
    loc: Tokenizer.Token.Loc,
};

pub const RunError = error{ OutOfMemory, Quota };

pub fn ScriptyVM(comptime Context: type) type {
    return struct {
        parser: Parser = .{},
        stack: std.MultiArrayList(Result) = .{},
        /// Set to 0 to disable quota
        quota: usize,

        pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
            self.stack.deinit(gpa);
        }

        pub fn run(
            self: *@This(),
            gpa: std.mem.Allocator,
            code: []const u8,
            ctx: *Context,
            diag: ?*Diagnostics,
        ) RunError!Result {
            // On error make the vm usable again.
            errdefer |err| switch (@as(RunError, err)) {
                error.Quota => {},
                else => self.stack.shrinkRetainingCapacity(0),
            };

            if (diag != null) @panic("TODO: implement diagnostics");
            if (self.quota == 1) return error.Quota;

            while (self.parser.next(code)) |node| : ({
                if (self.quota == 1) return error.Quota;
                self.quota -|= 1;
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
                        .value = .{ .string = try node.loc.unquote(gpa, code) },
                        .loc = node.loc,
                    }),
                    .number => try self.stack.append(gpa, .{
                        .value = .{ .int = 0 },
                        .loc = node.loc,
                    }),
                    .true => try self.stack.append(gpa, .{
                        .value = .{ .bool = true },
                        .loc = node.loc,
                    }),
                    .false => try self.stack.append(gpa, .{
                        .value = .{ .bool = false },
                        .loc = node.loc,
                    }),
                    .path => {
                        // log.err("(vm) {any} `{s}`", .{
                        //     node.loc,
                        //     code[node.loc.start..node.loc.end],
                        // });
                        const global = code[node.loc.start] == '$';
                        const call = code[node.loc.end - 1] == '(';
                        const start = node.loc.start + @intFromBool(global);
                        const end = node.loc.end - @intFromBool(call);
                        const path = code[start..end];

                        if (call) {
                            try self.stack.append(gpa, .{
                                .loc = node.loc,
                                .value = .{ .lazy_path = path },
                            });
                            continue;
                        }

                        if (global) {
                            const value = try ctx.dot(gpa, path);
                            if (value == .err) {
                                self.stack.shrinkRetainingCapacity(0);
                                return .{ .loc = node.loc, .value = value };
                            }
                            try self.stack.append(gpa, .{
                                .loc = node.loc,
                                .value = value,
                            });
                        } else {
                            const stack_values = self.stack.items(.value);
                            const last = &stack_values[stack_values.len - 1];
                            const value = try last.dot(gpa, path);
                            if (value == .err) {
                                self.stack.shrinkRetainingCapacity(0);
                                const locs = self.stack.items(.loc);
                                const last_loc = locs[stack_values.len - 1];
                                return .{
                                    .loc = .{
                                        .start = last_loc.start,
                                        .end = end,
                                    },
                                    .value = value,
                                };
                            }
                        }
                    },
                    .apply => {
                        const slice = self.stack.slice();
                        const stack_locs = slice.items(.loc);
                        var call_idx = stack_locs.len - 1;
                        while (true) : (call_idx -= 1) {
                            const current = stack_locs[call_idx];
                            if (code[current.end - 1] == '(') break;
                        }

                        const stack_values = slice.items(.value);

                        const path = stack_values[call_idx].lazy_path;
                        const args = stack_values[call_idx + 1 ..];

                        const result = try ctx.call(gpa, path, args);
                        if (result == .err) {
                            self.stack.shrinkRetainingCapacity(0);
                            return .{ .loc = node.loc, .value = value };
                        }
                        // const result = switch (value) {
                        //     .lazy_path => ctx.dotAndCall(gpa, path, args),
                        //     inline else => |v| v.dotAndCall(gpa, path, args),
                        // };

                        // Caller path becomes the new result
                        stack_values[call_idx] = result;

                        // Extend the loc to encompass the entire expression
                        // (which also disables the value as a call path)
                        stack_locs[call_idx].end = node.loc.end;

                        // Remove arguments
                        self.stack.shrinkRetainingCapacity(call_idx + 1);
                    },
                }
            }

            std.debug.assert(self.stack.items(.loc).len == 1);
            const result = self.stack.pop();
            std.debug.assert(result.value != .lazy_path);
            std.debug.assert(result.value != .err);
            return result;
        }
    };
}

const TestContext = struct {
    version: []const u8,
    page: struct {
        title: []const u8,
        authors: []const []const u8,
        content: []const u8,
    },
    site: struct {
        name: []const u8,
    },

    pub fn call(self: *TestContext, gpa: std.mem.Allocator, path: []const u8, args: []const Value) !Value {
        _ = self;
        _ = path;
        _ = gpa;
        _ = args;

        @panic("TODO");
    }
    pub fn dot(self: *TestContext, gpa: std.mem.Allocator, path: []const u8) !Value {
        _ = gpa;
        if (std.mem.eql(u8, path, "page.title")) {
            return .{
                .string = .{
                    .must_free = false,
                    .bytes = self.page.title,
                },
            };
        }

        @panic("TODO");
    }
};

const test_ctx: TestContext = .{
    .version = "v0",
    .page = .{
        .title = "Home",
        .authors = &.{ "loris cro", "andrew kelley" },
        .content = "<p>Welcome!</p>",
    },
    .site = .{
        .name = "Loris Cro's Personal Blog",
    },
};

const TestInterpreter = ScriptyVM(TestContext);

test "basic" {
    const code = "$page.title";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var t = test_ctx;
    var vm: TestInterpreter = .{ .quota = 0 };
    const result = try vm.run(arena.allocator(), code, &t, null);

    const ex: Result = .{
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
