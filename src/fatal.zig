const std = @import("std");
const main = @import("main.zig");
const builtin = @import("builtin");

pub fn msg(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    if (builtin.mode == .Debug) std.debug.panic("\n\n(Zine debug stack trace)\n", .{});
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

pub fn help() noreturn {
    std.debug.print(
        \\Usage: zine [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  (no command)      Start the development web server
        \\  init              Initialize a Zine site in the current directory
        \\  release           Create a release of a Zine site
        \\  help              Show this menu and exit
        \\  version           Print the Zine version and exit
        \\
        \\General Options:
        \\  --drafts          Enable draft pages
        \\  --help, -h        Print command specific usage and extra options
        \\
        \\Development web server options: 
        \\  --host HOST       Listening host (default 'localhost')
        \\  --port PORT       Listening port (default 1990)
        \\  --debounce <ms>   Rebuild delay after a file change (default 25)
        \\
        \\
    , .{});
    std.process.exit(1);
}
