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

_in_repo: bool = false,

commit_hash: []const u8 = undefined,
commit_date: DateTime = undefined,
commit_message: []const u8 = undefined,
author_name: []const u8 = undefined,
author_email: []const u8 = undefined,

_tag: ?[]const u8 = null,
_branch: ?[]const u8 = null,

pub const docs_description =
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
};

pub const Builtins = struct {
    pub const tag = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the tag of the current commit.
            \\If the current commit does not have a tag, an error is returned.
        ;
        pub const examples =
            \\<div :text="$build.git().tag()"></div>
            \\<div :if="$build.git?()"><span :text="$if.tag()"></span></div>
        ;
        pub fn call(
            git: Git,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (git._tag) |_tag| Value.from(gpa, _tag) else .{ .err = "No tag for this commit" };
        }
    };

    pub const @"tag?" = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the tag of the current commit.
            \\If the current commit does not have a tag, null is returned.
        ;
        pub const examples =
            \\<div :if="$build.git().tag?()"><span :text="$if"></span></div>
            \\<div :if="$build.git?()"><span :if="$if.tag?()"><span :text="$if"></span></span></div>
        ;
        pub fn call(
            git: Git,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (git._tag) |_tag| Optional.init(gpa, _tag) else Optional.Null;
        }
    };

    pub const branch = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the branch of the current commit.
            \\If the current commit does not have a branch, an error is returned.
        ;
        pub const examples =
            \\<div :text="$build.git().branch()"></div>
            \\<div :if="$build.git?()"><span :text="$if.branch()"></span></div>
        ;
        pub fn call(
            git: Git,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (git._branch) |_branch| Value.from(gpa, _branch) else .{ .err = "No branch for this commit" };
        }
    };

    pub const @"branch?" = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the branch of the current commit.
            \\If the current commit does not have a branch, null is returned.
        ;
        pub const examples =
            \\<div :if="$build.git().branch?()"><span :text="$if"></span></div>
            \\<div :if="$build.git?()"><span :if="$if.branch?()"><span :text="$if"></span></span></div>
        ;
        pub fn call(
            git: Git,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (git._branch) |_branch| Optional.init(gpa, _branch) else Optional.Null;
        }
    };
};
