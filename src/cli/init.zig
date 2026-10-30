const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const options = @import("options");
const tracy = @import("tracy");
const fatal = @import("../fatal.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.init);

const File = struct { path: []const u8, src: []const u8 };

pub fn init(io: Io, gpa: Allocator, args: []const []const u8) bool {
    _ = gpa;

    const cmd: Command = .parse(args);
    if (cmd.multilingual) @panic("TODO: multilingual init");

    const files: []const File = if (cmd.minimal) &minimal_files else &full_files;
    writeFiles(io, files);

    std.debug.print(
        \\
        \\Run `zine` to run the Zine development server.
        \\Run `zine release` to build your website in 'public/'.
        \\Run `zine help` for more commands and options.
        \\
        \\Read https://zine-ssg.io/docs/ to learn more about Zine.
        \\
    , .{});

    return false;
}

const minimal_files = [_]File{
    .{
        .path = ".zine.ziggy-schema",
        .src = @embedFile("../schemas/zine.ziggy-schema"),
    },
    .{
        .path = "zine.ziggy",
        .src = std.fmt.comptimePrint(@embedFile("init/minimal/zine.ziggy"), .{options.version}),
    },
    .{
        .path = "content/.smd.ziggy-schema",
        .src = @embedFile("../schemas/page.ziggy-schema"),
    },
    .{
        .path = "content/index.smd",
        .src = @embedFile("init/minimal/content/index.smd"),
    },
    .{
        .path = "layouts/index.shtml",
        .src = @embedFile("init/minimal/layouts/index.shtml"),
    },
};

const full_files = [_]File{
    .{
        .path = ".zine.ziggy-schema",
        .src = @embedFile("../schemas/zine.ziggy-schema"),
    },
    .{
        .path = "zine.ziggy",
        .src = std.fmt.comptimePrint(@embedFile("init/full/zine.ziggy"), .{options.version}),
    },
    .{
        .path = "content/.smd.ziggy-schema",
        .src = @embedFile("../schemas/page.ziggy-schema"),
    },
    .{
        .path = "content/index.smd",
        .src = @embedFile("init/full/content/index.smd"),
    },
    .{
        .path = "content/about.smd",
        .src = @embedFile("init/full/content/about.smd"),
    },
    .{
        .path = "content/blog/index.smd",
        .src = @embedFile("init/full/content/blog/index.smd"),
    },
    .{
        .path = "content/blog/first-post/index.smd",
        .src = @embedFile("init/full/content/blog/first-post/index.smd"),
    },
    .{
        .path = "content/blog/first-post/fanzine.jpg",
        .src = @embedFile("init/full/content/blog/first-post/fanzine.jpg"),
    },
    .{
        .path = "content/blog/second-post.smd",
        .src = @embedFile("init/full/content/blog/second-post.smd"),
    },
    .{
        .path = "content/devlog/index.smd",
        .src = @embedFile("init/full/content/devlog/index.smd"),
    },
    .{
        .path = "content/devlog/1990.smd",
        .src = @embedFile("init/full/content/devlog/1990.smd"),
    },
    .{
        .path = "content/devlog/1989.smd",
        .src = @embedFile("init/full/content/devlog/1989.smd"),
    },
    .{
        .path = "layouts/index.shtml",
        .src = @embedFile("init/full/layouts/index.shtml"),
    },
    .{
        .path = "layouts/page.shtml",
        .src = @embedFile("init/full/layouts/page.shtml"),
    },
    .{
        .path = "layouts/post.shtml",
        .src = @embedFile("init/full/layouts/post.shtml"),
    },
    .{
        .path = "layouts/blog.shtml",
        .src = @embedFile("init/full/layouts/blog.shtml"),
    },
    .{
        .path = "layouts/blog.xml",
        .src = @embedFile("init/full/layouts/blog.xml"),
    },
    .{
        .path = "layouts/devlog.shtml",
        .src = @embedFile("init/full/layouts/devlog.shtml"),
    },
    .{
        .path = "layouts/devlog.xml",
        .src = @embedFile("init/full/layouts/devlog.xml"),
    },
    .{
        .path = "layouts/devlog-archive.shtml",
        .src = @embedFile("init/full/layouts/devlog-archive.shtml"),
    },
    .{
        .path = "layouts/templates/base.shtml",
        .src = @embedFile("init/full/layouts/templates/base.shtml"),
    },
    .{
        .path = "assets/style.css",
        .src = @embedFile("init/full/assets/style.css"),
    },
    .{
        .path = "assets/highlight.css",
        .src = @embedFile("init/full/assets/highlight.css"),
    },
    .{
        .path = "assets/under-construction.gif",
        .src = @embedFile("init/full/assets/under-construction.gif"),
    },
    .{
        .path = "assets/render-mathtex.js",
        .src = @embedFile("init/full/assets/render-mathtex.js"),
    },
    .{
        .path = "assets/Temml-Local.css",
        .src = @embedFile("init/full/assets/Temml-Local.css"),
    },
    .{
        .path = "assets/Temml.woff2",
        .src = @embedFile("init/full/assets/Temml.woff2"),
    },
    .{
        .path = "assets/temml.min.js",
        .src = @embedFile("init/full/assets/temml.min.js"),
    },
};

fn writeFiles(io: Io, files: []const File) void {
    for (files) |file| {
        const dirname = std.fs.path.dirnamePosix(file.path);
        const basename = std.fs.path.basenamePosix(file.path);

        const base_dir = if (dirname) |dn|
            Io.Dir.cwd().createDirPathOpen(io, dn, .{}) catch |err| fatal.dir(dn, err)
        else
            Io.Dir.cwd();

        const f = base_dir.createFile(io, basename, .{
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
        var file_writer = f.writer(io, &.{});
        file_writer.interface.writeAll(file.src) catch |err| fatal.file(file.path, err);
    }
}

const Command = struct {
    multilingual: bool,
    minimal: bool,
    fn parse(args: []const []const u8) Command {
        var multilingual: ?bool = null;
        var minimal: ?bool = null;
        for (args) |a| {
            if (std.mem.eql(u8, a, "--multilingual")) {
                multilingual = true;
            }

            if (std.mem.eql(u8, a, "--minimal")) {
                minimal = true;
            }

            if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
                fatal.msg(
                    \\Usage: zine init [OPTIONS]
                    \\
                    \\Command specific options:
                    \\  --minimal        Setup a minimal website (single page, no assets)
                    \\  --multilingual   Setup a sample multilingual website
                    \\
                    \\General Options:
                    \\  --help, -h       Print command specific usage
                    \\
                    \\
                , .{});
            }
        }

        return .{
            .multilingual = multilingual orelse false,
            .minimal = minimal orelse false,
        };
    }
};
