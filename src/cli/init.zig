const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.init);

pub fn init(gpa: Allocator, args: []const []const u8) void {
    const cmd: Command = .parse(args);
    if (cmd.multilingual) @panic("TODO: multilingual init");

    // zine.ziggy
    blk: {
        const zine_ziggy =
            \\Site {{
            \\    .title = "{0s}",
            \\    .host_url = "https://{0s}",
            \\    .content_dir_path = "content",
            \\    .layouts_dir_path = "layouts",
            \\    .assets_dir_path = "assets",
            \\}}
            \\
        ;

        const name = std.fs.path.basename(
            std.process.getCwdAlloc(gpa) catch "sample-site.com",
        );
        const f = std.fs.cwd().createFile("zine.ziggy", .{
            .exclusive = true,
        }) catch |err| switch (err) {
            else => fatal.file("zine.ziggy", err),
            error.PathAlreadyExists => {
                std.debug.print(
                    "WARNING: 'zine.ziggy' already exists, skipping.\n",
                    .{},
                );
                break :blk;
            },
        };
        std.debug.print("Created: zine.ziggy\n", .{});
        f.writer().print(
            zine_ziggy,
            .{name},
        ) catch |err| fatal.file("zine.ziggy", err);
    }

    const File = struct { path: []const u8, src: []const u8 };
    const files = [_]File{
        .{
            .path = "content/index.smd",
            .src = @embedFile("init/content/index.smd"),
        },
        .{
            .path = "content/about.smd",
            .src = @embedFile("init/content/about.smd"),
        },
        .{
            .path = "content/blog/first-post.smd",
            .src = @embedFile("init/content/blog/first-post.smd"),
        },
        .{
            .path = "content/blog/second-post/index.smd",
            .src = @embedFile("init/content/blog/second-post/index.smd"),
        },
        .{
            .path = "layouts/index.shtml",
            .src = @embedFile("init/layouts/index.shtml"),
        },
        .{
            .path = "layouts/page.shtml",
            .src = @embedFile("init/layouts/page.shtml"),
        },
        .{
            .path = "layouts/templates/base.shtml",
            .src = @embedFile("init/layouts/templates/base.shtml"),
        },
    };

    for (files) |file| {
        const dirname = std.fs.path.dirnamePosix(file.path);
        const basename = std.fs.path.basenamePosix(file.path);

        const base_dir = if (dirname) |dn|
            std.fs.cwd().makeOpenPath(dn, .{}) catch |err| fatal.dir(dn, err)
        else
            std.fs.cwd();

        const f = base_dir.createFile(basename, .{
            .exclusive = true,
        }) catch |err| switch (err) {
            else => fatal.file(basename, err),
            error.PathAlreadyExists => {
                std.debug.print(
                    "WARNING: '{s}' already exists, skipping.\n",
                    .{file.path},
                );
                continue;
            },
        };
        std.debug.print("Created: {s}\n", .{file.path});
        f.writeAll(file.src) catch |err| fatal.file(file.path, err);
    }

    std.debug.print(
        \\
        \\Run `zine serve` to run the Zine development server.
        \\Run `zine release` to build your website in 'public/'.
        \\Run `zine help` for more commands and options.
        \\
        \\Edit 'zine.ziggy' to change your website's main config.
        \\Read https://zine-ssg.io/documentation/ to learn more about Zine.
        \\
    , .{});
}

const Command = struct {
    multilingual: bool,
    fn parse(args: []const []const u8) Command {
        var multilingual: ?bool = null;
        for (args) |a| {
            if (std.mem.eql(u8, a, "--multilingual")) {
                multilingual = true;
            }

            if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
                fatal.msg(
                    \\Usage: zine init [OPTIONS]
                    \\
                    \\Command specific options:
                    \\  --multilingual   Setup a sample multilingual website
                    \\
                    \\General Options:
                    \\  --help, -h       Print command specific usage
                    \\
                    \\
                , .{});
            }
        }

        return .{ .multilingual = multilingual orelse false };
    }
};
