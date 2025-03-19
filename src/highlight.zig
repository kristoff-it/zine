const std = @import("std");
const syntax = @import("syntax");
const treez = @import("treez");
const tracy = @import("tracy");
const HtmlSafe = @import("superhtml").HtmlSafe;

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

var query_cache: syntax.QueryCache = .{
    .allocator = @import("main.zig").gpa,
    .mutex = std.Thread.Mutex{},
};

pub fn highlightCode(
    arena: std.mem.Allocator,
    lang_name: []const u8,
    code: []const u8,
    writer: anytype,
) !void {
    const zone = tracy.traceNamed(@src(), "highlightCode");
    defer zone.end();
    tracy.messageCopy(lang_name);

    // var cond = true;
    // if (cond) {
    //     _ = &cond;
    //     try writer.print("{s}", .{HtmlSafe{ .bytes = code }});
    //     return;
    // }
    //

    const lang = blk: {
        const query_zone = tracy.traceNamed(@src(), "syntax");
        defer query_zone.end();

        break :blk syntax.create_file_type(
            arena,
            lang_name,
            &query_cache,
        ) catch {
            const syntax_fallback_zone = tracy.traceNamed(@src(), "syntax fallback");
            defer syntax_fallback_zone.end();
            const fake_filename = try std.fmt.allocPrint(arena, "file.{s}", .{lang_name});
            break :blk try syntax.create_guess_file_type(arena, "", fake_filename, &query_cache);
        };
    };

    {
        const refresh_zone = tracy.traceNamed(@src(), "refresh");
        defer refresh_zone.end();
        try lang.refresh_full(code);
    }
    // we don't want to free any resource from the query cache
    // defer lang.destroy();

    const tree = lang.tree orelse return;
    const cursor = try treez.Query.Cursor.create();
    defer cursor.destroy();

    {
        const query_zone = tracy.traceNamed(@src(), "exec query");
        defer query_zone.end();
        cursor.execute(lang.query, tree.getRootNode());
    }

    const match_zone = tracy.traceNamed(@src(), "render");
    defer match_zone.end();

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
