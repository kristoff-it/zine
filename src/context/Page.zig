const Page = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const scripty = @import("scripty");
const supermd = @import("supermd");
const utils = @import("utils.zig");
const render = @import("../render.zig");
const Signature = @import("doctypes.zig").Signature;
const DateTime = @import("DateTime.zig");
const context = @import("../context.zig");
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Optional = context.Optional;
const Bool = context.Bool;
const String = context.String;

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
custom: ziggy.dynamic.Value = .{ .kv = .{} },

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
    name: []const u8 = "",
    layout: []const u8,
    output: []const u8,
    type: []const u8 = "",

    pub const dot = scripty.defaultDot(Alternative, Value, false);
    // pub const PassByRef = true;

    pub const Builtins = struct {};
    pub const description =
        \\An alternative version of the current page. Title and type
        \\can be used when generating `<link rel="alternate">` elements.
    ;
    pub const Fields = struct {
        pub const layout =
            \\The SuperHTML layout to use to generate this alternative version of the page.
        ;
        pub const output =
            \\Output path where to to put the generated alternative.
        ;
        pub const name =
            \\A name that can be used to fetch this alternative version
            \\of the page.
        ;
        pub const @"type" =
            \\A metadata field that can be used to set the content-type of this alternative version of the Page. 
            \\
            \\Useful for example to generate RSS links:
            \\
            \\```superhtml
            \\<ctx alt="$page.alternative('rss')"
            \\  <a href="$ctx.alt.link()" 
            \\     type="$ctx.alt.type" 
            \\     text="$ctx.alt.name"
            \\  ></a>
            \\</ctx>
            \\```
        ;
    };
};
pub const dot = scripty.defaultDot(Page, Value, false);
pub const PassByRef = true;

pub const description =
    \\The page currently being rendered.
