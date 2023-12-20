const std = @import("std");
const datetime = @import("datetime").datetime;
const DateTime = datetime.Datetime;
const Tokenizer = @import("Tokenizer.zig");

pub const String = struct {
    must_free: bool,
    bytes: []const u8,
};

pub const Array = struct {
    must_free: bool,
    items: []Value,
};
// pub const ScriptFunction = *const fn ([]const Value, arena: std.mem.Allocator) ScriptResult;
// pub const ScriptResult = union(enum) {
//     ok: Value,
//     err: []const u8,

//     pub fn unwrap(self: ScriptResult) Value {
//         switch (self) {
//             .ok => |v| return v,
//             .err => |e| @panic(e),
//         }
//     }
// };

// pub const ExternalValue = struct {
//     value: *anyopaque,
//     path: ?[]const u8 = null,
// };

pub const Result = struct {
    value: Value,
    loc: Tokenizer.Token.Loc,
};

pub const Value = union(enum) {
    global: []const u8, // path into the global namespace
    date: DateTime,
    string: String,
    bool: bool,
    int: usize,
    float: f64,
    array: Array,
    err: []const u8, // error message
    nil,

    pub fn dot(self: Value, gpa: std.mem.Allocator, path: []const u8) error{OutOfMemory}!Value {
        _ = self;
        _ = gpa;
        _ = path;
        @panic("TODO: implement dot on value");
    }

    pub fn call(
        self: Value,
        gpa: std.mem.Allocator,
        path: []const u8,
        args: []const Value,
    ) error{OutOfMemory}!Value {

        // No nested builtins: path must be a field
        for (path) |c| if (c == '.') {
            @panic("TODO: implement nested fields for map values");
            // should be implemented before this check
            // return .{ .err = "tryng to access field in a primitive value" };
        };
        const field = path;

        switch (self) {
            .global => unreachable,
            .float => @panic("TODO: float support in scripty"),
            .nil => @panic("TODO: explain that you dotted on a nil"),
            inline else => |t| {
                const Builtin = Value.builtinFor(t);
                inline for (@typeInfo(Builtin).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        @field(Builtin, struct_field.name)(@field(self, t), gpa, args);
                    }
                }

                return error.NotFound;
            },
        }
    }

    fn builtinFor(comptime tag: @typeInfo(Value).Union.tag_type.?) type {
        return switch (tag) {
            .global, .err, .nil => @compileError("these tags can't have builtins"),
            .float, .nil => @panic("TODO"),
            .date => DateBuiltins,
            .string => StringBuiltins,
            .bool => BoolBuiltins,
            .int => IntBuiltins,
            .array => ArrayBuiltins,
        };
    }

    const DateBuiltins = struct {
        pub fn format(dt: DateTime, gpa: std.mem.Allocator, args: []const Value) !Result {
            const argument_error = .{ .err = "'format' wants one (string) argument" };
            if (args.len != 1) return argument_error;
            const string = switch (args[1]) {
                .string => |s| s,
                else => return argument_error,
            };

            if (!std.mem.eql(u8, string, "January 02, 2006")) {
                @panic("TODO: implement more date formatting options");
            }

            const formatted_date = try std.fmt.allocPrint(gpa, "{s} {:0>2}, {}", .{
                dt.date.monthName(),
                dt.date.day,
                dt.date.year,
            });

            return .{
                .string = .{
                    .must_free = true,
                    .bytes = formatted_date,
                },
            };
        }
    };
    const IntBuiltins = struct {
        pub fn plus(num: usize, _: std.mem.Allocator, args: []const Value) Result {
            const argument_error = .{ .err = "'plus' wants one (int|float) argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |add| {
                    return .{ .int = num +| add };
                },
                .float => @panic("TODO: int with float argument"),
                else => return argument_error,
            }
        }
        pub fn div(num: usize, _: std.mem.Allocator, args: []const Value) Result {
            const argument_error = .{ .err = "'div' wants one (int|float) argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |den| {
                    const res = std.math.divTrunc(usize, num, den) catch |err| {
                        return .{ .err = @errorName(err) };
                    };

                    return .{ .int = res };
                },
                .float => @panic("TODO: div with float argument"),
                else => return argument_error,
            }
        }
    };

    const ArrayBuiltins = struct {
        pub fn len(array: Array, _: std.mem.Allocator, args: []const Value) Result {
            if (args.len != 0) return .{ .err = "'len' wants no arguments" };
            return .{ .int = array.len };
        }
    };
    const BoolBuiltins = struct {
        pub fn not(b: bool, _: std.mem.Allocator, args: []const Value) Result {
            if (args.len != 0) return .{ .err = "'not' wants no arguments" };
            return .{ .bool = !b };
        }
    };
    const StringBuiltins = struct {
        pub fn len(str: String, _: std.mem.Allocator, args: []const Value) Result {
            if (args.len != 0) return .{ .err = "'len' wants no arguments" };
            return .{ .int = str.len };
        }

        pub fn startsWith(haystack: String, _: std.mem.Allocator, args: []const Value) Result {
            const argument_error = .{
                .err = "'startsWith' wants one (string) argument, the needle",
            };

            if (args.len != 1) return argument_error;
            const needle = switch (args[1]) {
                .string => |s| s,
                else => return argument_error,
            };

            return .{ .bool = std.mem.startsWith(u8, haystack, needle) };
        }
    };
};
