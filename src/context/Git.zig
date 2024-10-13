const Git = @This();

const std = @import("std");
const scripty = @import("scripty");
const context = @import("../context.zig");
const DateTime = context.DateTime;
const Value = context.Value;

pub const dot = scripty.defaultDot(Git, Value, false);

_in_repo: bool,

current_commit: ?struct {
    hash: []const u8,
    date: DateTime,
    message: []const u8,
    author: struct {
        name: []const u8,
        email: []const u8,
    },
},
current_tag: ?[]const u8,
current_branch: ?[]const u8,

pub fn init() Git {
    return .{
        ._in_repo = false,
        .current_commit = null,
        .current_tag = null,
        .current_branch = null,
    };
}

fn readHead() ![]const u8 {}

pub const description =
    \\Information about the current git repository.
;

pub const Builtins = struct {};
