const Page = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const scripty = @import("scripty");
const supermd = @import("supermd");
const utils = @import("utils.zig");
const render = @import("../render.zig");
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
translation_key: ?[]const u8 = null,
custom: ziggy.dynamic.Value = .null,

_meta: struct {
    site: *const context.Site = undefined,
    md_path: []const u8 = "",
    md_rel_path: []const u8 = "",
    md_asset_dir_path: []const u8 = "",
    md_asset_dir_rel_path: []const u8 = "",

    // true when this page has not been loaded via Scripty
    is_root: bool = false,
    parent_section_path: ?[]const u8 = null,
    index_in_section: ?usize = null,
    word_count: u64 = 0,
    is_section: bool = false,
    key_variants: []const Translation = &.{},
    src: []const u8 = "",
    ast: ?supermd.Ast = null,

    const Self = @This();
    pub const ziggy_options = struct {
        pub fn stringify(
            value: Self,
            opts: ziggy.serializer.StringifyOptions,
            indent_level: usize,
            depth: usize,
            writer: anytype,
        ) !void {
            _ = value;
            _ = opts;
            _ = indent_level;
            _ = depth;

            try writer.writeAll("{}");
        }

        pub fn parse(
            p: *ziggy.Parser,
            first_tok: ziggy.Tokenizer.Token,
        ) !Self {
            try p.must(first_tok, .lb);
            _ = try p.nextMust(.rb);
            return .{};
        }
    };
} = .{},

pub const Translation = struct {
    site: *const context.Site,
    md_rel_path: []const u8,
};

