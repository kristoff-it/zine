const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const log = std.log.scoped(.update_assets);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();
    var args_it = std.process.argsWithAllocator(gpa) catch oom();

    std.debug.assert(args_it.skip());
    const install_path = args_it.next() orelse {
        fatal("wrong invocation of asset installer", .{});
    };

    const install_dir = try std.fs.cwd().makeOpenPath(install_path, .{});

    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_impl.allocator();
    while (args_it.next()) |list_path| {
        _ = arena_impl.reset(.retain_capacity);
        const src = std.fs.cwd().readFileAlloc(
            arena,
            list_path,
            std.math.maxInt(u16),
        ) catch |err| {
            fatal("error while reading asset list '{s}': {s}", .{
                list_path,
                @errorName(err),
            });
        };
        updateAssetsFromList(gpa, src, list_path, install_dir);
    }
}

fn updateAssetsFromList(
    gpa: std.mem.Allocator,
    src: []const u8,
    asset_list_path: []const u8,
    install_dir: std.fs.Dir,
) void {
    _ = gpa;
    var it = std.mem.tokenizeScalar(u8, src, '\n');

    while (it.next()) |asset_src_path| {
        log.debug("asset src path: '{s}'", .{asset_src_path});

        const asset_install_path = it.next() orelse {
            fatal(
                "error: asset list '{s}' has wrong number of entries!\n",
                .{asset_list_path},
            );
        };
        log.debug("asset install path: '{s}'", .{asset_install_path});

        // TODO: see if this can be improved
        const result = std.fs.cwd().updateFile(
            asset_src_path,
            install_dir,
            asset_install_path,
            .{},
        ) catch |err| {
            fatal("error while updating asset '{s}': {s}", .{
                asset_src_path,
                @errorName(err),
            });
        };

        log.debug("asset was: {s}", .{@tagName(result)});
    }
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}
