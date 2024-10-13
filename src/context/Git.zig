const Git = @This();

const std = @import("std");
const scripty = @import("scripty");
const context = @import("../context.zig");
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

tag: ?[]const u8,
branch: ?[]const u8,

pub fn init() Git {
    return .{
        ._in_repo = false,
        .commit_hash = "",
        .commit_date = DateTime.initNow(),
        .commit_message = "",
        .author_name = "",
        .author_email = "",
        .tag = null,
        .branch = null,
    };
}

fn readHead() ![]const u8 {}

pub const description =
    \\Information about the current git repository.
;

pub const Builtins = struct {};
