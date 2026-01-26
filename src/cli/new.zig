const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

const DateTime = @import("../context/DateTime.zig");
const fatal = @import("../fatal.zig");
const root = @import("../root.zig");

const log = std.log.scoped(.init);

pub fn new_page(gpa: Allocator, args: []const []const u8) bool {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cfg, _ = root.Config.load(gpa);
    const cmd: Command = .parse(gpa, args, cfg.Site.default_frontmatter);

    var date_str: std.Io.Writer.Allocating = .init(gpa);
    errdefer date_str.deinit();

    DateTime.initNow()._inst.time().strftime(&date_str.writer, "%Y-%m-%dT%H:%M:%S%z") catch |err| {
        fatal.msg("error while trying to set date: {s}\n", .{@errorName(err)});
    };
    const draft_str = if (cmd.draft) "true" else "false";

    var tags_list: ArrayList(u8) = .empty;
    try tags_list.append(gpa, '[');
    if (cmd.tags.len > 0) {
        for (cmd.tags) |tag| {
            try tags_list.append(gpa, '"');
            try tags_list.appendSlice(gpa, tag);
            try tags_list.appendSlice(gpa, "\",");
        }
        // pop off the last trailing comma
        _ = tags_list.pop();
    }
    try tags_list.append(gpa, ']');

    var alias_list: ArrayList(u8) = .empty;
    try alias_list.append(gpa, '[');
    if (cmd.aliases.len > 0) {
        for (cmd.aliases) |alias| {
            try alias_list.append(gpa, '"');
            try alias_list.appendSlice(gpa, alias);
            try alias_list.appendSlice(gpa, "\",");
        }
        // pop off the last trailing comma
        _ = alias_list.pop();
    }
    try alias_list.append(gpa, ']');

    const frontmatter = try std.fmt.allocPrint(gpa,
        \\---
        \\.title = "{s}",
        \\.date = @date("{s}"),
        \\.author = "{s}",
        \\.layout = "{s}",
        \\.draft = {s},
        \\.description = "{s}",
        \\.tags = {s},
        \\.aliases = {s},
        \\---
    , .{ cmd.title, try date_str.toOwnedSlice(), cmd.author, cmd.layout, draft_str, cmd.description, tags_list.items, alias_list.items });

    // create file and populate frontmatter according to what is in the command
    // NOTE: this requires including the `.smd` file extension for a non-directory path,
    // it is not appended automatically.
    const out_file = switch (cmd.file_path[cmd.file_path.len - 1]) {
        '/' => dir_blk: {
            std.fs.cwd().makeDir(cmd.file_path) catch |err| {
                fatal.msg("error while creating output file directory: {s}\n{s}\n", .{ cmd.file_path, @errorName(err) });
            };
            break :dir_blk try std.mem.concat(gpa, u8, &.{ cmd.file_path, "index.smd" });
        },
        else => cmd.file_path,
    };
    const new_file = std.fs.cwd().createFile(out_file, .{ .exclusive = true }) catch |err| {
        fatal.msg("error while creating output file: {s}\n{s}\n", .{ out_file, @errorName(err) });
    };
    defer new_file.close();
    new_file.writeAll(frontmatter) catch |err| fatal.file(
        out_file,
        err,
    );

    return false;
}

