const Git = @This();

const std = @import("std");
const scripty = @import("scripty");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
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

pub fn init() Git {
    var self = Git{};
    const git_dir = std.fs.cwd().openDir(".git", .{}) catch {
        return self;
    };
    self._in_repo = true;

    // TODO: Handle errors
    const head = readHead(git_dir) catch unreachable;
    switch (head) {
        .commit_hash => |hash| self.commit_hash = hash,
        .branch => |branch| {
            self.@"branch?" = branch;
            self.commit_hash = readCommitOfBranch(git_dir, branch) catch |err| @errorName(err);
        },
    }

    self.@"tag?" = getTagForCommitHash(git_dir, self.commit_hash) catch |err| @errorName(err);

    // TODO: Get the rest of the metadata
    self.commit_date = DateTime.initNow();
    self.commit_message = "NoMessage";
    self.author_name = "NoName";
    self.author_email = "NoEmail";

    return self;
}

fn readHead(git_dir: std.fs.Dir) !union(enum) { commit_hash: []const u8, branch: []const u8 } {
    const pa = std.heap.page_allocator;
    var head_file = try git_dir.openFile("HEAD", .{});
    defer head_file.close();
    const buf = try head_file.readToEndAlloc(pa, 4096);

    if (std.mem.startsWith(u8, buf, "ref:")) {
        return .{ .branch = buf[16 .. buf.len - 1] };
    } else {
        return .{ .commit_hash = buf[0 .. buf.len - 1] };
    }
}

// TODO: support branches with slashes
fn readCommitOfBranch(git_dir: std.fs.Dir, branch: []const u8) ![]const u8 {
    const pa = std.heap.page_allocator;
    const rel_path = try std.fs.path.join(pa, &.{ "refs", "heads", branch });
    defer pa.free(rel_path);
    const content = try git_dir.readFileAlloc(pa, rel_path, gitCommitHashLen + 1);
    return content[0..gitCommitHashLen];
}

fn getTagForCommitHash(git_dir: std.fs.Dir, commit_hash: []const u8) !?[]const u8 {
    const pa = std.heap.page_allocator;
    const rel_path = try std.fs.path.join(pa, &.{ "refs", "tags" });
    defer pa.free(rel_path);

    var tags = try git_dir.openDir(rel_path, .{ .iterate = true });
    defer tags.close();

    var iter = tags.iterate();
    while (try iter.next()) |tag| {
        const content = try tags.readFileAlloc(pa, tag.name, gitCommitHashLen + 1);
        const tag_hash = content[0..gitCommitHashLen];
        // NOTE: This could maybe be optimized
        if (std.mem.eql(u8, tag_hash, commit_hash)) {
            return try pa.dupe(u8, tag.name);
        }
    }
    return null;
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