pub const Alternative = struct {
    layout: []const u8,
    output: []const u8,
    title: []const u8 = "",
    type: []const u8 = "",

    pub const dot = scripty.defaultDot(Alternative, Value, false);
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
pub const dot = scripty.defaultDot(Page, Value, false);
pub const PassByRef = true;
pub const Builtins = struct {
    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns an asset by name from inside the page's asset directory.
            \\
            \\Assets for a non-section page must be placed under a subdirectory 
            \\that shares the same name with the corresponding markdown file.
            \\
            \\(as a reminder sections are defined by pages named `index.md`)
            \\
            \\| section? |      page path      | asset directory |
            \\|----------|---------------------|-----------------|
            \\|   yes    |  blog/foo/index.md  |    blog/foo/    |
            \\|   no     |  blog/bar.md        |    blog/bar/    |
        ;
        pub const examples =
            \\<img src="$page.asset('foo.png').link(false)">
        ;
        pub fn call(
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (!p._meta.is_root) return .{
                .err = "accessing assets of other pages has not been implemented yet, sorry!",
            };

            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            return context.assetFind(ref, .{ .page = p });
        }
    };
    pub const site = struct {
        pub const signature: Signature = .{ .ret = .Site };
        pub const description =
            \\Returns the Site that the page belongs to.
        ;
        pub const examples =
            \\<div var="$page.site().localeName()"></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{ .site = p._meta.site };
        }
    };
    pub const locales = struct {
        pub const signature: Signature = .{ .ret = .{ .many = .Page } };
        pub const description =
            \\Returns a list of localized variants of the current page.
        ;
        pub const examples =
            \\<div loop="$page.locales()"><a href="$loop.it.link()" var="$loop.it.title"></a></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{
                .iterator = .{
                    .translation_it = context.TranslationIterator.init(p),
                },
            };
        }
    };
    pub const locale = struct {
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .{ .opt = .Page },
        };
        pub const description =
            \\Returns a reference to a localized variant of the target page, if
            \\present. Returns null otherwise.
            \\
            \\To be used in conjunction with an `if` attribute.
        ;
        pub const examples =
            \\<div if="$page.locale('en-US')"><a href="$if.link()" var="$if.title"></a></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;

            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const code = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            const other_site = context.siteGet(code) orelse return .{
                .err = "unknown locale code",
            };
            if (p.translation_key) |tk| {
                for (p._meta.key_variants) |*v| {
                    if (std.mem.eql(u8, v.site._meta.kind.multi.code, code)) {
                        const other = context.pageGet(other_site, tk, null, null, false) catch @panic("TODO: report that a localized variant failed to load");
                        return .{ .optional = .{ .page = other } };
                    }
                }
                return .{ .optional = null };
            } else {
                const other = context.pageGet(
                    other_site,
                    p._meta.md_rel_path,
                    null,
                    null,
                    false,
                ) catch @panic("trying to access a non-existent localized variant of a page is an error for now, sorry! give the same translation key to all variants of this page and you won't see this error anymore.");
                return .{ .optional = .{ .page = other } };
            }
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
            self: *const Page,
            gpa: Allocator,
            args: []const Value,
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
            self: *const Page,
            gpa: Allocator,
            args: []const Value,
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
            \\not a section, returns an empty list.
            \\
            \\Sections are defined by `index.md` files, see the content 
            \\structure section in the official docs for more info.
        ;
        pub const examples =
            \\<div loop="$page.subpages()"><span var="$loop.it.title"></span></div>
        ;
        pub fn call(
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return context.pageFind(.{ .subpages = p });
            // return self._pages.call(gpa, .{
            //     .md_rel_path = p,
            //     .url_path_prefix = self._meta.site._meta.url_path_prefix,
            //     .parent_section_path = p[0 .. p.len - "index.md".len],
            //     .kind = .subpages,
            // });
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
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            if (p._meta.index_in_section == null) return .{
                .err = "unable to do next on a page loaded by scripty, for now",
            };

            return context.pageFind(.{ .next = p });
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
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const idx = p._meta.index_in_section orelse return .{
                .err = "unable to do prev on a page loaded by scripty, for now",
            };

            if (idx == 0) return .{ .optional = null };

            return context.pageFind(.{ .prev = p });
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
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            if (p._meta.index_in_section == null) return .{
                .err = "unable to do next on a page loaded by scripty, for now",
            };

            const other = try context.pageFind(.{ .next = p });
            return if (other.optional == null) .{ .bool = false } else .{ .bool = true };
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
            p: *const Page,
            _: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const idx = p._meta.index_in_section orelse return .{
                .err = "unable to do prev on a page loaded by scripty, for now",
            };

            if (idx == 0) return .{ .bool = false };

            const other = try context.pageFind(.{ .prev = p });
            return if (other.optional == null) .{ .bool = false } else .{ .bool = true };
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
            self: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            const p = self._meta.md_rel_path;
            const path = switch (self._meta.is_section) {
                true => p[0 .. p.len - "index.md".len],
                false => p[0 .. p.len - ".md".len],
            };

            // TODO: support host url overrides

            const result = try std.fs.path.join(gpa, &.{
                "/",
                self._meta.site._meta.url_path_prefix,
                path,
                "/",
            });

            return .{ .string = result };
        }
    };

    // TODO: delete this
    pub const permalink = struct {
        pub const signature: Signature = .{ .ret = .str };
        pub const description =
            \\Deprecated, use `link()`
        ;
        pub const examples = "";
        pub fn call(
            _: *const Page,
            _: Allocator,
            _: []const Value,
        ) !Value {
            return .{ .err = "deprecated, use `link`" };
        }
    };

    pub const content = struct {
        pub const signature: Signature = .{ .ret = .str };
        pub const description =
            \\Renders the full Markdown page to HTML
        ;
        pub const examples = "";
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var buf = std.ArrayList(u8).init(gpa);
            const ast = p._meta.ast orelse return .{
                .err = "only the main page can be rendered for now",
            };
            try render.html(gpa, ast, ast.md.root, true, "", buf.writer());
            return .{ .string = try buf.toOwnedSlice() };
        }
    };
    pub const block = struct {
        pub const signature: Signature = .{
            .params = &.{ .str, .{ .opt = .bool } },
            .ret = .str,
        };
        pub const description =
            \\Renders only the specified content block of a page.
            \\A content blcok is a Markdown heading defined to be a `block` 
            \\with an id attribute set.  
            \\
            \\A second optional boolean parameter defines if the heading itself
            \\should be rendered or not (defaults to `true`).
            \\
            \\Example:
            \\ `# [Title]($block.id('section-id'))`
        ;
        pub const examples =
            \\<div var="$page.block('section-id')"></div>
            \\<div var="$page.block('other-section', false)"></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument and an optional bool argument",
            };
            if (args.len < 1 or args.len > 2) return bad_arg;

            const block_id = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            const heading = if (args.len == 1) true else switch (args[1]) {
                .bool => |s| s,
                else => return bad_arg,
            };

            const ast = p._meta.ast orelse return .{
                .err = "only the main page can be rendered for now",
            };
            var buf = std.ArrayList(u8).init(gpa);

            const node = ast.sections.get(block_id) orelse {
                return Value.errFmt(
                    gpa,
                    "content section '{s}' doesn't exist, available sections are: {s}",
                    .{ block_id, ast.sections.keys() },
                );
            };

            try render.html(gpa, ast, node, heading, "", buf.writer());
            return .{ .string = try buf.toOwnedSlice() };
        }
    };

    pub const toc = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\Renders the table of content.
        ;
        pub const examples =
            \\<div var="$page.toc()"></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 0 arguments",
            };
            if (args.len != 0) return bad_arg;

            const ast = p._meta.ast orelse return .{
                .err = "only the main page can be rendered for now",
            };
            var buf = std.ArrayList(u8).init(gpa);
            try render.htmlToc(ast, buf.writer());

            return .{ .string = try buf.toOwnedSlice() };
        }
    };
};
