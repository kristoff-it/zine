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
        _: *utils.SuperHTMLResource,
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
        _: *utils.SuperHTMLResource,
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
        _: *utils.SuperHTMLResource,
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
        _: *utils.SuperHTMLResource,
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
