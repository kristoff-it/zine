const std = @import("std");
const assert = std.debug.assert;
const ziggy = @import("ziggy");
const utils = @import("../utils.zig");
const context = @import("../../context.zig");
const DateTime = @import("../DateTime.zig");
const Signature = @import("../docgen.zig").Signature;
const Value = context.Value;
const Allocator = std.mem.Allocator;

pub const get = struct {
    pub const signature: Signature = .{ .params = &.{ .str, .dyn }, .ret = .dyn };
    pub const description =
        \\Tries to get a dynamic value, returns the second value on failure.
        \\
    ;
    pub const examples =
        \\$page.custom.get('coauthor', 'Loris Cro')
    ;
    pub fn call(
        dyn: ziggy.dynamic.Value,
        gpa: Allocator,
        args: []const Value,
    ) Value {
        _ = gpa;
        const bad_arg = .{ .err = "'get' wants two (string) arguments" };
        if (args.len != 2) return bad_arg;

        const path = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        const default = args[1];

        if (dyn == .null) return default;
        if (dyn != .kv) return .{ .err = "get on a non-map dynamic value" };

        if (dyn.kv.fields.get(path)) |value| {
            switch (value) {
                .null => return default,
                .bool => |b| return .{ .bool = b },
                .integer => |i| return .{ .int = i },
                .bytes => |s| return .{ .string = s },
                .tag => |t| {
                    assert(std.mem.eql(u8, t.name, "date"));
                    const date = DateTime.init(t.bytes) catch {
                        return .{ .err = "error parsing date" };
                    };
                    return .{ .date = date };
                },
                inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
            }
        }

        return default;
    }
};

pub const @"get!" = struct {
    pub const signature: Signature = .{ .params = &.{.str}, .ret = .dyn };
    pub const description =
        \\Tries to get a dynamic value, errors out if the value is not present.
        \\
    ;
    pub const examples =
        \\$page.custom.get!('coauthor')
    ;
    pub fn call(
        dyn: ziggy.dynamic.Value,
        gpa: Allocator,
        args: []const Value,
    ) Value {
        _ = gpa;
        const bad_arg = .{ .err = "'get' wants one (string) argument" };
        if (args.len != 1) return bad_arg;

        const path = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        if (dyn != .kv) return .{ .err = "get on a non-map dynamic value" };

        if (dyn.kv.fields.get(path)) |value| {
            switch (value) {
                .null => return .{ .err = "missing value" },
                .bool,
                => |b| return .{ .bool = b },
                .integer => |i| return .{ .int = i },
                .bytes => |s| return .{ .string = s },
                .tag => |t| {
                    assert(std.mem.eql(u8, t.name, "date"));
                    const date = DateTime.init(t.bytes) catch {
                        return .{ .err = "error parsing date" };
                    };
                    return .{ .date = date };
                },
                .kv => return .{ .dynamic = value },
                inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
            }
        }

        return .{ .err = "missing value" };
    }
};

pub const @"get?" = struct {
    pub const signature: Signature = .{ .params = &.{.str}, .ret = .{ .opt = .dyn } };
    pub const description =
        \\Tries to get a dynamic value, to be used in conjuction with an `if` attribute.
        \\
    ;
    pub const examples =
        \\<div if="$page.custom.get?('myValue')"><span var="$if"></span></div>
    ;
    pub fn call(
        dyn: ziggy.dynamic.Value,
        gpa: Allocator,
        args: []const Value,
    ) Value {
        _ = gpa;
        const bad_arg = .{ .err = "'get?' wants 1 string argument" };
        if (args.len != 1) return bad_arg;

        const path = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        if (dyn == .null) return .{ .optional = null };
        if (dyn != .kv) return .{ .err = "get? on a non-map dynamic value" };

        if (dyn.kv.fields.get(path)) |value| {
            switch (value) {
                .null => return .{ .optional = null },
                .bool => |b| return .{ .optional = .{ .bool = b } },
                .integer => |i| return .{ .optional = .{ .int = i } },
                .bytes => |s| return .{ .optional = .{ .string = s } },
                .kv => return .{ .optional = .{ .dynamic = value } },
                inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
            }
        }

        return .{ .optional = null };
    }
};
pub const has = struct {
    pub const signature: Signature = .{ .params = &.{.str}, .ret = .bool };
    pub const description =
        \\Returns true if the map contains the provided key.
        \\
    ;
    pub const examples =
        \\<div if="$page.custom.has('myValue')">Yep!</div>
    ;
    pub fn call(
        dyn: ziggy.dynamic.Value,
        gpa: Allocator,
        args: []const Value,
    ) Value {
        _ = gpa;
        const bad_arg = .{ .err = "'get?' wants 1 string argument" };
        if (args.len != 1) return bad_arg;

        const path = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        if (dyn == .null) return .{ .optional = null };
        if (dyn != .kv) return .{ .err = "has called on a non-map dynamic value" };

        return .{
            .bool = dyn.kv.fields.get(path) != null,
        };
    }
};

pub const iterate = struct {
    pub const signature: Signature = .{
        .parameters = &.{ .opt = .{.str} },
        .ret = .dyn,
    };
    pub const description =
        \\Iterates over key-value pairs of a Ziggy map.
        \\
        \\You can optionally pass a string that will be used to filter key names.
    ;
    pub const examples =
        \\$page.custom.iterate()
    ;
    pub fn call(
        dyn: ziggy.dynamic.Value,
        gpa: Allocator,
        args: []const Value,
    ) Value {
        _ = gpa;
        const bad_arg = .{ .err = "expected 0 or 1 string arguments" };
        if (args.len > 1) return bad_arg;

        if (dyn != .kv) return .{
            .err = "trying to iterate a non-map dynamic value",
        };

        const filter: ?[]const u8 = if (args.len == 0) null else switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        return .{
            .iterator = .{
                .impl = .{
                    .map_it = context.MapIterator.init(dyn.kv.fields.iterator(), filter),
                },
            },
        };
    }
};
