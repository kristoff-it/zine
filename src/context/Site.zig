const Site = @This();

const std = @import("std");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const StringTable = @import("../StringTable.zig");
const PathTable = @import("../PathTable.zig");
const root = @import("../root.zig");
const join = root.join;
const Signature = @import("doctypes.zig").Signature;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Bool = context.Bool;
const String = context.String;
const Array = context.Array;

const log = std.log.scoped(.scripty);

host_url: []const u8,
title: []const u8,
_meta: struct {
    variant_id: u32,
    kind: union(enum) {
        simple: []const u8, // url_path_prefix
        multi: root.Locale,
    },
},

pub const docs_description =
    \\The global site configuration. The fields come from the call to 
    \\`website` in your `build.zig`.
    \\ 
    \\ Gives you also access to assets and static assets from the directories 
    \\ defined in your site configuration.
;

pub const dot = scripty.defaultDot(Site, Value, false);
pub const PassByRef = true;
pub const Fields = struct {
    pub const host_url =
        \\The host URL, as defined in your `build.zig`.
    ;
    pub const title =
        \\The website title, as defined in your `build.zig`.
    ;
};
pub const Builtins = struct {
    pub const localeCode = struct {
        pub const signature: Signature = .{
            .ret = .String,
        };
        pub const docs_description =
            \\In a multilingual website, returns the locale of the current 
            \\variant as defined in your `build.zig` file. 
        ;
        pub const examples =
            \\<html lang="$site.localeCode()"></html>
        ;
        pub fn call(
            p: *const Site,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return switch (p._meta.kind) {
                .multi => |l| String.init(l.code),
                .simple => .{
                    .err = "only available in a multilingual website",
                },
            };
        }
    };
    pub const localeName = struct {
        pub const signature: Signature = .{
            .ret = .String,
        };
        pub const docs_description =
            \\In a multilingual website, returns the locale name of the current 
            \\variant as defined in your `build.zig` file. 
        ;
        pub const examples =
            \\<span :text="$site.localeName()"></span>
        ;
        pub fn call(
            site: *const Site,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            return switch (site._meta.kind) {
                .multi => |l| String.init(l.name),
                .simple => .{
                    .err = "only available in multilingual websites",
                },
            };
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{
            .ret = .String,
        };
        pub const docs_description =
            \\Returns a link to the homepage of the website.
            \\
            \\Correctly links to a subpath when correct to do so in a  
            \\multilingual website.
        ;
        pub const examples =
            \\<a href="$site.link()" :text="$site.title"></a>
        ;
        pub fn call(
            s: *const Site,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = s;
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            var buf: std.ArrayListUnmanaged(u8) = .empty;
            const w = buf.writer(gpa);
            try ctx.printLinkPrefix(w, ctx.site._meta.variant_id, false);
            return String.init(buf.items);
        }
    };

    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Asset,
        };
        pub const docs_description =
            \\Retuns an asset by name from inside the assets directory.
        ;
        pub const examples =
            \\<img src="$site.asset('foo.png').link()">
        ;
        pub fn call(
            _: *const Site,
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

            if (root.validatePathMessage(ref, .{})) |msg| return .{ .err = msg };

            const st = &ctx._meta.build.st;
            const pt = &ctx._meta.build.pt;
            if (PathName.get(st, pt, ref)) |pn| {
                if (ctx._meta.build.site_assets.contains(pn)) {
                    return .{
                        .asset = .{
                            ._meta = .{
                                .ref = context.stripTrailingSlash(ref),
                                .url = pn,
                                .kind = .site,
                            },
                        },
                    };
                }
            }

            return Value.errFmt(gpa, "missing site asset: '{s}'", .{ref});
        }
    };

    pub const page = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Page,
        };
        pub const docs_description =
            \\Finds a page by path.
            \\
            \\Paths are relative to the content directory and should exclude
            \\the markdown suffix as Zine will automatically infer which file
            \\naming convention is used by the target page. 
            \\
            \\For example, the value 'foo/bar' will be automatically
            \\matched by Zine with either:
            \\ - content/foo/bar.smd
            \\ - content/foo/bar/index.smd
            \\
            \\To reference the site homepage, pass an empty string.
        ;
        pub const examples =
            \\<a href="$site.page('downloads').link()">Downloads</a>
        ;
        pub fn call(
            site: *const Site,
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

            if (root.validatePathMessage(ref, .{ .empty = true })) |msg| return .{
                .err = msg,
            };

            const variant = &ctx._meta.build.variants[site._meta.variant_id];

            const path = variant.path_table.getPathNoName(
                &variant.string_table,
                &.{},
                ref,
            ) orelse return Value.errFmt(gpa, "missing page '{s}'", .{
                ref,
            });

            const index_html: StringTable.String = @enumFromInt(11);
            std.debug.assert(variant.string_table.get("index.html") == index_html);
            const pn: PathName = .{
                .path = path,
                .name = index_html,
            };

            const hint = variant.urls.get(pn) orelse return Value.errFmt(
                gpa,
                "missing page '{s}'",
                .{ref},
            );

            switch (hint.kind) {
                .page_main => {},
                else => return Value.errFmt(
                    gpa,
                    "missing page '{s}'",
                    .{ref},
                ),
            }

            return .{ .page = &variant.pages.items[hint.id] };
        }
    };

    pub const pages = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Many = .String } },
            .ret = .{ .Many = .Page },
        };
        pub const docs_description =
            \\Same as `page`, but accepts a variable number of page references and 
            \\loops over them in the provided order. All pages must exist.
            \\
            \\To be used in conjunction with a `loop` attribute.
        ;
        pub const examples =
            \\<ul :loop="$site.pages('a', 'b', 'c')"><li :text="$loop.it.title"></li></ul>
        ;
        pub fn call(
            site: *const Site,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            if (args.len == 0) return .{
                .err = "expected at least 1 string argument",
            };

            const v = &ctx._meta.build.variants[site._meta.variant_id];
            const page_list = try gpa.alloc(Value, args.len);
            errdefer gpa.free(page_list);

            for (page_list, args) |*p, arg| {
                const ref = switch (arg) {
                    .string => |s| s.value,
                    else => return .{ .err = "not a string argument" },
                };

                const path = v.path_table.getPathNoName(
                    &v.string_table,
                    &.{},
                    ref,
                ) orelse return Value.errFmt(gpa, "page '{s}' does not exist", .{
                    ref,
                });

                const index_html: StringTable.String = @enumFromInt(11);
                const hint = v.urls.get(.{
                    .path = path,
                    .name = index_html,
                }) orelse return Value.errFmt(gpa, "page '{s}' does not exist", .{
                    ref,
                });

                switch (hint.kind) {
                    .page_main => {},
                    else => return Value.errFmt(gpa, "page '{s}' does not exist", .{
                        ref,
                    }),
                }

                p.* = .{ .page = &v.pages.items[hint.id] };
                if (!p.page._parse.active) return Value.errFmt(
                    gpa,
                    "page '{s}' is a draft",
                    .{ref},
                );
            }

            return context.Array.init(gpa, Value, page_list);
        }
    };
    pub const locale = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Site,
        };
        pub const docs_description =
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
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const code = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const site = ctx._meta.sites.getPtr(code) orelse return Value.errFmt(
                gpa,
                "unknown language code '{s}'",
                .{code},
            );

            return .{ .site = site };
        }
    };
};
