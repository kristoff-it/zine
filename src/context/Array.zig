const Array = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const superhtml = @import("superhtml");
const scripty = @import("scripty");
const context = @import("../context.zig");
const doctypes = @import("doctypes.zig");
const Signature = doctypes.Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Template = context.Template;
const Site = context.Site;
const Page = context.Page;
const Map = context.Map;

len: usize,
empty: bool,
_items: []const Value,

pub fn init(gpa: Allocator, T: type, items: []const T) error{OutOfMemory}!Value {
    if (T == Value) return .{
        .array = .{
            .len = items.len,
            .empty = items.len == 0,
            ._items = items,
        },
    };

    const boxed_items = try gpa.alloc(Value, items.len);

    for (items, boxed_items) |i, *bi| {
        bi.* = try Value.from(gpa, i);
    }

    return .{
        .array = .{
            .len = items.len,
            .empty = items.len == 0,
            ._items = boxed_items,
        },
    };
}

// pub fn deinit(iter: *const Iterator, gpa: Allocator) void {
//     gpa.destroy(iter);
// }

pub const dot = scripty.defaultDot(Array, Value, false);
pub const description = "An array of items.";
pub const Fields = struct {
    pub const len =
        \\The length of the array.
    ;
    pub const empty =
        \\True when len is 0.
    ;
};

pub const Builtins = struct {
    pub const slice = struct {
        pub const signature: Signature = .{
            .params = &.{ .Int, .{ .Opt = .Int } },
            .ret = .Array,
        };
        pub const description =
            \\Slices an array from the first value (inclusive) to the
            \\second value (exclusive).
            \\
            \\The second value can be omitted and defaults to the array's
            \\length, meaning that invoking `slice` with one argunent 
            \\produces **suffixes** of the original sequence (i.e. it 
            \\removes a prefix from the original sequence).
            \\
            \\Note that negative values are not allowed at the moment.
        ;
        pub const examples =
            \\$page.tags.slice(0,1)
        ;
        pub fn call(
            arr: Array,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 1 or 2 integer argument(s)" };
            if (args.len < 1 or args.len > 2) return bad_arg;

            const start = switch (args[0]) {
                .int => |i| i.value,
                else => return bad_arg,
            };
            const end: i64 = if (args.len == 1) @intCast(arr.len) else switch (args[1]) {
                .int => |i| i.value,
                else => return bad_arg,
            };

            if (start < 0) return Value.errFmt(
                gpa,
                "start value {} is negative",
                .{start},
            );

            if (end < 0) return Value.errFmt(
                gpa,
                "end value {} is negative",
                .{end},
            );

            if (start >= arr.len) return Value.errFmt(gpa, "start value {} exceeds array of length {}", .{
                start, arr.len,
            });

            if (end > arr.len) return Value.errFmt(gpa, "end value {} exceeds array of length {}", .{
                end, arr.len,
            });

            if (start > end) return Value.errFmt(gpa, "start value {} is bigger than end value {}!", .{
                start, end,
            });

            const new = arr._items[@intCast(start)..@intCast(end)];

            return .{
                .array = .{
                    .len = new.len,
                    .empty = new.len == 0,
                    ._items = new,
                },
            };
        }
    };

    pub const at = struct {
        pub const signature: Signature = .{
            .params = &.{.Int},
            .ret = .Value,
        };
        pub const description =
            \\Returns the value at the provided index. 
        ;
        pub const examples =
            \\$page.tags.at(0)
        ;
        pub fn call(
            arr: Array,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 1 integer argument" };
            if (args.len != 1) return bad_arg;

            const idx = switch (args[0]) {
                .int => |i| i.value,
                else => return bad_arg,
            };

            if (idx < 0) return Value.errFmt(
                gpa,
                "index value {} is negative",
                .{idx},
            );

            if (idx >= arr.len) return Value.errFmt(gpa, "index {} exceeds array of length {}", .{
                idx, arr.len,
            });

            return arr._items[@intCast(idx)];
        }
    };
};
