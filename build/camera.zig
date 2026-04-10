//! Runs a program that might or might not fail and appends to stdout what
//! the actual exit code was, always returning a successful exit code under
//! normal conditions (regardless of the child's exit code).
//!
//! This is useful for snapshot tests where some of which are meant to be
//! successes, while others are meant to be failures.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var child = try std.process.spawn(io, .{ .argv = args[1..] });
    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            const fmt = "\n\n ----- EXIT CODE: {} -----\n";
            std.debug.print(fmt, .{code});
            // try std.io.getStdOut().writer().print(fmt, .{code});
        },
        else => std.debug.panic("child process crashed: {}\n", .{term}),
    }
}
