const Site = @This();

const std = @import("std");
const log = std.log.scoped(.scripty);
const Io = std.Io;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;

const scripty = @import("scripty");
const ziggy = @import("ziggy");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Bool = context.Bool;
const String = context.String;
const Array = context.Array;
const StringTable = @import("../StringTable.zig");
const PathTable = @import("../PathTable.zig");
const PathName = PathTable.PathName;
const root = @import("../root.zig");
const join = root.join;
const Signature = @import("doctypes.zig").Signature;

host_url: []const u8,
title: []const u8,
custom: ziggy.Dictionary(ziggy.Dynamic),
_meta: struct {
    variant_id: u32,
    kind: union(enum) {
        simple: []const u8, // url_path_prefix
        multi: root.Locale,
    },
},

pub const docs_description =
    \\ The global site configuration. The fields come from your `zine.ziggy`
    \\ config file (or the call to `website` in your `build.zig`).
    \\ 
    \\ Gives you also access to site assets and other site-wide resources.
;

pub const Dot = true;
pub const PassByRef = true;
pub const Fields = struct {
    pub const host_url =
        \\The host URL, as defined in your `build.zig`.
    ;
    pub const title =
        \\The website title, as defined in your `build.zig`.
    ;
    pub const custom =
        \\The custom Ziggy Dictionary you can define in your `zine.ziggy`
        \\config file.
        \\
        \\Note that in the case of multilingual websites this is still
        \\going to be a single instance shared by all localized variants.
        \\To create per-localized-variant settings, refer to the 'i18n'
        \\documentation.
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
            ctx: *const context.Root,
            args: []const Value,
        ) !Value {
            _ = gpa;
            _ = ctx;

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
            _: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
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
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            _ = s;
            const bad_arg: Value = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            var aw: Writer.Allocating = .init(gpa);
            ctx.printLinkPrefix(
                &aw.writer,
                ctx.site._meta.variant_id,
                false,
            ) catch return error.OutOfMemory;
            return String.init(aw.written());
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
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
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

    pub const index = struct {
        pub const signature: Signature = .{
            .ret = .Page,
        };
        pub const docs_description =
            \\Returns the root index page of the site,
            \\sometimes referred to also as the homepage.
        ;
        pub const examples =
            \\<a href="$site.index().link()">Homepage</a>
        ;
        pub fn call(
            site: *const Site,
            _: Allocator,
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{ .err = "expected no arguments" };
            if (args.len != 0) return bad_arg;

            const variant = &ctx._meta.build.variants[site._meta.variant_id];
            return .{ .page = &variant.pages.items[variant.root_index] };
        }
    };

    pub const page = struct {
        pub const signature: Signature = .{
            .params = &.{
                .String,
                .{ .Many = .String },
            },
            .ret = .Page,
        };
        pub const docs_description =
            \\Finds a page by path.
            \\
            \\Paths are relative to the content directory and should
            \\exclude the markdown suffix as Zine will automatically infer
            \\which file naming convention is used by the target page.
            \\
            \\For example, the value 'foo/bar' will be automatically
            \\matched by Zine with either:
            \\
            \\ - content/foo/bar.smd
            \\ - content/foo/bar/index.smd
            \\
            \\Passing an empty string will return the root index file (aka
            \\the homepage), but it's recommended to use `$site.index()`
            \\when trying to access it directly.
            \\
            \\You can pass multiple arguments to compose a path, meaning
            \\that the two following invocations are equivalent:
            \\
            \\ - `$site.page('foo/bar/baz')`
            \\ - `$site.page('foo', 'bar/baz')`
            \\
            \\This can be useful when part of your path is fixed while
            \\part is parametrized:
            \\
            \\ - `$site.page('speakers', $page.authors.at(0))`
        ;
        pub const examples =
            \\<a href="$site.page('downloads').link()">Downloads</a>
        ;
        pub fn call(
            site: *const Site,
            gpa: Allocator,
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected 1 or more string arguments",
            };
            if (args.len < 1) return bad_arg;

            var path_buf: Io.Writer.Allocating = .init(gpa);
            defer path_buf.deinit();

            for (args) |arg| switch (arg) {
                .string => |s| {
                    if (s.value.len == 0) continue;
                    const str = if (s.value[s.value.len - 1] == '/')
                        s.value[0 .. s.value.len - 1]
                    else
                        s.value;

                    if (path_buf.written().len > 0) {
                        path_buf.writer.writeByte('/') catch return error.OutOfMemory;
                    }

                    path_buf.writer.writeAll(str) catch return error.OutOfMemory;
                },
                else => return bad_arg,
            };

            const ref = path_buf.written();

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
            .ret = .{ .Many = .Page },
        };
        pub const docs_description =
            \\Returns all pages in the website, to be used in conjunction with a `loop` attribute.
        ;
        pub const examples =
            \\<ul :loop="$site.pages()"><li :text="$loop.it.title"></li></ul>
        ;
        pub fn call(
            site: *const Site,
            gpa: Allocator,
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            const v = &ctx._meta.build.variants[site._meta.variant_id];

            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const page_list = try gpa.alloc(Value, v.pages.items.len);
            errdefer gpa.free(page_list);

            page_list[0] = .{ .page = &v.pages.items[v.root_index] };
            var idx: usize = 1;
            for (v.sections.items[1..]) |*s| {
                for (s.pages.items) |pid| {
                    page_list[idx] = .{ .page = &v.pages.items[pid] };
                    idx += 1;
                }
            }

            std.debug.assert(idx == page_list.len);

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
            ctx: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
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
