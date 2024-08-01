const AnsiRenderer = @This();
const std = @import("std");

state: State = .normal,
current_style: Style = .{},
g0_charset: Charset = .ascii,

const State = union(enum) {
    normal,
    escape,
    csi: ?u32,
    gzd4,
};

const Style = struct {
    bold: bool = false,
    dim: bool = false,
    foreground: ?Color = null,

    const Color = enum {
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
    };

    fn print(style: Style, out: anytype, open: bool) !void {
        comptime var fields: [std.meta.fields(Style).len]std.builtin.Type.StructField = undefined;
        @memcpy(&fields, std.meta.fields(Style));
        comptime std.mem.reverse(std.builtin.Type.StructField, &fields);
        const FieldEnum = std.meta.FieldEnum(Style);
        inline for (fields) |field| {
            const value = @field(style, field.name);
            const tag: ?std.meta.Tuple(&.{ []const u8, ?[]const u8 }) = switch (@field(FieldEnum, field.name)) {
                .bold => if (value) .{ "b", null } else null,
                .dim => if (value) .{ "span", "style=\"filter: brightness(75%)\"" } else null,
                .foreground => if (value) |color| .{ "span", switch (color) {
                    inline else => |c| "style=\"color: " ++ @tagName(c) ++ "\"",
                } } else null,
            };

            if (tag) |t| {
                if (open) {
                    if (t[1]) |attrs| {
                        try out.print("<{s} {s}>", .{ t[0], attrs });
                    } else {
                        try out.print("<{s}>", .{t[0]});
                    }
                } else {
                    try out.print("</{s}>", .{t[0]});
                }
            }
        }
    }

    fn printOpen(style: Style, out: anytype) !void {
        try style.print(out, true);
    }

    fn printClose(style: Style, out: anytype) !void {
        try style.print(out, false);
    }
};

const Charset = enum {
    ascii,
    vt100_line_drawing,
};

pub fn renderSlice(allocator: std.mem.Allocator, src: []const u8) ![]const u8 {
    var fbs = std.io.fixedBufferStream(src);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var renderer: AnsiRenderer = .{};
    try renderer.render(fbs.reader(), out.writer());

    return try out.toOwnedSlice();
}

fn render(renderer: *AnsiRenderer, reader: anytype, writer: anytype) !void {
    try renderer.current_style.printOpen(writer);

    while (true) {
        const char = reader.readByte() catch break;

        switch (renderer.state) {
            .normal => switch (char) {
                '\x1b' => renderer.state = .escape,
                else => switch (renderer.g0_charset) {
                    .ascii => try writer.writeByte(char),
                    .vt100_line_drawing => {
                        _ = try writer.write(switch (char) {
                            'j' => "┘",
                            'k' => "┐",
                            'l' => "┌",
                            'm' => "└",
                            'n' => "┼",
                            'q' => "─",
                            't' => "├",
                            'u' => "┤",
                            'v' => "┴",
                            'w' => "┬",
                            'x' => "│",
                            else => "�",
                        });
                    },
                },
            },
            .escape => switch (char) {
                '[' => renderer.state = .{ .csi = null },
                '(' => renderer.state = .gzd4,
                else => renderer.state = .normal,
            },
            .csi => |payload| switch (char) {
                '0'...'9' => {
                    if (payload == null) {
                        renderer.state.csi = char - '0';
                    } else {
                        renderer.state.csi.? *= 10;
                        renderer.state.csi.? += char - '0';
                    }
                },
                'm' => {
                    const n = payload orelse 0;

                    try renderer.current_style.printClose(writer);

                    switch (n) {
                        0 => renderer.current_style = .{},
                        1 => renderer.current_style.bold = true,
                        2 => renderer.current_style.dim = true,
                        30...37 => renderer.current_style.foreground = @enumFromInt(n - 30),
                        else => {},
                    }

                    try renderer.current_style.printOpen(writer);

                    renderer.state = .normal;
                },
                else => renderer.state = .normal,
            },
            .gzd4 => {
                switch (char) {
                    'B' => renderer.g0_charset = .ascii,
                    '0' => renderer.g0_charset = .vt100_line_drawing,
                    else => {},
                }
                renderer.state = .normal;
            },
        }
    }

    try renderer.current_style.printClose(writer);
}
