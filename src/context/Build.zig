const Build = @This();

const std = @import("std");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Optional = context.Optional;
const uninitialized = utils.uninitialized;

pub const dot = scripty.defaultDot(Build, Value, false);
pub const PassByRef = true;

generated: context.DateTime,
_git_data_path: []const u8,
_git: context.Git,

pub fn init(
    git_data_path: []const u8,
    git: context.Git,
) Build {
    return .{
        .generated = context.DateTime.initNow(),
        ._git_data_path = git_data_path,
        ._git = git,
    };
}

pub const docs_description =
    \\Gives you access to build-time assets and other build related info.
    \\When inside of a git repository it also gives git-related metadata.
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
        pub const docs_description =
            \\Retuns a build-time asset (i.e. an asset generated through your 'build.zig' file) by name.
        ;
        pub const examples =
            \\<div :text="$build.asset('foo').bytes()"></div>
        ;
        pub fn call(
            _: *const Build,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const ok = ctx._meta.build.build_assets.contains(ref);
            if (!ok) return Value.errFmt(gpa, "unknown build asset '{s}'", .{
                ref,
            });

            return .{
                .asset = .{
                    ._meta = .{
                        .ref = ref,
                        .kind = .build,
                        .url = undefined,
                    },
                },
            };
        }
    };

    pub const git = struct {
        pub const signature: Signature = .{ .ret = .Git };
        pub const docs_description =
            \\Returns git-related metadata if you are inside a git repository.
            \\If you are not or the parsing failes, it will return an error.
            \\Packed object are not supported, commit anything to get the metadata.
        ;
        pub const examples =
            \\<div :text="$build.git()..."></div>
        ;
        pub fn call(
            build: *const Build,
            _: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (build._git._in_repo) .{
                .git = build._git,
            } else .{
                .err = "Not in a git repository",
            };
        }
    };

    pub const @"git?" = struct {
        pub const signature: Signature = .{ .ret = .Git };
        pub const docs_description =
            \\Returns git-related metadata if you are inside a git repository.
            \\If you are not or the parsing failes, it will return null.
            \\Packed object are not supported, commit anything to get the metadata.
        ;
        pub const examples =
            \\<div :if="$build.git?()">...</div>
        ;
        pub fn call(
            build: *const Build,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return if (build._git._in_repo)
                Optional.init(gpa, build._git)
            else
                Optional.Null;
        }
    };
};
