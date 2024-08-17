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
    url_path_prefix: []const u8,
    output_path_prefix: []const u8,
    content_dir_path: []const u8,
    kind: union(enum) {
        simple,
        multi: struct {
            code: []const u8,
            name: []const u8,
        },
    },
},

pub const description =
    \\The global site configuration. The fields come from the call to 
    \\`website` in your `build.zig`.
    \\ 
    \\ Gives you also access to assets and static assets from the directories 
    \\ defined in your site configuration.
;

pub const dot = scripty.defaultDot(Site, Value, false);
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
            p: *const Site,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;

            const bad_arg = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return switch (p._meta.kind) {
                .multi => |l| .{ .string = l.code },
                .simple => .{
                    .err = "only available in a multilingual website",
                },
            };
        }
    };
    pub const localeName = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\In a multilingual website, returns the locale name of the current 
            \\variant as defined in your `build.zig` file. 
        ;
        pub const examples =
            \\<span var="$site.localeName()"></span>
        ;
        pub fn call(
            p: *const Site,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;

            const bad_arg = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return switch (p._meta.kind) {
                .multi => |l| .{ .string = l.name },
                .simple => .{
                    .err = "only available in a multilingual website",
                },
            };
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\Returns a link to the homepage of the website.
            \\
            \\Correctly links to a subpath when correct to do so in a  
            \\multilingual website.
        ;
        pub const examples =
            \\<a href="$site.link()" var="$site.title"></a>
        ;
        pub fn call(
            p: *const Site,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            const url = std.fs.path.join(gpa, &.{
                "/",
                p._meta.url_path_prefix,
                "/",
            }) catch @panic("oom");

            return .{ .string = url };
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
            _: *const Site,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            return context.assetFind(ref, .site);
        }
    };
    pub const page = struct {
        pub const signature: Signature = .{
            .parameters = &.{.str},
            .ret = .Page,
        };
        pub const description =
            \\Finds a page by path.
            \\
            \\Paths are relative to the content directory and should exclude
            \\the markdown suffix as Zine will automatically infer which file
            \\naming convention is used by the target page. 
            \\
            \\For example, the value 'foo/bar' will be automatically
            \\matched by Zine with either:
            \\        - content/foo/bar.md
            \\        - content/foo/bar/index.md
        ;
        pub const examples =
            \\<a href="$site.page('downloads').link()">Downloads</a>
        ;
        pub fn call(
            site: *const Site,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;

            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            return context.pageFind(.{
                .ref = .{
                    .path = ref,
                    .site = site,
                },
            });
        }
    };
    pub const locale = struct {
        pub const signature: Signature = .{
            .parameters = &.{.str},
            .ret = .Site,
        };
        pub const description =
            \\Returns the Site corresponding to the provided locale code.
            \\
            \\Only available in multilingual websites.
        ;
        pub const examples =
            \\<a href="$site.locale('en-US').link()">Murica</a>
        ;
        pub fn call(
            _: *const Site,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const code = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            const other = context.siteGet(code) orelse {
                return Value.errFmt(gpa, "unable to find locale '{s}'", .{
                    code,
                });
            };

            return .{ .site = other };
        }
    };
};
