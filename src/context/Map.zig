const Map = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const scripty = @import("scripty");
const context = @import("../context.zig");
const DateTime = @import("DateTime.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Optional = context.Optional;
const Bool = context.Bool;

value: ZiggyMap,

pub const ZiggyMap = ziggy.dynamic.Map(ziggy.dynamic.Value);

pub fn dot(map: Map, gpa: Allocator, path: []const u8) Value {
    _ = map;
    _ = gpa;
    _ = path;
    return .{ .err = "Map has no fields" };
}
pub const description =
    \\A map that can hold any value, used to represent the `custom` field 
    \\in Page frontmatters or Ziggy / JSON data loaded from assets.
;
pub const Builtins = struct {
    pub const getOr = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .String },
            .ret = .String,
        };
        pub const description =
            \\Tries to get a value from a map, returns the second value on failure.
            \\
        ;
        pub const examples =
            \\$page.custom.getOr('coauthor', 'Loris Cro')
        ;
        pub fn call(
            map: Map,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 2 string arguments" };
            if (args.len != 2) return bad_arg;

            const path = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const default = args[1];

            if (map.value.fields.get(path)) |value| {
                if (value == .null) return default;
                return Value.fromZiggy(gpa, value);
            }

            return default;
        }
    };

    pub const get = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .any,
        };
        pub const description =
            \\Tries to get a value from a map, errors out if the value is not present.
            \\
        ;
        pub const examples =
            \\$page.custom.get('coauthor')
        ;
        pub fn call(
            map: Map,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const path = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const missing = try Value.errFmt(gpa, "missing value '{s}'", .{path});

            if (map.value.fields.get(path)) |value| {
                if (value == .null) return missing;
                return Value.fromZiggy(gpa, value);
            }

            return missing;
        }
    };

    pub const @"get?" = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .{ .Opt = .any },
        };
        pub const description =
            \\Tries to get a dynamic value, to be used in conjuction with an `if` attribute.
            \\
        ;
        pub const examples =
            \\<div if="$page.custom.get?('myValue')">
            \\  <span text="$if"></span>
            \\</div>
        ;
        pub fn call(
            map: Map,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "'get?' wants 1 string argument" };
            if (args.len != 1) return bad_arg;

            const path = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            if (map.value.fields.get(path)) |value| {
                return Value.fromZiggy(gpa, value);
            }

            return Optional.Null;
        }
    };
    pub const has = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Bool,
        };
        pub const description =
            \\Returns true if the map contains the provided key.
            \\
        ;
        pub const examples =
            \\<div if="$page.custom.has('myValue')">Yep!</div>
        ;
        pub fn call(
            map: Map,
            gpa: Allocator,
            args: []const Value,
        ) Value {
            _ = gpa;
            const bad_arg = .{ .err = "'get?' wants 1 string argument" };
            if (args.len != 1) return bad_arg;

            const path = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            return Bool.init(map.value.fields.get(path) != null);
        }
    };

    pub const iterate = struct {
        pub const signature: Signature = .{
            .params = &.{.{ .Opt = .String }},
            .ret = .{ .Many = .KV },
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
            map: Map,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 0 or 1 string argument" };
            if (args.len > 1) return bad_arg;

            const filter: ?[]const u8 = if (args.len == 0) null else switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            return .{
                .iterator = try context.Iterator.init(gpa, .{
                    .map_it = context.Iterator.MapIterator.init(
                        map.value.fields.iterator(),
                        filter,
                    ),
                }),
            };
        }
    };
};

pub const KV = struct {
    key: []const u8,
    value: ziggy.dynamic.Value,

    pub const dot = scripty.defaultDot(KV, Value, false);
    pub const description = "A key-value pair.";
    pub const Fields = struct {
        pub const key = "The key string.";
        pub const value = "The corresponding value.";
    };
    pub const Builtins = struct {};
};
