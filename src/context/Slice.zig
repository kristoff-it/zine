const Slice = @This();

const std = @import("std");
const context = @import("../context.zig");
const Allocator = std.mem.Allocator;
const Value = context.Value;

value: []const Value,

pub const docs_description = "TODO";
pub const Builtins = struct {};
