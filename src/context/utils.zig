const std = @import("std");
const ziggy = @import("ziggy");
const super = @import("superhtml");
const Allocator = std.mem.Allocator;
const Asset = @import("Asset.zig");
const Value = @import("../context.zig").Value;

pub const log = std.log.scoped(.builtin);

pub const Resources = struct {
    kind: Asset.Kind,
    ref: []const u8,
};

pub const SuperHTMLResource = super.utils.ResourceDescriptor(Resources);

pub fn HostExtern(comptime T: type) type {
    return struct {
        ext_fn: ExtFn = undef,

        pub const Args = T;
        pub const ExtFn = *const fn (*const @This(), Allocator, T) error{OutOfMemory}!Value;
        const Self = @This();

        pub fn call(
            he: *const Self,
            gpa: Allocator,
            arg: T,
        ) error{OutOfMemory}!Value {
            return he.ext_fn(he, gpa, arg);
        }

        pub fn undef(
            he: *const Self,
            gpa: Allocator,
            arg: T,
        ) !Value {
            _ = he;
            _ = gpa;
            _ = arg;
            @panic("programming error: the host application forgot to set a extern");
        }

        // TODO: add to ziggy the ability to omit fields more directly
        pub const ziggy_options = struct {
            pub fn stringify(
                value: Self,
                opts: ziggy.serializer.StringifyOptions,
                indent_level: usize,
                depth: usize,
                writer: anytype,
            ) !void {
                _ = value;
                _ = opts;
                _ = indent_level;
                _ = depth;

                try writer.writeAll("{}");
            }

            pub fn parse(
                p: *ziggy.Parser,
                first_tok: ziggy.Tokenizer.Token,
            ) !Self {
                try p.must(first_tok, .lb);
                _ = try p.nextMust(.rb);
                return .{};
            }
        };
    };
}
