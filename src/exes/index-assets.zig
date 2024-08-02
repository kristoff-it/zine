const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const log = std.log.scoped(.index_assets);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();
    var args_it = std.process.argsWithAllocator(gpa) catch oom();

    std.debug.assert(args_it.skip());
    const asset_index_dir_path = args_it.next() orelse unreachable;
    log.debug("index path: '{s}'", .{asset_index_dir_path});

    std.fs.cwd().deleteTree(asset_index_dir_path) catch |err| {
        fatal("unable to clear asset index directory '{s}': {s}", .{
            asset_index_dir_path,
            @errorName(err),
        });
    };

    const asset_index_dir = try std.fs.cwd().makeOpenPath(asset_index_dir_path, .{});

    var buf = std.ArrayList(u8).init(gpa);
    while (args_it.next()) |name| {
        log.debug("asset name: '{s}'", .{name});

        const asset_path = args_it.next() orelse {
            fatal("error: invocation of asset-indexer has wrong number of args!\n", .{});
        };
        log.debug("asset path: '{s}'", .{asset_path});
        const install_path = args_it.next() orelse {
            fatal("error: invocation of asset-indexer has wrong number of args!\n", .{});
        };
        log.debug("asset install path: '{s}'", .{install_path});

        for (name) |c| if (c == std.fs.path.sep) {
            fatal("TODO: support complex asset names", .{});
        };

        const file = try asset_index_dir.createFile(name, .{
            .read = true,
            .truncate = false,
        });
        defer file.close();

        log.debug("stale content detected: '{s}'", .{buf.items});
        try file.setEndPos(asset_path.len);
        try file.seekTo(0);

        {
            buf.clearRetainingCapacity();
            const w = buf.writer();
            try w.writeAll(asset_path);
            if (!std.mem.eql(u8, install_path, "null")) {
                try w.writeAll("\n");
                try w.writeAll(install_path);
            }
        }

        try file.writeAll(buf.items);
    }
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}
