//! Runs a program that might or might not fail and appends to stdout what
//! the actual exit code was, always returning a successful exit code under
//! normal conditions (regardless of the child's exit code).
//!
//! This is useful for snapshot tests where some of which are meant to be
//! successes, while others are meant to be failures.
const std = @import("std");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const args = try std.process.argsAlloc(gpa);

    var cmd = std.process.Child.init(args[1..], gpa);
    const term = try cmd.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            const fmt = "\n\n ----- EXIT CODE: {} -----\n";
            std.debug.print(fmt, .{code});
            // try std.io.getStdOut().writer().print(fmt, .{code});
        },
        else => std.debug.panic("child process crashed: {}\n", .{term}),
    }
}
