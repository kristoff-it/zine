const std = @import("std");
const datetime = @import("datetime").datetime;
const DateTime = datetime.Datetime;
const Tokenizer = @import("Tokenizer.zig");

pub const String = struct {
    must_free: bool = false,
    bytes: []const u8,
};

pub const Array = struct {
    must_free: bool,
    items: []Value,
};

pub const Result = struct {
    value: Value,
    loc: Tokenizer.Token.Loc,
};

pub const Value = union(Tag) {
    lazy_path: []const u8,
    date: DateTime,
    string: String,
    bool: bool,
    int: usize,
    float: f64,
    array: Array,
    err: []const u8, // error message
    nil,

    pub const Tag = enum {
        lazy_path,
        date,
        string,
        bool,
        int,
        float,
        array,
        err,
        nil,
    };
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
            .lazy_path => unreachable,
            .float => @panic("TODO: float support in scripty"),
            .nil => @panic("TODO: explain that you dotted on a nil"),
            inline else => |v, tag| {
                const Builtin = Value.builtinFor(tag);
                inline for (@typeInfo(Builtin).Struct.decls) |struct_field| {
                    if (std.mem.eql(u8, struct_field.name, field)) {
                        return @field(Builtin, struct_field.name)(v, gpa, args);
                    }
                }

                return .{ .err = "not found" };
            },
        }
    }

    fn builtinFor(comptime tag: Tag) type {
        return switch (tag) {
            .lazy_path, .err => struct {},
            .float, .nil => struct {},
            .date => DateBuiltins,
            .string => StringBuiltins,
            .bool => BoolBuiltins,
            .int => IntBuiltins,
            .array => ArrayBuiltins,
        };
    }
};

pub const DateBuiltins = struct {
    pub fn format(dt: DateTime, gpa: std.mem.Allocator, args: []const Value) !Value {
        const bad_arg = .{ .err = "'format' wants one (string) argument" };
        if (args.len != 1) return bad_arg;
        const string = switch (args[1]) {
            .string => |s| s,
            else => return bad_arg,
        };

        if (!std.mem.eql(u8, string.bytes, "January 02, 2006")) {
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
pub const IntBuiltins = struct {
    pub fn plus(num: usize, _: std.mem.Allocator, args: []const Value) Value {
        const bad_arg = .{ .err = "'plus' wants one (int|float) argument" };
        if (args.len != 1) return bad_arg;

        switch (args[0]) {
            .int => |add| {
                return .{ .int = num +| add };
            },
            .float => @panic("TODO: int with float argument"),
            else => return bad_arg,
        }
    }
    pub fn div(num: usize, _: std.mem.Allocator, args: []const Value) Value {
        const bad_arg = .{ .err = "'div' wants one (int|float) argument" };
        if (args.len != 1) return bad_arg;

        switch (args[0]) {
            .int => |den| {
                const res = std.math.divTrunc(usize, num, den) catch |err| {
                    return .{ .err = @errorName(err) };
                };

                return .{ .int = res };
            },
            .float => @panic("TODO: div with float argument"),
            else => return bad_arg,
        }
    }
};

pub const ArrayBuiltins = struct {
    pub fn len(array: Array, _: std.mem.Allocator, args: []const Value) Value {
        if (args.len != 0) return .{ .err = "'len' wants no arguments" };
        return .{ .int = array.items.len };
    }
};
pub const BoolBuiltins = struct {
    pub fn not(b: bool, _: std.mem.Allocator, args: []const Value) Value {
        if (args.len != 0) return .{ .err = "'not' wants no arguments" };
        return .{ .bool = !b };
    }
};
pub const StringBuiltins = struct {
    pub fn len(str: String, _: std.mem.Allocator, args: []const Value) Value {
        if (args.len != 0) return .{ .err = "'len' wants no arguments" };
        return .{ .int = str.bytes.len };
    }

    pub fn startsWith(haystack: String, _: std.mem.Allocator, args: []const Value) Value {
        const bad_arg = .{
            .err = "'startsWith' wants one (string) argument, the needle",
        };

        if (args.len != 1) return bad_arg;
        const needle = switch (args[1]) {
            .string => |s| s,
            else => return bad_arg,
        };

        return .{ .bool = std.mem.startsWith(u8, haystack.bytes, needle.bytes) };
    }
};

// pub fn PathNavigator(comptime T: type) type {
//     return struct {
//         const info = @typeInfo(T).Struct;
//         pub fn dot(
//             op: *anyopaque,
//             gpa: std.mem.Allocator,
//             path: []const u8,
//         ) error{OutOfMemory}!Value {
//             const t: *T = @alignCast(@ptrCast(op));
//             var it = std.mem.tokenizeScalar(u8, path, '.');
//             const component = it.next().?;
//             const rest = it.rest();

//             for (info.fields) |f| {
//                 if (std.mem.eql(u8, f.name, component)) {
//                     if (Value.supports(f.type))
//                     const FieldNav = PathNavigator(f.type);
//                     const field_ptr = &@field(t, f.name);
//                     if (rest.len == 0) {
//                         return .{
//                             .global = .{
//                                 .ptr = field_ptr,
//                                 .fn_ptr = &FieldNav.dot,
//                             },
//                         };
//                     } else {
//                         return FieldNav.dot(field_ptr, gpa, rest);
//                     }
//                 }
//             }

//             return .{ .err = "not found" };
//         }
//     };
// }
