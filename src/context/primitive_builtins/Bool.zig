const std = @import("std");
const utils = @import("../utils.zig");
const Allocator = std.mem.Allocator;
const Signature = @import("../docgen.zig").Signature;
const Value = @import("../../context.zig").Value;

pub const then = struct {
    pub const signature: Signature = .{ .params = &.{ .dyn, .dyn }, .ret = .dyn };
    pub const description =
        \\If the boolean is `true`, returns the first argument.
        \\Otherwise, returns the second argument.
        \\
    ;
    pub const examples =
        \\$page.draft.then("<alert>DRAFT!</alert>", "")
    ;
    pub fn call(
        b: bool,
        _: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len != 2) return .{ .err = "'then' wants two arguments" };

        if (b) {
            return args[0];
        } else {
            return args[1];
        }
    }
};
pub const not = struct {
    pub const signature: Signature = .{ .ret = .bool };
    pub const description =
        \\Negates a boolean value.
        \\
    ;
    pub const examples =
        \\$page.draft.not()
    ;
    pub fn call(
        b: bool,
        _: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len != 0) return .{ .err = "'not' wants no arguments" };
        return .{ .bool = !b };
    }
};
pub const @"and" = struct {
    pub const signature: Signature = .{
        .params = &.{ .bool, .{ .many = .bool } },
        .ret = .bool,
    };

    pub const description =
        \\Computes logical `and` between the receiver value and any other value passed as argument.
        \\
    ;
    pub const examples =
        \\$page.draft.and($site.tags.len().eq(10))
    ;
    pub fn call(
        b: bool,
        _: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len == 0) return .{ .err = "'and' wants at least one argument" };
        for (args) |a| switch (a) {
            .bool => {},
            else => return .{ .err = "wrong argument type" },
        };
        if (!b) return .{ .bool = false };
        for (args) |a| if (!a.bool) return .{ .bool = false };

        return .{ .bool = true };
    }
};
pub const @"or" = struct {
    pub const signature: Signature = .{
        .params = &.{ .bool, .{ .many = .bool } },
        .ret = .bool,
    };
    pub const description =
        \\Computes logical `or` between the receiver value and any other value passed as argument.
        \\
    ;
    pub const examples =
        \\$page.draft.or($site.tags.len().eq(0))
    ;
    pub fn call(
        b: bool,
        _: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len == 0) return .{ .err = "'or' wants at least one argument" };
        for (args) |a| switch (a) {
            .bool => {},
            else => return .{ .err = "wrong argument type" },
        };
        if (b) return .{ .bool = true };
        for (args) |a| if (a.bool) return .{ .bool = true };

        return .{ .bool = false };
    }
};
