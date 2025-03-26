const Git = @This();

const std = @import("std");
const builtin = @import("builtin");
const ziggy = @import("ziggy");
const zeit = @import("zeit");
const Allocator = std.mem.Allocator;

pub const git_commit_hash_len = 40;

_in_repo: bool = false,
commit_hash: []const u8 = undefined,
_tag: ?[]const u8 = null,
_branch: ?[]const u8 = null,
author_name: []const u8 = undefined,
author_email: []const u8 = undefined,
commit_date: CommitDate = undefined,
commit_message: []const u8 = undefined,

const CommitDate = struct {
    unix: i64 = 0,

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
};

pub fn init(gpa: Allocator, path: []const u8) !Git {
    var p = path;
    var git_dir = while (true) {
        var dir = try std.fs.openDirAbsolute(p, .{});
        defer dir.close();
        break dir.openDir(".git", .{}) catch |err| switch (err) {
            error.FileNotFound => {
                p = std.fs.path.dirname(p) orelse return Git{};
                continue;
            },
            else => return err,
        };
    };
    defer git_dir.close();

    const head = readHead(gpa, git_dir) catch return Git{};

    var commit_hash: [git_commit_hash_len]u8 = undefined;
    var branch: ?[]const u8 = null;

    switch (head) {
        .commit_hash => |hash| commit_hash = hash,
        .branch => |b| {
            branch = b;
            commit_hash = readCommitOfBranch(gpa, git_dir, b) catch return Git{};
        },
    }

    const tag = getTagForCommitHash(gpa, git_dir, &commit_hash) catch return Git{};

    const meta = setAdditionalMetadata(gpa, git_dir, commit_hash) catch return Git{};

    return .{
        ._in_repo = true,
        .commit_hash = try gpa.dupe(u8, &commit_hash),
        ._branch = branch,
        ._tag = tag,
        .commit_date = meta.commit_date,
        .commit_message = meta.commit_message,
        .author_name = meta.author_name,
        .author_email = meta.author_email,
    };
}

const Head = union(enum) {
    commit_hash: [git_commit_hash_len]u8,
    branch: []const u8,
};
fn readHead(gpa: Allocator, git_dir: std.fs.Dir) !Head {
    var head_file = try git_dir.openFile("HEAD", .{});
    defer head_file.close();
    const buf = try head_file.readToEndAlloc(gpa, 4096);
    const prefix = "ref: refs/heads/";
    if (std.mem.startsWith(u8, buf, prefix)) {
        return .{ .branch = buf[prefix.len .. buf.len - 1] };
    } else {
        defer gpa.free(buf);
        return .{ .commit_hash = buf[0..git_commit_hash_len].* };
    }
}

fn readCommitOfBranch(gpa: Allocator, git_dir: std.fs.Dir, branch: []const u8) ![git_commit_hash_len]u8 {
    const rel_path = switch (builtin.os.tag) {
        .windows => win: {
            const duped_branch = try gpa.dupe(u8, branch);
            defer gpa.free(duped_branch);
            std.mem.replaceScalar(u8, duped_branch, '/', '\\');
            break :win try std.fs.path.join(gpa, &.{ "refs", "heads", duped_branch });
        },
        else => try std.fs.path.join(gpa, &.{ "refs", "heads", branch }),
    };
    defer gpa.free(rel_path);

    var hash: [git_commit_hash_len]u8 = undefined;
    const read = try git_dir.readFile(rel_path, &hash);
    std.debug.assert(read.len == hash.len);
    return hash;
}

fn getTagForCommitHash(
    arena: Allocator,
    git_dir: std.fs.Dir,
    commit_hash: []const u8,
) !?[]const u8 {
    const rel_path = "refs" ++ std.fs.path.sep_str ++ "tags";

    var tags = try git_dir.openDir(rel_path, .{ .iterate = true });
    defer tags.close();

    var iter = tags.iterate();
    while (try iter.next()) |tag| {
        var buf: [git_commit_hash_len]u8 = undefined;
        const tag_hash = try tags.readFile(tag.name, &buf);

        if (std.mem.eql(u8, tag_hash, commit_hash)) {
            return try arena.dupe(u8, tag.name);
        }
    }
    return null;
}

const Meta = struct {
    author_name: []const u8 = "",
    author_email: []const u8 = "",
    commit_date: CommitDate = .{},
    commit_message: []const u8 = "",
};

// NOTE: Does not support packed objects
fn setAdditionalMetadata(
    arena: Allocator,
    git_dir: std.fs.Dir,
    commit_hash: [git_commit_hash_len]u8,
) !Meta {
    const commit_path = "objects" ++ std.fs.path.sep_str ++ commit_hash[0..2] ++ std.fs.path.sep_str ++ commit_hash[2..];

    const content = try git_dir.openFile(commit_path, .{});
    var decompressed = std.compress.zlib.decompressor(content.reader());
    const reader = decompressed.reader();
    const data = try reader.readAllAlloc(arena, 100_000);

    // std.debug.print("git data: \n\n{s}\n\n", .{data});

    var meta: Meta = .{};
    var attributes = std.mem.splitScalar(u8, data, '\n');
    while (attributes.next()) |attribute| {
        const committer_heading = "committer ";
        if (std.mem.startsWith(u8, attribute, committer_heading)) {
            const @"<_index" = std.mem.indexOfScalar(u8, attribute, '<').?;
            const @">_index" = std.mem.indexOfScalar(u8, attribute, '>').?;

            meta.author_name = attribute[10 .. @"<_index" - 1];
            meta.author_email = attribute[@"<_index" + 1 .. @">_index"];

            const unix_time = try std.fmt.parseInt(
                i64,
                attribute[@">_index" + 2 .. attribute.len - 6],
                10,
            );
            const offset_hour = try std.fmt.parseInt(
                i64,
                attribute[attribute.len - 4 .. attribute.len - 2],
                10,
            );
            const offset = switch (attribute[attribute.len - 5]) {
                '-' => -offset_hour,
                '+' => offset_hour,
                else => unreachable,
            };
            meta.commit_date = .{ .unix = unix_time + offset * 3600 };
        }
        if (attribute.len == 0) {
            break;
        }
    }
    meta.commit_message = attributes.rest();
    return meta;
}
