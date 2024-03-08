const std = @import("std");
const syntax = @import("syntax");
const treez = @import("treez");

const log = std.log.scoped(.highlight);

pub const DotsToSpaces = struct {
    bytes: []const u8,

    pub fn format(
        self: DotsToSpaces,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        for (self.bytes) |b| {
            switch (b) {
                '.' => try out_stream.writeAll(" "),
                else => try out_stream.writeByte(b),
            }
        }
    }
};
pub const HtmlSafe = struct {
    bytes: []const u8,

    pub fn format(
        self: HtmlSafe,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        for (self.bytes) |b| {
            switch (b) {
                '>' => try out_stream.writeAll("&gt;"),
                '<' => try out_stream.writeAll("&lt;"),
                else => try out_stream.writeByte(b),
            }
        }
    }
};

pub fn highlightCode(
    arena: std.mem.Allocator,
    lang_name: []const u8,
    code: []const u8,
    path: []const u8,
    line: u32,
    col: u32,
    writer: anytype,
) !void {
    const lang = syntax.create_file_type(arena, code, lang_name) catch {
        std.debug.print(
            \\{s}:{}:{}
            \\Unable to find highlighting queries for language '{s}'
            \\
        ,
            .{ path, line, col, lang_name },
        );
        std.process.exit(1);
    };

    const tree = lang.tree orelse {
        std.debug.print(
            \\{s}:{}:{}
            \\Unable to parse the code block
            \\
        ,
            .{ path, line, col },
        );
        std.process.exit(1);
    };

    const cursor = try treez.Query.Cursor.create();
    defer cursor.destroy();
    cursor.execute(lang.query, tree.getRootNode());
    var print_cursor: usize = 0;
    while (cursor.nextMatch()) |match| {
        var idx: usize = 0;
        for (match.captures()) |capture| {
            const capture_name = lang.query.getCaptureNameForId(capture.id);
            const range = capture.node.getRange();

            if (range.start_byte < print_cursor) continue;

            if (range.start_byte > print_cursor) {
                try writer.print("{s}", .{HtmlSafe{ .bytes = code[print_cursor..range.start_byte] }});
            }

            try writer.print(
                \\<span class="{s}">{s}</span>
            , .{
                DotsToSpaces{ .bytes = capture_name },
                HtmlSafe{ .bytes = code[range.start_byte..range.end_byte] },
            });

            print_cursor = range.end_byte;
            idx += 1;
        }
    }

    if (code.len > print_cursor) {
        try writer.print("{s}", .{HtmlSafe{ .bytes = code[print_cursor..] }});
    }
}
