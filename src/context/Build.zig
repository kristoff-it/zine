const Build = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Git = @import("./Git.zig");
const Value = context.Value;
const Signature = @import("doctypes.zig").Signature;
const uninitialized = utils.uninitialized;

pub const dot = scripty.defaultDot(Build, Value, false);
pub const PassByRef = true;

generated: context.DateTime,
_git: Git,

pub fn init() Build {
    return .{
        .generated = context.DateTime.initNow(),
        ._git = Git.init(),
    };
}

pub const description =
    \\Gives you access to build-time assets and other build related info.
    // \\When inside of a git repository it also gives git-related metadata.
;

pub const Fields = struct {
    pub const generated =
        \\Returns the current date when the build is taking place.
        \\
        \\># [Note]($block.attrs('note'))
        \\>Using this function will not add a dependency on the current time
        \\>for the page, hence the name `generated`. 
        \\>
        \\>To get the best results, use in conjunction with caching as otherwise
        \\>the page will be regenerated anew every single time.
    ;
};

pub const Builtins = struct {
    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns a build-time asset (i.e. an asset generated through your 'build.zig' file) by name.
        ;
        pub const examples =
            \\<div :text="$build.asset('foo').bytes()"></div>
        ;
        pub fn call(
            _: *const Build,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            return context.assetFind(ref, .{ .build = null });
        }
    };
};

pub fn git(build: Build) Value {
    return if (build._git._in_repo) .{ .git = build._git } else .{ .err = "Not in a git repository" };
}
