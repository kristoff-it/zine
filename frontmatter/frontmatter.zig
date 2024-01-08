const std = @import("std");
const json = std.json;

pub fn parse(comptime Header: type, reader: anytype, arena: std.mem.Allocator) !Header {
    var json_string = std.ArrayList(u8).init(arena);

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var state: enum { start, body } = .start;

    while (true) : (fbs.reset()) {
        reader.streamUntilDelimiter(fbs.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => switch (state) {
                .start => return error.BadFrontMatter,
                .body => return error.BadFrontMatter,
            },
            else => return err,
        };

        const maybe_trimmed_dashes = std.mem.trimRight(u8, fbs.getWritten(), " \r");
        switch (state) {
            .start => {
                if (std.mem.eql(u8, maybe_trimmed_dashes, "---")) {
                    state = .body;
                } else {
                    return error.BadFrontMatter;
                }
            },

            .body => {
                if (std.mem.eql(u8, maybe_trimmed_dashes, "---")) {
                    break;
                } else {
                    try json_string.appendSlice(maybe_trimmed_dashes);
                }
            },
        }
    }

    var scanner = json.Scanner.initCompleteInput(arena, json_string.items);
    defer scanner.deinit();

    var diagnostics: json.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);

    return json.parseFromTokenSourceLeaky(Header, arena, &scanner, .{}) catch |err| {
        std.debug.print("Error while reading frontmatter: {s}\n line {}, col: {}\n", .{
            @errorName(err), diagnostics.getLine(), diagnostics.getColumn(),
        });

        return err;
    };
}
