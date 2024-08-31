const Build = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Signature = @import("doctypes.zig").Signature;
const uninitialized = utils.uninitialized;

pub const dot = scripty.defaultDot(Build, Value, false);
pub const PassByRef = true;

changed: context.DateTime,

pub fn init() Build {
    return .{
        .date = context.DateTime.initNow(),
    };
}

pub const description =
    \\Gives you access to build-time assets and other build related info.
    // \\When inside of a git repository it also gives git-related metadata.
;

pub const Fields = struct {
    pub const date =
        \\Returns the current datetime when the build is taking place.
        \\
        \\># [Note]($block.attrs('note'))
        \\>Using this function will not add a dependency on the current time
        \\>for the page. 
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
            \\<div text="$build.asset('foo').bytes()"></div>
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
