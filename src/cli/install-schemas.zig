const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const root = @import("../root.zig");
const fatal = @import("../fatal.zig");

const config_schema = @embedFile("../schemas/zine.ziggy-schema");
const page_schema = @embedFile("../schemas/page.ziggy-schema");

pub fn install_schemas(io: Io, gpa: Allocator, args: []const []const u8) bool {
    const cmd = Command.parse(args) catch fatal.oom();
    const cfg, const base_dir_path = root.Config.load(io, gpa, cmd.search);

    const base_dir = Io.Dir.cwd().openDir(io, base_dir_path, .{}) catch |err| {
        fatal.dir(base_dir_path, err);
    };

    writeFile(io, base_dir, ".zine.ziggy-schema", config_schema);

    switch (cfg.site) {
        .simple => |s| {
            const content_dir = base_dir.createDirPathOpen(io, s.content_dir_path, .{}) catch |err| {
                fatal.dir(s.content_dir_path, err);
            };

            const content_schema_path = std.fs.path.join(gpa, &.{
                s.content_dir_path,
                ".smd.ziggy-schema",
            }) catch fatal.oom();

            writeFile(io, content_dir, content_schema_path, page_schema);
        },
        .multilingual => |m| {
            for (m.locales) |l| {
                const content_dir = base_dir.createDirPathOpen(io, l.content_dir_path, .{}) catch |err| {
                    fatal.dir(l.content_dir_path, err);
                };

                const content_schema_path = std.fs.path.join(gpa, &.{
                    l.content_dir_path,
                    ".smd.ziggy-schema",
                }) catch fatal.oom();

                writeFile(io, content_dir, content_schema_path, page_schema);
            }
        },
    }

    std.debug.print("\n", .{});
    return false;
}

fn writeFile(io: Io, dir: Io.Dir, full_path: []const u8, bytes: []const u8) void {
    const schema = dir.createFile(io, std.fs.path.basename(full_path), .{ .truncate = true }) catch |err| {
        fatal.msg("unable to create '{s}': {t}", .{ full_path, err });
    };
    defer schema.close(io);

    schema.writeStreamingAll(io, bytes) catch |err| {
        fatal.msg("unable to write to '{s}': {t}", .{ full_path, err });
    };

    std.debug.print("WRITTEN: {s}\n", .{full_path});
}

pub const Command = struct {
    search: root.Config.Search,

    pub fn parse(args: []const []const u8) !Command {
        var config_path: ?[]const u8 = null;

        const eql = std.mem.eql;
        const startsWith = std.mem.startsWith;
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                fatal.msg(help_message, .{});
            } else if (eql(u8, arg, "-c") or eql(u8, arg, "--config")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '{s}'",
                    .{arg},
                );
                config_path = args[idx];
            } else if (startsWith(u8, arg, "--config=")) {
                config_path = arg["--config=".len..];
            } else {
                fatal.msg("error: unexpected cli argument '{s}'\n", .{arg});
            }
        }

        return .{
            .search = if (config_path) |p| .{ .path = p } else .auto,
        };
    }
};

const help_message =
    \\Usage: zine install-schemas [OPTIONS]
    \\
    \\Installs up-to-date Ziggy Schema files to be used by the Ziggy
    \\Language Server to provide schema checking, autocomplete and
    \\documentation.
    \\
    \\Command specific options:
    \\  --config, -c FILE  Use a custom config file instead of searching
    \\                     recursively upwards for a 'zine.ziggy' file
    \\  --help, -h         Show this help menu
    \\
    \\
;
