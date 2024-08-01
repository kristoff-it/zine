const Page = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const Signature = @import("docgen.zig").Signature;
const DateTime = @import("DateTime.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Allocator = std.mem.Allocator;

var asset_undef: context.AssetExtern = .{};
var page_undef: context.PageExtern = .{};

title: []const u8,
description: []const u8 = "",
author: []const u8,
date: DateTime,
layout: []const u8,
draft: bool = false,
tags: []const []const u8 = &.{},
aliases: []const []const u8 = &.{},
alternatives: []const Alternative = &.{},
skip_subdirs: bool = false,
translation_key: []const u8 = "",
custom: ziggy.dynamic.Value = .null,
content: []const u8 = "",
_assets: *context.AssetExtern = &asset_undef,
_pages: *context.PageExtern = &page_undef,

_meta: struct {
    // true when this page has not been loaded via Scripty
    is_root: bool = false,
    parent_section_path: ?[]const u8 = null,
    index_in_section: ?usize = null,
    url_path_prefix: []const u8 = "",
    md_rel_path: []const u8 = "",
    word_count: u64 = 0,
    is_section: bool = false,
    translations: []const Translation = &.{},
} = .{},

pub const Translation = struct {
    locale_code: []const u8,
    page: *Page,
    _meta: struct {
        host_url_override: ?[]const u8 = null,
    } = .{},

    pub const dot = scripty.defaultDot(Translation, Value);
    pub const PassByRef = true;
    pub const Builtins = struct {};
    pub const description =
        \\A Localized Variant of the current page.
    ;
};

pub const Alternative = struct {
    layout: []const u8,
    output: []const u8,
    title: []const u8 = "",
    type: []const u8 = "",

    pub const dot = scripty.defaultDot(Alternative, Value);
    pub const PassByRef = true;
    pub const Builtins = struct {};
    pub const description =
        \\An alternative version of the current page. Title and type
        \\can be used when generating `<link rel="alternate">` elements.
    ;
};
pub const description =
    \\The current page.
;
pub const dot = scripty.defaultDot(Page, Value);
pub const PassByRef = true;
pub const Builtins = struct {
    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns an asset by name from inside the page's subdirectory.
        ;
        pub const examples =
            \\<img src="$page.asset('foo.png')">
        ;
        pub fn call(
            p: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            if (!p._meta.is_root) return .{
                .err = "accessing assets of other pages has not been implemented yet, sorry!",
            };

            const ref = switch (args[0]) {
                .string => |s| try std.fs.path.join(gpa, &.{
                    std.fs.path.dirname(p._meta.md_rel_path).?,
                    s,
                }),
                else => return bad_arg,
            };

            return p._assets.call(gpa, .{
                .kind = .page,
                .ref = ref,
            });
        }
    };
    pub const translations = struct {
        pub const signature: Signature = .{ .ret = .{ .many = .Translation } };
        pub const description =
            \\Returns a list of translations for the current page.
            \\A translation is a file with the same translation key as the current page.
        ;
        pub const examples =
            \\<div loop="$page.translations()"><a href="$loop.it.link()" var="$loop.it.title"></a></div>
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{
                .iterator = .{
                    .translation_it = .{ .items = self._meta.translations },
                },
            };
        }
    };
    pub const wordCount = struct {
        pub const signature: Signature = .{ .ret = .int };
        pub const description =
            \\Returns the word count of the page.
            \\
            \\The count is performed assuming 5-letter words, so it actually
            \\counts all characters and divides the result by 5.
        ;
        pub const examples =
            \\<div loop="$page.wordCount()"></div>
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{ .int = @intCast(self._meta.word_count) };
        }
    };

    pub const isSection = struct {
        pub const signature: Signature = .{ .ret = .bool };
        pub const description =
            \\Returns true if the current page defines a section (i.e. if 
            \\the current page is an 'index.md' page).
            \\
        ;
        pub const examples =
            \\$page.isSection()
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{ .bool = self._meta.is_section };
        }
    };

    pub const subpages = struct {
        pub const signature: Signature = .{ .ret = .{ .many = .Page } };
        pub const description =
            \\Returns a list of all the pages in this section. If the page is 
            \\not a section, it returns an empty list.
            \\
            \\Sections are defined by `index.md` files, see the content 
            \\structure section in the official docs for more info.
        ;
        pub const examples =
            \\<div loop="$page.subpages()"><span var="$loop.it.title"></span></div>
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            const p = self._meta.md_rel_path;
            return self._pages.call(gpa, .{
                .md_rel_path = p,
                .url_path_prefix = self._meta.url_path_prefix,
                .parent_section_path = p[0 .. p.len - "index.md".len],
                .kind = .subpages,
            });
        }
    };

    pub const nextPage = struct {
        pub const signature: Signature = .{ .ret = .{ .opt = .Page } };
        pub const description =
            \\Returns the next page in the same section, sorted by date. 
            \\
            \\The returned value is an optional to be used in conjunction 
            \\with an `if` attribute. Use `$if` to access the unpacked value
            \\within the `if` block.
        ;
        pub const examples =
            \\<div if="$page.nextPage()">
            \\  <span var="$if.title"></span>
            \\</div>
        ;

        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const idx = self._meta.index_in_section orelse return .{
                .optional = null,
            };
            const p = self._meta.md_rel_path;

            return self._pages.call(gpa, .{
                .md_rel_path = p,
                .url_path_prefix = self._meta.url_path_prefix,
                .parent_section_path = self._meta.parent_section_path.?,
                .kind = .{ .next = idx },
            });
        }
    };
    pub const prevPage = struct {
        pub const signature: Signature = .{ .ret = .{ .opt = .Page } };
        pub const description =
            \\Tries to return the page before the target one (sorted by date), to be used with an `if` attribute.
        ;
        pub const examples =
            \\<div if="$page.prevPage()"></div>
        ;

        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const idx = self._meta.index_in_section orelse return .{
                .optional = null,
            };
            if (idx == 0) return .{ .optional = null };
            const p = self._meta.md_rel_path;
            return self._pages.call(gpa, .{
                .md_rel_path = p,
                .url_path_prefix = self._meta.url_path_prefix,
                .parent_section_path = self._meta.parent_section_path.?,
                .kind = .{ .prev = idx },
            });
        }
    };

    pub const hasNext = struct {
        pub const signature: Signature = .{ .ret = .bool };
        pub const description =
            \\Returns true of the target page has another page after (sorted by date) 
        ;
        pub const examples =
            \\$page.hasNext()
        ;

        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            ext: *utils.SuperHTMLResource,
        ) !Value {
            _ = self;
            _ = gpa;
            _ = args;
            _ = ext;
            // const p = try nextPage.call(self, gpa, args, ext);
            // return switch (p) {
            //     .err => p,
            //     .optional => |opt| if (opt == null)
            //         .{ .bool = false }
            //     else
            //         .{ .bool = true },
            //     else => unreachable,
            // };

            @panic("todo");
        }
    };
    pub const hasPrev = struct {
        pub const signature: Signature = .{ .ret = .bool };
        pub const description =
            \\Returns true of the target page has another page before (sorted by date) 
        ;
        pub const examples =
            \\$page.hasPrev()
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            ext: *utils.SuperHTMLResource,
        ) !Value {
            _ = self;
            _ = gpa;
            _ = args;
            _ = ext;
            // const p = try prevPage.call(self, gpa, args, ext);
            // return switch (p) {
            //     .err => p,
            //     .optional => |opt| if (opt == null)
            //         .{ .bool = false }
            //     else
            //         .{ .bool = true },

            //     else => unreachable,
            // };
            @panic("todo");
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{ .ret = .str };
        pub const description =
            \\Returns the URL of the target page.
        ;
        pub const examples =
            \\$page.link()
        ;
        pub fn call(
            self: *Page,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            const p = self._meta.md_rel_path;
            const path = switch (self._meta.is_section) {
                true => p[0 .. p.len - "index.md".len],
                false => p[0 .. p.len - ".md".len],
            };

            const result = try std.fs.path.join(gpa, &.{
                "/",
                self._meta.url_path_prefix,
                path,
                "/",
            });

            return .{ .string = result };
        }
    };
};
