const Bool = @This();

const std = @import("std");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const String = context.String;

value: bool,

pub fn init(b: bool) Value {
    return .{ .bool = .{ .value = b } };
}

fn not(b: Bool) Value {
    return .{ .bool = .{ .value = !b.value } };
}

pub const True = Bool.init(true);
pub const False = Bool.init(false);

pub const PassByRef = false;
pub const description = "A boolean value";
pub const Builtins = struct {
    pub const then = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Opt = .String } },
            .ret = .String,
        };
        pub const description =
            \\If the boolean is `true`, returns the first argument.
            \\Otherwise, returns the second argument.
            \\
            \\The second argument defaults to an empty string.
            \\
        ;
        pub const examples =
            \\$page.draft.then("<alert>DRAFT!</alert>")
        ;
        pub fn call(
            b: Bool,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len < 1 or args.len > 2) return .{
                .err = "expected 1 or 2 string arguments",
            };

            if (b.value) {
                return args[0];
            } else {
                if (args.len < 2) return String.init("");
                return args[1];
            }
        }
    };
    pub const not = struct {
        pub const signature: Signature = .{ .ret = .Bool };
        pub const description =
            \\Negates a boolean value.
            \\
        ;
        pub const examples =
            \\$page.draft.not()
        ;
        pub fn call(
            b: Bool,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return b.not();
        }
    };
    pub const @"and" = struct {
        pub const signature: Signature = .{
            .params = &.{ .Bool, .{ .Many = .Bool } },
            .ret = .Bool,
        };

        pub const description =
            \\Computes logical `and` between the receiver value and any other 
            \\value passed as argument.
        ;
        pub const examples =
            \\$page.draft.and($site.tags.len().eq(10))
        ;
        pub fn call(
            b: Bool,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len == 0) return .{ .err = "expected 1 or more boolean argument(s)" };
            for (args) |a| switch (a) {
                .bool => {},
                else => return .{ .err = "wrong argument type" },
            };
            if (!b.value) return False;
            for (args) |a| if (!a.bool.value) return False;

            return True;
        }
    };
    pub const @"or" = struct {
        pub const signature: Signature = .{
            .params = &.{ .Bool, .{ .Many = .Bool } },
            .ret = .Bool,
        };
        pub const description =
            \\Computes logical `or` between the receiver value and any other value passed as argument.
            \\
        ;
        pub const examples =
            \\$page.draft.or($site.tags.len().eq(0))
        ;
        pub fn call(
            b: Bool,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len == 0) return .{ .err = "'or' wants at least one argument" };
            for (args) |a| switch (a) {
                .bool => {},
                else => return .{ .err = "wrong argument type" },
            };
            if (b.value) return True;
            for (args) |a| if (a.bool.value) return True;

            return False;
        }
    };
};
