const std = @import("std");
const utils = @import("../utils.zig");
const Signature = @import("../docgen.zig").Signature;
const Value = @import("../../context.zig").Value;
const Allocator = std.mem.Allocator;

pub const eq = struct {
    pub const signature: Signature = .{
        .params = &.{.int},
        .ret = .bool,
    };
    pub const description =
        \\Tests if two integers have the same value.
        \\
    ;
    pub const examples =
        \\$page.wordCount().eq(200)
    ;
    pub fn call(
        num: i64,
        _: Allocator,
        args: []const Value,
    ) !Value {
        const argument_error = .{ .err = "'plus' wants one int argument" };
        if (args.len != 1) return argument_error;

        switch (args[0]) {
            .int => |rhs| {
                return .{ .bool = num == rhs };
            },
            else => return argument_error,
        }
    }
};
pub const gt = struct {
    pub const signature: Signature = .{
        .params = &.{.int},
        .ret = .bool,
    };
    pub const description =
        \\Returns true if lhs is greater than rhs (the argument).
        \\
    ;
    pub const examples =
        \\$page.wordCount().gt(200)
    ;
    pub fn call(
        num: i64,
        _: Allocator,
        args: []const Value,
    ) !Value {
        const argument_error = .{ .err = "'gt' wants one int argument" };
        if (args.len != 1) return argument_error;

        switch (args[0]) {
            .int => |rhs| {
                return .{ .bool = num > rhs };
            },
            else => return argument_error,
        }
    }
};

pub const plus = struct {
    pub const signature: Signature = .{
        .params = &.{.int},
        .ret = .int,
    };
    pub const description =
        \\Sums two integers.
        \\
    ;
    pub const examples =
        \\$page.wordCount().plus(10)
    ;
    pub fn call(
        num: i64,
        _: Allocator,
        args: []const Value,
    ) !Value {
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
};
pub const div = struct {
    pub const signature: Signature = .{
        .params = &.{.int},
        .ret = .int,
    };
    pub const description =
        \\Divides the receiver by the argument.
        \\
    ;
    pub const examples =
        \\$page.wordCount().div(10)
    ;
    pub fn call(
        num: i64,
        _: Allocator,
        args: []const Value,
    ) !Value {
        const argument_error = .{ .err = "'div' wants one (int|float) argument" };
        if (args.len != 1) return argument_error;

        switch (args[0]) {
            .int => |den| {
                const res = std.math.divTrunc(i64, num, den) catch |err| {
                    return .{ .err = @errorName(err) };
                };

                return .{ .int = res };
            },
            .float => @panic("TODO: div with float argument"),
            else => return argument_error,
        }
    }
};

pub const byteSize = struct {
    pub const signature: Signature = .{
        .ret = .string,
    };
    pub const description =
        \\Turns a raw number of bytes into a human readable string that
        \\appropriately uses Kilo, Mega, Giga, etc.
        \\
    ;
    pub const examples =
        \\$page.asset('photo.jpg').size().byteSize()
    ;
    pub fn call(
        num: i64,
        gpa: Allocator,
        args: []const Value,
    ) !Value {
        if (args.len != 0) return .{ .err = "expected 0 arguments" };

        const size: usize = if (num > 0) @intCast(num) else return Value.errFmt(
            gpa,
            "cannot represent {} (a negative value) as a size",
            .{num},
        );

        return .{
            .string = try std.fmt.allocPrint(gpa, "{:.0}", .{
                std.fmt.fmtIntSizeBin(size),
            }),
        };
    }
};
