const Int = @This();

const std = @import("std");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Bool = context.Bool;
const String = context.String;

value: i64,

pub fn init(i: i64) Value {
    return .{ .int = .{ .value = i } };
}

pub const PassByRef = false;
pub const description = "A signed 64-bit integer.";
pub const Builtins = struct {
    pub const eq = struct {
        pub const signature: Signature = .{
            .params = &.{.Int},
            .ret = .Bool,
        };
        pub const description =
            \\Tests if two integers have the same value.
            \\
        ;
        pub const examples =
            \\$page.wordCount().eq(200)
        ;
        pub fn call(
            int: Int,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const argument_error = .{ .err = "'plus' wants one int argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |rhs| return Bool.init(int.value == rhs.value),
                else => return argument_error,
            }
        }
    };
    pub const gt = struct {
        pub const signature: Signature = .{
            .params = &.{.Int},
            .ret = .Bool,
        };
        pub const description =
            \\Returns true if lhs is greater than rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.wordCount().gt(200)
        ;
        pub fn call(
            int: Int,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const argument_error = .{ .err = "'gt' wants one int argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |rhs| return Bool.init(int.value > rhs.value),
                else => return argument_error,
            }
        }
    };

    pub const plus = struct {
        pub const signature: Signature = .{
            .params = &.{.Int},
            .ret = .Int,
        };
        pub const description =
            \\Sums two integers.
            \\
        ;
        pub const examples =
            \\$page.wordCount().plus(10)
        ;
        pub fn call(
            int: Int,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const argument_error = .{ .err = "expected 1 int argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |add| return Int.init(int.value +| add.value),
                .float => @panic("TODO: int with float argument"),
                else => return argument_error,
            }
        }
    };
    pub const div = struct {
        pub const signature: Signature = .{
            .params = &.{.Int},
            .ret = .Int,
        };
        pub const description =
            \\Divides the receiver by the argument.
            \\
        ;
        pub const examples =
            \\$page.wordCount().div(10)
        ;
        pub fn call(
            int: Int,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const argument_error = .{ .err = "'div' wants one (int|float) argument" };
            if (args.len != 1) return argument_error;

            switch (args[0]) {
                .int => |den| {
                    const res = std.math.divTrunc(i64, int.value, den.value) catch |err| {
                        return .{ .err = @errorName(err) };
                    };

                    return Int.init(res);
                },
                .float => @panic("TODO: div with float argument"),
                else => return argument_error,
            }
        }
    };

    pub const byteSize = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const description =
            \\Turns a raw number of bytes into a human readable string that
            \\appropriately uses Kilo, Mega, Giga, etc.
            \\
        ;
        pub const examples =
            \\$page.asset('photo.jpg').size().byteSize()
        ;
        pub fn call(
            int: Int,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const size: usize = if (int.value > 0) @intCast(int.value) else return Value.errFmt(
                gpa,
                "cannot represent {} (a negative value) as a size",
                .{int.value},
            );

            return String.init(try std.fmt.allocPrint(gpa, "{:.0}", .{
                std.fmt.fmtIntSizeBin(size),
            }));
        }
    };
};
