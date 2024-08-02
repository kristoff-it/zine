const Build = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Signature = @import("docgen.zig").Signature;
const uninitialized = utils.uninitialized;
_assets: *const context.AssetExtern = &.{},

pub const description =
    \\Gives you access to build-time assets and other build related info.
    \\When inside of a git repository it also gives git-related metadata.
;
pub const dot = scripty.defaultDot(Build, Value);
pub const PassByRef = true;
pub const Builtins = struct {
    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns a build-time asset (i.e. an asset generated through your 'build.zig' file) by name.
        ;
        pub const examples =
            \\<div var="$build.asset('foo').bytes()"></div>
        ;
        pub fn call(
            b: *Build,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            return b._assets.call(gpa, .{
                .kind = .{ .build = null },
                .ref = ref,
            });
        }
    };
    // pub const date = struct {
    //     pub const signature: Signature = .{
    //         .params = &.{},
    //         .ret = .Date,
    //     };
    //     pub const description =
    //         \\Retuns a build-time asset (i.e. an asset generated through your 'build.zig' file) by name.
    //     ;
    //     pub const examples =
    //         \\<div var="$build.asset('foo').bytes()"></div>
    //     ;
    //     pub fn call(
    //         b: *Build,
    //         gpa: Allocator,
    //         args: []const Value,
    //         _: *utils.SuperHTMLResource,
    //     ) !Value {
    //         const bad_arg = .{
    //             .err = "expected 1 string argument",
    //         };
    //         if (args.len != 1) return bad_arg;

    //         const ref = switch (args[0]) {
    //             .string => |s| s,
    //             else => return bad_arg,
    //         };

    //         return b._assets.call(gpa, .{
    //             .kind = .build,
    //             .ref = ref,
    //         });
    //     }
    // };
};
