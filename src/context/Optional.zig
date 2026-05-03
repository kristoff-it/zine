const Optional = @This();

const std = @import("std");
const context = @import("../context.zig");
const Allocator = std.mem.Allocator;
const Value = context.Value;

value: Value,

pub const Null: Value = .{ .optional = null };
pub fn init(gpa: Allocator, v: anytype) !Value {
    const box = try gpa.create(Optional);
    box.value = try Value.from(gpa, v);
    return .{ .optional = box };
}

pub const PassByRef = false;
pub const docs_description = "An optional value, to be used in conjunction with `if` attributes.";
pub const Builtins = struct {};
