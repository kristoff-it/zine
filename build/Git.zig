const Git = @This();

const std = @import("std");
const builtin = @import("builtin");
const ziggy = @import("ziggy");
const zeit = @import("zeit");
const Allocator = std.mem.Allocator;

_in_repo: bool = false,

commit_hash: []const u8 = undefined,
commit_date: struct {
    unix: i64 = undefined,

    const Self = @This();
    pub const ziggy_options = struct {
        pub fn stringify(
            value: Self,
            opts: ziggy.serializer.StringifyOptions,
            indent_level: usize,
            depth: usize,
            writer: anytype,
        ) !void {
            _ = opts;
            _ = indent_level;
            _ = depth;

            const date = zeit.instant(.{
                .source = .{ .unix_timestamp = value.unix },
            }) catch unreachable;

            try writer.print("@date(\"", .{});
            date.time().gofmt(writer, "2006-01-02T15:04:05") catch unreachable;
            try writer.print("\")", .{});
        }
    };
} = undefined,
commit_message: []const u8 = undefined,
author_name: []const u8 = undefined,
author_email: []const u8 = undefined,

_tag: ?[]const u8 = null,
_branch: ?[]const u8 = null,

pub const gitCommitHashLen = 40;

pub fn init(gpa: Allocator, path: []const u8) !Git {
    var git = Git{};

    var p = path;
    const git_dir = while (true) {
        var dir = try std.fs.openDirAbsolute(p, .{});
        defer dir.close();
        break dir.openDir(".git", .{}) catch |err| switch (err) {
            error.FileNotFound => {
                p = std.fs.path.dirname(p) orelse return git;
                continue;
            },
            else => return err,
        };
    };

    git._in_repo = true;

    const head = readHead(gpa, git_dir) catch return Git{};
    switch (head) {
        .commit_hash => |hash| git.commit_hash = hash,
        .branch => |branch| {
            git._branch = branch;
            git.commit_hash = readCommitOfBranch(gpa, git_dir, branch) catch return Git{};
        },
    }

    git._tag = getTagForCommitHash(gpa, git_dir, git.commit_hash) catch return Git{};

    git.setAdditionalMetadata(gpa, git_dir) catch return Git{};
    return git;
}

fn readHead(arena: Allocator, git_dir: std.fs.Dir) !union(enum) { commit_hash: []const u8, branch: []const u8 } {
    var head_file = try git_dir.openFile("HEAD", .{});
    defer head_file.close();
    const buf = try head_file.readToEndAlloc(arena, 4096);

    if (std.mem.startsWith(u8, buf, "ref:")) {
        return .{ .branch = buf[16 .. buf.len - 1] };
    } else {
        return .{ .commit_hash = buf[0 .. buf.len - 1] };
    }
}

fn readCommitOfBranch(arena: Allocator, git_dir: std.fs.Dir, branch: []const u8) ![]const u8 {
    const rel_path = switch (builtin.os.tag) {
        .windows => win: {
            const duped_branch = try arena.dupe(u8, branch);
            defer arena.free(duped_branch);
            std.mem.replaceScalar(u8, duped_branch, '/', '\\');
            break :win try std.fs.path.join(arena, &.{ "refs", "heads", duped_branch });
        },
        else => try std.fs.path.join(arena, &.{ "refs", "heads", branch }),
    };
    defer arena.free(rel_path);

    const content = try git_dir.readFileAlloc(arena, rel_path, gitCommitHashLen + 1);
    return content[0..gitCommitHashLen];
}

fn getTagForCommitHash(arena: Allocator, git_dir: std.fs.Dir, commit_hash: []const u8) !?[]const u8 {
    const rel_path = try std.fs.path.join(arena, &.{ "refs", "tags" });
    defer arena.free(rel_path);

    var tags = try git_dir.openDir(rel_path, .{ .iterate = true });
    defer tags.close();

    var iter = tags.iterate();
    while (try iter.next()) |tag| {
        const content = try tags.readFileAlloc(arena, tag.name, gitCommitHashLen + 1);
        const tag_hash = content[0..gitCommitHashLen];

        if (std.mem.eql(u8, tag_hash, commit_hash)) {
            return try arena.dupe(u8, tag.name);
        }
    }
    return null;
}

// NOTE: Does not support packed objects
fn setAdditionalMetadata(git: *Git, arena: Allocator, git_dir: std.fs.Dir) !void {
    const commit_path = try std.fs.path.join(arena, &.{ "objects", git.commit_hash[0..2], git.commit_hash[2..] });
    defer arena.free(commit_path);

    const content = try git_dir.openFile(commit_path, .{});
    var decompressed = std.compress.zlib.decompressor(content.reader());
    const reader = decompressed.reader();
    const data = try reader.readAllAlloc(arena, 100000);

    var attributes = std.mem.splitScalar(u8, data, '\n');

    _ = attributes.next(); // tree hash
    _ = attributes.next(); // parent commit hash
    _ = attributes.next(); // author

    if (attributes.next()) |committer| {
        const @"<_index" = std.mem.indexOfScalar(u8, committer, '<').?;
        const @">_index" = std.mem.indexOfScalar(u8, committer, '>').?;

        git.author_name = committer[10 .. @"<_index" - 1];
        git.author_email = committer[@"<_index" + 1 .. @">_index"];

        const unix_time = try std.fmt.parseInt(i64, committer[@">_index" + 2 .. committer.len - 6], 10);
        const offset_hour = try std.fmt.parseInt(i64, committer[committer.len - 4 .. committer.len - 2], 10);
        const offset = switch (committer[committer.len - 5]) {
            '-' => -offset_hour,
            '+' => offset_hour,
            else => unreachable,
        };
        git.commit_date = .{ .unix = unix_time + offset * 3600 };
    }

    _ = attributes.next(); // empty line
    git.commit_message = attributes.rest();
}
