const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const root = @import("../root.zig");
const worker = @import("../worker.zig");
const Allocator = std.mem.Allocator;

pub fn release(gpa: Allocator, args: []const []const u8) void {
    const cmd: Command = .parse(args);
    _ = cmd;

    worker.start();
    defer worker.stopWaitAndDeinit();

    const b = root.run(gpa);
    b.deinit(gpa);
}

const Command = struct {
    fn parse(args: []const []const u8) Command {
        for (args) |a| {
            if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
                fatal.msg(
                    \\Usage: zine release [OPTIONS]
                    \\
                    \\Command specific options:
                    // \\  --multilingual   Setup a sample multilingual website
                    \\
                    \\General Options:
                    \\  --help, -h       Print command specific usage
                    \\
                    \\
                , .{});
            }
        }

        return .{};
    }
};
