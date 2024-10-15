const Git = @This();

const std = @import("std");
const builtin = @import("builtin");
const scripty = @import("scripty");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const DateTime = context.DateTime;
const String = context.String;
const Optional = context.Optional;
const Bool = context.Bool;
const Value = context.Value;

pub const dot = scripty.defaultDot(Git, Value, false);

pub const gitCommitHashLen = 40;

_in_repo: bool = false,

commit_hash: []const u8 = undefined,
commit_date: DateTime = undefined,
commit_message: []const u8 = undefined,
author_name: []const u8 = undefined,
author_email: []const u8 = undefined,

@"tag?": ?[]const u8 = null,
@"branch?": ?[]const u8 = null,

pub fn init(arena: Allocator) Git {
    var git = Git{};

    const git_dir = std.fs.cwd().openDir(".git", .{}) catch {
        return git;
    };
    git._in_repo = true;

    const head = readHead(arena, git_dir) catch return Git{};
    switch (head) {
        .commit_hash => |hash| git.commit_hash = hash,
        .branch => |branch| {
            git.@"branch?" = branch;
            git.commit_hash = readCommitOfBranch(arena, git_dir, branch) catch return Git{};
        },
    }

    git.@"tag?" = getTagForCommitHash(arena, git_dir, git.commit_hash) catch return Git{};

    git.setAdditionalMetadata(arena, git_dir) catch return Git{};
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
    if (builtin.os.tag == .windows) {
        try std.mem.replaceScalar(u8, branch, "/", "\\");
    }
    const rel_path = try std.fs.path.join(arena, &.{ "refs", "heads", branch });
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
        git.commit_date = try DateTime.initUnix(unix_time);
    }

    _ = attributes.next(); // empty line
    git.commit_message = attributes.rest();
}

pub const description =
    \\Information about the current git repository.
;

pub const Fields = struct {
    pub const commit_hash =
        \\The current commit hash.
    ;
    pub const commit_date =
        \\The date of the current commit.
    ;
    pub const commit_message =
        \\The commit message of the current commit.
    ;
    pub const author_name =
        \\The name of the author of the current commit.
    ;
    pub const author_email =
        \\The email of the author of the current commit.
    ;
    pub const @"tag?" =
        \\The current tag, if any.
    ;
    pub const @"branch?" =
        \\The current branch, if any.
    ;
};

pub const Builtins = struct {};
