const std = @import("std");
const sitter = @import("sitter.zig");
const builtin = @import("builtin");

pub const ErrWriter = std.fs.File.Writer;

/// Used to catch programming errors where a function fails to report
/// correctly that an error has occurred.
pub const Fatal = error{
    /// The error has been fully reported.
    Fatal,

    /// There was an error while outputting to the error writer.
    ErrIO,

    /// There war an error while outputting to the out writer.
    OutIO,
};

pub const FatalOOM = error{OutOfMemory} || Fatal;

pub const FatalShow = Fatal || error{
    /// The error has been reported but we should also print the
    /// interface of the template we are extending.
    FatalShowInterface,
};

pub const FatalShowOOM = error{OutOfMemory} || FatalShow;

pub fn report(
    writer: ErrWriter,
    template_name: []const u8,
    template_path: []const u8,
    bad_node: sitter.Node,
    html: []const u8,
    comptime error_code: []const u8,
    comptime title: []const u8,
    comptime msg: []const u8,
) Fatal {
    try header(writer, title, msg);
    const error_line = comptime "[" ++ error_code ++ "]";
    try diagnostic(writer, template_name, template_path, error_line, bad_node, html);
    return error.Fatal;
}

pub fn diagnostic(
    writer: ErrWriter,
    template_name: []const u8,
    template_path: []const u8,
    comptime note_line: []const u8,
    node: sitter.Node,
    html: []const u8,
) error{ErrIO}!void {
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

    writer.print(
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
    }) catch return error.ErrIO;
}

pub fn header(
    writer: ErrWriter,
    comptime title: []const u8,
    comptime msg: []const u8,
) error{ErrIO}!void {
    writer.print(
        \\
        \\---------- {s} ----------
        \\
    , .{title}) catch return error.ErrIO;
    writer.print(msg, .{}) catch return error.ErrIO;
    writer.print("\n", .{}) catch return error.ErrIO;
}

pub fn fatal(
    writer: ErrWriter,
    comptime fmt: []const u8,
    args: anytype,
) Fatal {
    writer.print(fmt, args) catch return error.ErrIO;
    return error.ErrIO;
}