;
pub const Fields = struct {
    pub const title =
        \\Title of the page, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const description =
        \\Description of the page, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const author =
        \\Author of the page, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const date =
        \\Publication date of the page, 
        \\as set in the SuperMD frontmatter.
        \\
        \\Used to provide default ordering of pages.
    ;
    pub const layout =
        \\SuperHTML layout used to render the page, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const draft =
        \\When set to true the page will not be rendered in release mode, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const tags =
        \\Tags associated with the page, 
        \\as set in the SuperMD frontmatter.
    ;
    pub const aliases =
        \\Aliases of the current page, 
        \\as set in the SuperMD frontmatter.
        \\
        \\Aliases can be used to make the same page available
        \\from different locations.
        \\
        \\Every entry in the list is an output location where the 
        \\rendered page will be copied to.
    ;
    pub const alternatives =
        \\Alternative versions of the page, 
        \\as set in the SuperMD frontmatter.
        \\
        \\Alternatives are a good way of implementing RSS feeds, for example.
    ;
    pub const skip_subdirs =
        \\Skips any other potential content present in the subdir of the page, 
        \\as set in the SuperMD frontmatter.
        \\
        \\Can only be set to true on section pages (i.e. `index.smd` pages).
    ;
    pub const translation_key =
        \\Translation key used to map this page with corresponding localized variants, 
        \\as set in the SuperMD frontmatter.
        \\
        \\See the docs on i18n for more info.
    ;
    pub const custom =
        \\A Ziggy map where you can define custom properties for the page, 
        \\as set in the SuperMD frontmatter.
    ;
};
pub const Builtins = struct {
    pub const isCurrent = struct {
        pub const signature: Signature = .{ .ret = .Bool };
        pub const description =
            \\Returns true if the target page is the one currently being 
            \\rendered. 
            \\
            \\To be used in conjunction with the various functions that give 
            \\you references to other pages, like `$site.page()`, for example.
        ;
        pub const examples =
            \\<div class="$site.page('foo').isCurrent().then('selected')"></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return Bool.init(p._meta.is_root);
        }
    };

    pub const asset = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Asset,
        };
        pub const description =
            \\Retuns an asset by name from inside the page's asset directory.
            \\
            \\Assets for a non-section page must be placed under a subdirectory 
            \\that shares the same name with the corresponding markdown file.
            \\
            \\(as a reminder sections are defined by pages named `index.smd`)
            \\
            \\| section? |     page path      | asset directory |
            \\|----------|--------------------|-----------------|
            \\|   yes    | blog/foo/index.smd |    blog/foo/    |
            \\|   no     | blog/bar.smd       |    blog/bar/    |
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
                .string => |s| s.value,
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
            \\<div :text="$page.site().localeName()"></div>
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

    pub const locale = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .{ .Opt = .Page },
        };
        pub const description =
            \\Returns a reference to a localized variant of the target page.
            \\
        ;
        pub const examples =
            \\<div text="$page.locale('en-US').title"></div>
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
                .string => |s| s.value,
                else => return bad_arg,
            };

            const other_site = context.siteGet(code) orelse return .{
                .err = "unknown locale code",
            };
            if (p.translation_key) |tk| {
                for (p._meta.key_variants) |*v| {
                    if (std.mem.eql(u8, v.site._meta.kind.multi.code, code)) {
                        const other = context.pageGet(other_site, tk, null, null, false) catch @panic("TODO: report that a localized variant failed to load");
                        return .{ .page = other };
                    }
                }
                return .{ .err = "locale not found" };
            } else {
                const other = context.pageGet(
                    other_site,
                    p._meta.md_rel_path,
                    null,
                    null,
                    false,
                ) catch @panic("Trying to access a non-existent localized variant of a page is an error for now, sorry! As a temporary workaround you can set a translation key for this page (and its localized variants). This limitation will be lifted in the future.");
                return .{ .page = other };
            }
        }
    };

    pub const @"locale?" = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .{ .Opt = .Page },
        };
        pub const description =
            \\Returns a reference to a localized variant of the target page, if
            \\present. Returns null otherwise.
            \\
            \\To be used in conjunction with an `if` attribute.
        ;
        pub const examples =
            \\<div :if="$page.locale?('en-US')">
            \\  <a href="$if.link()" :text="$if.title"></a>
            \\</div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const code = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const other_site = context.siteGet(code) orelse return .{
                .err = "unknown locale code",
            };
            if (p.translation_key) |tk| {
                for (p._meta.key_variants) |*v| {
                    if (std.mem.eql(u8, v.site._meta.kind.multi.code, code)) {
                        const other = context.pageGet(other_site, tk, null, null, false) catch @panic("TODO: report that a localized variant failed to load");
                        return Optional.init(gpa, other);
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
                return Optional.init(gpa, other);
            }
        }
    };

    pub const locales = struct {
        pub const signature: Signature = .{ .ret = .{ .Many = .Page } };
        pub const description =
            \\Returns the list of localized variants of the current page.
        ;
        pub const examples =
            \\<div :loop="$page.locales()"><a href="$loop.it.link()" text="$loop.it.title"></a></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{
                .iterator = try context.Iterator.init(gpa, .{
                    .translation_it = context.Iterator.TranslationIterator.init(p),
                }),
            };
        }
    };

    pub const wordCount = struct {
        pub const signature: Signature = .{ .ret = .Int };
        pub const description =
            \\Returns the word count of the page.
            \\
            \\The count is performed assuming 5-letter words, so it actually
            \\counts all characters and divides the result by 5.
        ;
        pub const examples =
            \\<div :loop="$page.wordCount()"></div>
        ;
        pub fn call(
            self: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{ .int = .{ .value = @intCast(self._meta.word_count) } };
        }
    };

    pub const parentSection = struct {
        pub const signature: Signature = .{ .ret = .Page };
        pub const description =
            \\Returns the parent section of a page. 
            \\
            \\It's always an error to call this function on the site's main 
            \\index page as it doesn't have a parent section.
        ;
        pub const examples =
            \\$page.parentSection()
        ;
        pub fn call(
            self: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            const p = self._meta.parent_section_path orelse return .{
                .err = "root index page has no parent path",
            };
            return context.pageFind(.{
                .ref = .{
                    .path = p,
                    .site = self._meta.site,
                },
            });
        }
    };

    pub const isSection = struct {
        pub const signature: Signature = .{ .ret = .Bool };
        pub const description =
            \\Returns true if the current page defines a section (i.e. if 
            \\the current page is an 'index.smd' page).
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
            return Bool.init(self._meta.is_section);
        }
    };

    pub const subpages = struct {
        pub const signature: Signature = .{ .ret = .{ .Many = .Page } };
        pub const description =
            \\Returns a list of all the pages in this section. If the page is 
            \\not a section, returns an empty list.
            \\
            \\Sections are defined by `index.smd` files, see the content 
            \\structure section in the official docs for more info.
        ;
        pub const examples =
            \\<div :loop="$page.subpages()">
            \\  <span :text="$loop.it.title"></span>
            \\</div>
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
        pub const signature: Signature = .{ .ret = .{ .Opt = .Page } };
        pub const description =
            \\Returns the next page in the same section, sorted by date. 
            \\
            \\The returned value is an optional to be used in conjunction 
            \\with an `if` attribute. Use `$if` to access the unpacked value
            \\within the `if` block.
        ;
        pub const examples =
            \\<div :if="$page.nextPage()">
            \\  <span :text="$if.title"></span>
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
        pub const signature: Signature = .{ .ret = .{ .Opt = .Page } };
        pub const description =
            \\Tries to return the page before the target one (sorted by date), to be used with an `if` attribute.
        ;
        pub const examples =
            \\<div :if="$page.prevPage()"></div>
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
        pub const signature: Signature = .{ .ret = .Bool };
        pub const description =
            \\Returns true of the target page has another page after (sorted by date) 
        ;
        pub const examples =
            \\$page.hasNext()
        ;

        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            if (p._meta.index_in_section == null) return .{
                .err = "unable to do next on a page loaded by scripty, for now",
            };

            const other = try context.pageFind(.{ .next = p });
            return Bool.init(other.optional != null);
        }
    };
    pub const hasPrev = struct {
        pub const signature: Signature = .{ .ret = .Bool };
        pub const description =
            \\Returns true of the target page has another page before (sorted by date) 
        ;
        pub const examples =
            \\$page.hasPrev()
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const idx = p._meta.index_in_section orelse return .{
                .err = "unable to do prev on a page loaded by scripty, for now",
            };

            if (idx == 0) return Bool.False;

            const other = try context.pageFind(.{ .prev = p });
            return Bool.init(other.optional != null);
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{ .ret = .String };
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
                true => p[0 .. p.len - "index.smd".len],
                false => p[0 .. p.len - ".smd".len],
            };

            // TODO: support host url overrides

            const result = try std.fs.path.join(gpa, &.{
                "/",
                self._meta.site._meta.url_path_prefix,
                path,
                "/",
            });

            return String.init(result);
        }
    };

    // TODO: delete this
    pub const permalink = struct {
        pub const signature: Signature = .{ .ret = .String };
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
        pub const signature: Signature = .{ .ret = .String };
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
            try render.html(gpa, ast, ast.md.root, "", buf.writer());
            return String.init(try buf.toOwnedSlice());
        }
    };
    pub const contentSection = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .String,
        };
        pub const description =
            \\Renders the specified [content section]($link.page('docs/supermd/scripty').ref('Section')) of a page.
        ;
        pub const examples =
            \\<div :html="$page.contentSection('section-id')"></div>
            \\<div :html="$page.contentSection('other-section')"></div>
        ;
        pub fn call(
            p: *const Page,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 string argument argument",
            };
            if (args.len != 1) return bad_arg;

            const section_id = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const ast = p._meta.ast orelse return .{
                .err = "only the main page can be rendered for now",
            };
            var buf = std.ArrayList(u8).init(gpa);

            const node = ast.ids.get(section_id) orelse {
                return Value.errFmt(
                    gpa,
                    "content section '{s}' doesn't exist",
                    .{section_id},
                );
            };

            switch (node.getDirective().?.kind) {
                .section => {},
                else => {
                    return Value.errFmt(
                        gpa,
                        "id '{s}' exists but is not a section",
                        .{section_id},
                    );
                },
            }

            try render.html(gpa, ast, node, "", buf.writer());
            return String.init(try buf.toOwnedSlice());
        }
    };

    pub const contentSections = struct {
        pub const signature: Signature = .{
            .params = &.{},
            .ret = .{ .Many = .ContentSection },
        };
        pub const description =
            \\Returns a list of sections for the current page.
            \\
            \\A page that doesn't define any section will have
            \\a default section for the whole document with a 
            \\null id.
        ;
        pub const examples =
            \\<div :html="$page.contentSections()"></div>
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

            const ast = p._meta.ast.?;

            var sections = std.ArrayList(ContentSection).init(gpa);
            var it = ast.ids.iterator();
            while (it.next()) |kv| {
                const d = kv.value_ptr.getDirective().?;
                if (d.kind == .section) {
                    try sections.append(.{
                        .id = d.id orelse "",
                        .data = d.data,
                        ._node = kv.value_ptr.*,
                        ._ast = ast,
                    });
                }
            }

            return Value.from(gpa, try sections.toOwnedSlice());
        }
    };

    pub const toc = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const description =
            \\Renders the table of content.
        ;
        pub const examples =
            \\<div :html="$page.toc()"></div>
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

            return String.init(try buf.toOwnedSlice());
        }
    };
};

