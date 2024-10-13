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

_in_repo: bool,

commit_hash: []const u8,
commit_date: DateTime,
commit_message: []const u8,
author_name: []const u8,
author_email: []const u8,

@"tag?": ?[]const u8,
@"branch?": ?[]const u8,

pub fn init() Git {
    return .{
        ._in_repo = true,
        .commit_hash = "TestHash",
        .commit_date = DateTime.initNow(),
        .commit_message = "TestCommit",
        .author_name = "Marlon",
        .author_email = "@mail",
        .@"tag?" = "tag",
        .@"branch?" = "branch",
    };
}

fn readHead() ![]const u8 {}

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
