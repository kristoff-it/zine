const std = @import("std");
const main = @import("main.zig");
const builtin = @import("builtin");

pub fn msg(comptime fmt: []const u8, args: anytype) noreturn {
    if (builtin.mode == .Debug) std.debug.panic(fmt, args);
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    msg("oom\n", .{});
}

pub fn dir(path: []const u8, err: anyerror) noreturn {
    msg("error accessing dir '{s}': {s}\n", .{
        path, @errorName(err),
    });
}

pub fn file(path: []const u8, err: anyerror) noreturn {
    msg("error accessing file '{s}': {s}\n", .{
        path, @errorName(err),
    });
}