pub const ContentSection = struct {
    id: []const u8,
    data: supermd.Directive.Data = .{},
    _node: supermd.Node,
    _ast: supermd.Ast,

    pub const dot = scripty.defaultDot(ContentSection, Value, false);
    pub const description =
        \\A content section from a page.
    ;
    pub const Fields = struct {
        pub const id =
            \\The id of the current section.
        ;
        pub const data =
            \\A Ziggy Map that contains data key-value pairs set in SuperMD
        ;
    };
    pub const Builtins = struct {
        pub const heading = struct {
            pub const signature: Signature = .{ .ret = .String };
            pub const description =
                \\If the section starts with a heading element,
                \\this function returns the heading as simple text.           
            ;
            pub const examples =
                \\<div :html="$loop.it.heading()"></div>
            ;
            pub fn call(
                cs: ContentSection,
                gpa: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{
                    .err = "expected 0 arguments",
                };
                if (args.len != 0) return bad_arg;

                const err = Value.errFmt(gpa, "section '{s}' has no heading", .{
                    cs.id,
                });

                if (cs._node.nodeType() != .HEADING) {
                    return err;
                }

                // const link_node = cs._node.firstChild() orelse {
                //     return err;
                // };

                // const text_node = link_node.firstChild() orelse {
                //     return err;
                // };

                // const text = text_node.literal() orelse {
                //     return err;
                // };

                const text = try cs._node.renderPlaintext();

                return String.init(text);
            }
        };
        pub const @"heading?" = struct {
            pub const signature: Signature = .{ .ret = .{ .Opt = .String } };
            pub const description =
                \\If the section starts with a heading element,
                \\this function returns the heading as simple text.           
            ;
            pub const examples =
                \\<div :html="$loop.it.heading()"></div>
            ;
            pub fn call(
                cs: ContentSection,
                gpa: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{
                    .err = "expected 0 arguments",
                };
                if (args.len != 0) return bad_arg;

                if (cs._node.nodeType() != .HEADING) {
                    return Optional.Null;
                }

                const link_node = cs._node.firstChild() orelse {
                    return Optional.Null;
                };

                const text = link_node.literal() orelse {
                    return Optional.Null;
                };

                return Optional.init(gpa, String.init(text));
            }
        };
        pub const html = struct {
            pub const signature: Signature = .{ .ret = .String };
            pub const description =
                \\Renders the section.
            ;
            pub const examples =
                \\<div :html="$loop.it.html()"></div>
            ;
            pub fn call(
                cs: ContentSection,
                gpa: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{
                    .err = "expected 0 arguments",
                };
                if (args.len != 0) return bad_arg;

                var buf = std.ArrayList(u8).init(gpa);

                try render.html(
                    gpa,
                    cs._ast,
                    cs._node,
                    "",
                    buf.writer(),
                );
                return String.init(try buf.toOwnedSlice());
            }
        };
    };
};
