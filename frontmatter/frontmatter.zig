const std = @import("std");
const json = std.json;

pub const Header = struct {
    title: []const u8 = "",
    draft: bool = false,
    custom: json.Value = .null,
};

pub fn parse(reader: anytype, arena: std.mem.Allocator) !Header {
    var json_string = std.ArrayList(u8).init(arena);

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var state: enum { start, body } = .start;

    while (true) : (fbs.reset()) {
        reader.streamUntilDelimiter(fbs.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => switch (state) {
                .start => return .{},
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
                    return .{};
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

    return json.parseFromSliceLeaky(Header, arena, json_string.items, .{});
}
