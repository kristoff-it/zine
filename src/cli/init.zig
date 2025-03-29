const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.init);

pub fn init(gpa: Allocator, args: []const []const u8) bool {
    _ = gpa;

    const cmd: Command = .parse(args);
    if (cmd.multilingual) @panic("TODO: multilingual init");

    const File = struct { path: []const u8, src: []const u8 };
    const files = [_]File{
        .{
            .path = "zine.ziggy",
            .src = @embedFile("init/zine.ziggy"),
        },
        .{
            .path = "content/index.smd",
            .src = @embedFile("init/content/index.smd"),
        },
        .{
            .path = "content/about.smd",
            .src = @embedFile("init/content/about.smd"),
        },
        .{
            .path = "content/blog/index.smd",
            .src = @embedFile("init/content/blog/index.smd"),
        },
        .{
            .path = "content/blog/first-post/index.smd",
            .src = @embedFile("init/content/blog/first-post/index.smd"),
        },
        .{
            .path = "content/blog/first-post/fanzine.jpg",
            .src = @embedFile("init/content/blog/first-post/fanzine.jpg"),
        },
        .{
            .path = "content/blog/second-post.smd",
            .src = @embedFile("init/content/blog/second-post.smd"),
        },
        .{
            .path = "content/devlog/index.smd",
            .src = @embedFile("init/content/devlog/index.smd"),
        },
        .{
            .path = "content/devlog/1990.smd",
            .src = @embedFile("init/content/devlog/1990.smd"),
        },
        .{
            .path = "content/devlog/1989.smd",
            .src = @embedFile("init/content/devlog/1989.smd"),
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
            .path = "layouts/post.shtml",
            .src = @embedFile("init/layouts/post.shtml"),
        },
        .{
            .path = "layouts/blog.shtml",
            .src = @embedFile("init/layouts/blog.shtml"),
        },
        .{
            .path = "layouts/blog.xml",
            .src = @embedFile("init/layouts/blog.xml"),
        },
        .{
            .path = "layouts/devlog.shtml",
            .src = @embedFile("init/layouts/devlog.shtml"),
        },
        .{
            .path = "layouts/devlog.xml",
            .src = @embedFile("init/layouts/devlog.xml"),
        },
        .{
            .path = "layouts/devlog-archive.shtml",
            .src = @embedFile("init/layouts/devlog-archive.shtml"),
        },
        .{
            .path = "layouts/templates/base.shtml",
            .src = @embedFile("init/layouts/templates/base.shtml"),
        },
        .{
            .path = "assets/style.css",
            .src = @embedFile("init/assets/style.css"),
        },
        .{
            .path = "assets/highlight.css",
            .src = @embedFile("init/assets/highlight.css"),
        },
        .{
            .path = "assets/under-construction.gif",
            .src = @embedFile("init/assets/under-construction.gif"),
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
        \\Read https://zine-ssg.io/docs/ to learn more about Zine.
        \\
    , .{});

    return false;
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
