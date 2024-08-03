const Site = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Signature = @import("docgen.zig").Signature;

host_url: []const u8,
title: []const u8,
_meta: struct {
    locale: ?[]const u8,
},

_assets: *const context.AssetExtern = &.{},

pub const description =
    \\The global site configuration. The fields come from the call to 
    \\`website` in your `build.zig`.
    \\ 
    \\ Gives you also access to assets and static assets from the directories 
    \\ defined in your site configuration.
;

pub const dot = scripty.defaultDot(Site, Value);
pub const PassByRef = true;
pub const Builtins = struct {
    pub const localeCode = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\In a multilingual website, returns the locale of the current 
            \\variant as defined in your `build.zig` file. 
        ;
        pub const examples =
            \\<html lang="$site.localeCode()"></html>
        ;
        pub fn call(
            p: *Site,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;

            const bad_arg = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            const l = p._meta.locale orelse return .{
                .err = "only available in a multilingual website",
            };

            return .{ .string = l };
        }
    };

    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns an asset by name from inside the assets directory.
        ;
        pub const examples =
            \\<img src="$site.asset('foo.png').link()">
        ;
        pub fn call(
            p: *Site,
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

            return p._assets.call(gpa, .{
                .kind = .site,
                .ref = ref,
            });
        }
    };
};
