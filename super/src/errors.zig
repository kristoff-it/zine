const std = @import("std");
const sitter = @import("sitter.zig");
const builtin = @import("builtin");

const disable_printing = builtin.is_test;

/// Used to catch programming errors where a function fails to report
/// correctly that an error has occurred.
pub const Reported = error{
    /// The error has been fully reported.
    Reported,
    /// The error has been reported but we should also print the
    /// interface of the template we are extending.
    WantInterface,
};

pub fn report(
    template_name: []const u8,
    template_path: []const u8,
    bad_node: sitter.Node,
    html: []const u8,
    comptime error_code: []const u8,
    comptime title: []const u8,
    comptime msg: []const u8,
) Reported {
    header(title, msg);
    const error_line = comptime "[" ++ error_code ++ "]";
    diagnostic(template_name, template_path, error_line, bad_node, html);
    return error.Reported;
}

pub fn diagnostic(
    template_name: []const u8,
    template_path: []const u8,
    comptime note_line: []const u8,
    node: sitter.Node,
    html: []const u8,
) void {
    if (disable_printing) return;
    const pos = node.selection();
    const line_off = node.line(html);
    const offset = node.offset();

    // trim spaces
    const line_trim_left = std.mem.trimLeft(u8, line_off.line, &std.ascii.whitespace);
    const start_trim_left = line_off.start + line_off.line.len - line_trim_left.len;

    const caret_len = offset.end - offset.start;
    const caret_spaces_len = offset.start - start_trim_left;

    const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

    var buf: [1024]u8 = undefined;

    const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
        const h = buf[0 .. caret_len + caret_spaces_len];
        @memset(h[0..caret_spaces_len], ' ');
        @memset(h[caret_spaces_len..][0..caret_len], '^');
        break :blk h;
    } else "";

    std.debug.print(
        \\
        \\{s}
        \\({s}) {s}:{}:{}:
        \\    {s}
        \\    {s}
        \\
    , .{
        note_line,
        template_name,
        template_path,
        pos.start.row,
        pos.start.col,
        line_trim,
        highlight,
    });
}

pub fn header(
    comptime title: []const u8,
    comptime msg: []const u8,
) void {
    if (disable_printing) return;
    std.debug.print(
        \\
        \\---------- {s} ----------
        \\
    , .{title});
    std.debug.print(msg, .{});
    std.debug.print("\n", .{});
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (!disable_printing) std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}

// fn toLower(
//     data: []const u8,
//     comptime fmt: []const u8,
//     options: std.fmt.FormatOptions,
//     writer: anytype,
// ) !void {
//     for (data) |c| {
//         writer.write(std.ascii.toLower(c));
//     }
// }
