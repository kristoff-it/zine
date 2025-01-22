pub const context = @import("context.zig");
pub const highlight = @import("highlight.zig");
pub const StringTable = @import("StringTable.zig");
pub const PathTable = @import("PathTable.zig");
pub const fatal = @import("fatal.zig");

const std = @import("std");

pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    const separator = '/';

    // Find first non-empty path index.
    const first_path_index = blk: {
        for (paths, 0..) |path, index| {
            if (path.len == 0) continue else break :blk index;
        }

        // All paths provided were empty, so return early.
        return &[0]u8{};
    };

    // Calculate length needed for resulting joined path buffer.
    const total_len = blk: {
        var sum: usize = paths[first_path_index].len;
        var prev_path = paths[first_path_index];
        std.debug.assert(prev_path.len > 0);
        var i: usize = first_path_index + 1;
        while (i < paths.len) : (i += 1) {
            const this_path = paths[i];
            if (this_path.len == 0) continue;
            const prev_sep = prev_path[prev_path.len - 1] == separator;
            const this_sep = this_path[0] == separator;
            sum += @intFromBool(!prev_sep and !this_sep);
            sum += if (prev_sep and this_sep) this_path.len - 1 else this_path.len;
            prev_path = this_path;
        }

        break :blk sum;
    };

    const buf = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buf);

    @memcpy(buf[0..paths[first_path_index].len], paths[first_path_index]);
    var buf_index: usize = paths[first_path_index].len;
    var prev_path = paths[first_path_index];
    std.debug.assert(prev_path.len > 0);
    var i: usize = first_path_index + 1;
    while (i < paths.len) : (i += 1) {
        const this_path = paths[i];
        if (this_path.len == 0) continue;
        const prev_sep = prev_path[prev_path.len - 1] == separator;
        const this_sep = this_path[0] == separator;
        if (!prev_sep and !this_sep) {
            buf[buf_index] = separator;
            buf_index += 1;
        }
        const adjusted_path = if (prev_sep and this_sep) this_path[1..] else this_path;
        @memcpy(buf[buf_index..][0..adjusted_path.len], adjusted_path);
        buf_index += adjusted_path.len;
        prev_path = this_path;
    }

    // No need for shrink since buf is exactly the correct size.
    return buf;
}

pub const DepWriter = struct {
    w: std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter) DepWriter {
        return .{ .w = writer };
    }

    pub fn writeTarget(dw: DepWriter, target: []const u8) !void {
        try dw.w.print("\n{s}:", .{target});
    }

    pub fn writePrereq(dw: DepWriter, prereq: []const u8) !void {
        try dw.w.print(" \"{s}\"", .{prereq});
    }
};
