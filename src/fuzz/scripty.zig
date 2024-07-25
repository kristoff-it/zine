const std = @import("std");
const zine = @import("zine");

export fn zig_fuzz_init() void {}

export fn zig_fuzz_test(buf: [*]u8, len: isize) void {}
