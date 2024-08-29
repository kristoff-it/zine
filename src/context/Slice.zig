const Slice = @This();

const std = @import("std");
const context = @import("../context.zig");
const Allocator = std.mem.Allocator;
const Value = context.Value;

value: []const Value,

pub fn dot(s: Slice, gpa: Allocator, path: []const u8) !Value {
    _ = s;
    _ = gpa;
    _ = path;
    return .{ .err = "todo" };
}
pub const description = "TODO";
pub const Builtins = struct {};