const Command = struct {
    file_path: []const u8,
    title: []const u8,
    description: []const u8,
    author: []const u8,
    tags: []const []const u8,
    aliases: []const []const u8,
    draft: bool,
    layout: []const u8,
    fn parseCommaArray(gpa: Allocator, arg: []const u8) []const []const u8 {
        errdefer |err| switch (err) {
            error.OutOfMemory => fatal.oom(),
        };

        if (arg.len <= 0) {
            fatal.msg("error: missing argument to '--tags='", .{});
        }

        if (std.mem.indexOfScalar(u8, arg, ',') == null) {
            return &.{arg};
        } else {
            var tagArr: std.ArrayList([]const u8) = .empty;
            defer tagArr.deinit(gpa);

            var tagIt = std.mem.tokenizeScalar(u8, arg, ',');
            while (tagIt.next()) |tag| {
                try tagArr.append(gpa, tag);
            }

            return try tagArr.toOwnedSlice(gpa);
        }
    }

    fn parse(gpa: Allocator, args: []const []const u8, default_config: ?DefaultFrontmatter) Command {
        var file_path: []const u8 = undefined;
        var title: ?[]const u8 = default_config.?.title;
        var description: ?[]const u8 = default_config.?.description;
        var author: ?[]const u8 = default_config.?.author;
        var tags: ?[]const []const u8 = default_config.?.tags;
        var aliases: ?[]const []const u8 = default_config.?.aliases;
        var draft: ?bool = default_config.?.draft;
        var layout: ?[]const u8 = default_config.?.layout;

        if (args.len <= 0) {
            fatal.msg("Must provide a file path to 'zine new'", .{});
        }

        // In order:
        // 1. attempt to parse values for all fields above from CLI args
        // 2. for any that are still unpopulated, fall back to values from the config file
        // set above
        // 3. finally, set to a reasonable default (e.g. empty string) if neither of the above resolves
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];

            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                helpMsg();
            }

            if (std.mem.startsWith(u8, arg, "--title=")) {
                title = arg["--title=".len..];
            } else if (std.mem.eql(u8, arg, "--title")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--title'",
                    .{},
                );
                title = args[idx];
            } else if (std.mem.startsWith(u8, arg, "--description=")) {
                description = arg["--description=".len..];
            } else if (std.mem.startsWith(u8, arg, "--description")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--description'",
                    .{},
                );
                description = args[idx];
            } else if (std.mem.startsWith(u8, arg, "--author=")) {
                author = arg["--author=".len..];
            } else if (std.mem.startsWith(u8, arg, "--author")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--author'",
                    .{},
                );
                author = args[idx];
            } else if (std.mem.startsWith(u8, arg, "--layout=")) {
                layout = arg["--layout=".len..];
            } else if (std.mem.startsWith(u8, arg, "--layout")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--layout'",
                    .{},
                );
                layout = args[idx];
            } else if (std.mem.startsWith(u8, arg, "--tags=")) {
                // tags and aliases are comma separated
                const suffix = arg["--tags=".len..];
                tags = parseCommaArray(gpa, suffix);
            } else if (std.mem.startsWith(u8, arg, "--tags")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--tags'",
                    .{},
                );
                tags = parseCommaArray(gpa, args[idx]);
            } else if (std.mem.startsWith(u8, arg, "--aliases=")) {
                // tags and aliases are comma separated
                const suffix = arg["--aliases=".len..];
                aliases = parseCommaArray(gpa, suffix);
            } else if (std.mem.startsWith(u8, arg, "--aliases")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '--tags'",
                    .{},
                );
                aliases = parseCommaArray(gpa, args[idx]);
            } else if (std.mem.startsWith(u8, arg, "--draft")) {
                // NOTE: chose to just have this be present as a boolean flag rather than
                // explicitly providing a vaule to the option.
                draft = true;
            }

            // Last argument must be the file path
            file_path = arg;
        }

        return .{
            .file_path = file_path,
            .title = title orelse "Untitled",
            .description = description orelse "",
            .author = author orelse "",
            .tags = tags orelse &.{},
            .aliases = aliases orelse &.{},
            .draft = draft orelse true,
            // Default from `zine init`
            .layout = layout orelse "post.shtml",
        };
    }

    fn helpMsg() void {
        fatal.msg(
            \\Create a new page at the given path with frontmatter pre-filled. Frontmatter will be populated using, in prioritized order:
            \\  1. CLI options for the invocation of this command
            \\  2. Values set in the `.default_frontmatter` field of the site's `zine.ziggy` config file
            \\  3. A standard default
            \\
            \\Usage: zine new [OPTIONS] [PATH]
            \\
            \\Command specific options:
            \\  --title          Set the title for the new page
            \\  --description    Set the "description" frontmatter field for the new page
            \\  --author         Set the "author" frontmatter field for the new page
            \\  --tags           Set the "tags" frontmatter field for the new page, provide a comma separated list of tags.
            \\  --aliases        Set the "aliases" frontmatter field for the new page, provide a comma separated list of tags.
            \\  --draft          Set the "draft" frontmatter field for the new page
            \\  --layout         Set the "layout" frontmatter field for the new page
            \\
            \\Positional Arguments:
            \\  PATH (required): the path to the new file to create. May be an explicit
            \\    full file path, or a directory path with a trailing '/' character. If the latter
            \\    is provided, an `index.smd` file will be automatically created in that directory
            \\
            \\General Options:
            \\  --help, -h       Print command specific usage
            \\
            \\Examples:
            \\  `zine new --title "A New Post" --tags "tag1,tag2" --draft=true content/blog/new-post.smd`
            \\  `zine new --title "Another New Post" --layout "post.shtml" content/blog/another-new-post/`
        , .{});
    }
};

pub const DefaultFrontmatter = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    author: ?[]const u8 = null,
    tags: ?[]const []const u8 = null,
    aliases: ?[]const []const u8 = null,
    draft: ?bool = null,
    layout: []const u8,
};
