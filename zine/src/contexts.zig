const std = @import("std");
const scripty = @import("scripty");
const super = @import("super");
const ziggy = @import("ziggy");
const datetime = @import("datetime").datetime;
const timezones = @import("datetime").timezones;
const Signature = @import("docgen.zig").Signature;
const hl = @import("highlight.zig");

pub const DateTime = struct {
    _dt: datetime.Datetime,
    _string_repr: []const u8,

    pub const ziggy_options = struct {
        pub fn stringify(
            value: DateTime,
            opts: ziggy.serializer.StringifyOptions,
            indent_level: usize,
            depth: usize,
            writer: anytype,
        ) !void {
            _ = opts;
            _ = indent_level;
            _ = depth;

            try writer.print("\"{}\"", .{std.zig.fmtEscapes(value._string_repr)});
        }

        pub fn parse(p: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) !DateTime {
            try p.mustAny(first_tok, &.{ .string, .at });
            const src = switch (first_tok.tag) {
                .string => first_tok.loc.unquote(p.code) orelse {
                    return p.addError(.{
                        .syntax = .{
                            .name = first_tok.tag.lexeme(),
                            .sel = first_tok.loc.getSelection(p.code),
                        },
                    });
                },
                .at => blk: {
                    const ident = try p.nextMust(.identifier);
                    if (!std.mem.eql(u8, ident.loc.src(p.code), "date")) {
                        return p.addError(.{
                            .syntax = .{
                                .name = "@date",
                                .sel = ident.loc.getSelection(p.code),
                            },
                        });
                    }
                    _ = try p.nextMust(.lp);
                    const str = try p.nextMust(.string);
                    _ = try p.nextMust(.rp);
                    break :blk str.loc.unquote(p.code) orelse {
                        return p.addError(.{
                            .syntax = .{
                                .name = first_tok.tag.lexeme(),
                                .sel = first_tok.loc.getSelection(p.code),
                            },
                        });
                    };
                },
                else => unreachable,
            };

            const date = datetime.Date.parseIso(src[0..10]) catch {
                return p.addError(.{
                    .syntax = .{
                        .name = first_tok.tag.lexeme(),
                        .sel = first_tok.loc.getSelection(p.code),
                    },
                });
            };
            return .{
                ._string_repr = src,
                ._dt = .{
                    .date = date,
                    .time = datetime.Time.create(0, 0, 0, 0) catch unreachable,
                    .zone = &timezones.UTC,
                },
            };
        }
    };

    pub fn lessThan(self: DateTime, rhs: DateTime) bool {
        return self._dt.lt(rhs._dt);
    }
};

pub const Template = struct {
    site: Site,
    page: Page,

    // Globals specific to Super
    loop: ?Value = null,
    @"if": ?Value = null,

    pub const dot = scripty.defaultDot(Template, Value);
};

pub const Site = struct {
    base_url: []const u8,
    title: []const u8,

    pub const description =
        \\The global site configuration. The fields come from the call to 
        \\`addWebsite` in your `build.zig`.
    ;
    pub const dot = scripty.defaultDot(Site, Value);
    pub const PassByRef = true;
    pub const Builtins = struct {};
};

pub const Page = struct {
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
    custom: ziggy.dynamic.Value = .null,
    content: []const u8 = "",

    _meta: struct {
        permalink: []const u8 = "",
        word_count: i64 = 0,
        prev: ?*Page = null,
        next: ?*Page = null,
        subpages: []const Page = &.{},
        is_section: bool = false,

        const Self = @This();
    } = .{},

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
            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };
                return .{ .int = self._meta.word_count };
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
                \\<div ></div>
            ;
            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };
                return .{ .bool = self._meta.is_section };
            }
        };

        pub const subpages = struct {
            pub const signature: Signature = .{ .ret = .{ .many = .Page } };
            pub const description =
                \\Only available on 'index.md' pages, as those are the pages
                \\that define a section.
                \\
                \\Returns a list of all the pages in this section.
                \\
            ;
            pub const examples =
                \\<div loop="$page.subpages()"><span var="$loop.it.title"></span></div>
            ;
            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };

                return .{ .iterator = .{ .page_it = .{ .items = self._meta.subpages } } };
            }
        };

        pub const nextPage = struct {
            pub const signature: Signature = .{ .ret = .{ .opt = .Page } };
            pub const description =
                \\Tries to return the page after the target one (sorted by date), to be used with an `if` attribute.
            ;
            pub const examples =
                \\<div if="$page.nextPage()"></div>
            ;

            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };
                if (self._meta.next) |next| {
                    return .{ .optional = .{ .page = next } };
                } else {
                    return .{ .optional = null };
                }
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

            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };
                if (self._meta.prev) |prev| {
                    return .{ .optional = .{ .page = prev } };
                } else {
                    return .{ .optional = null };
                }
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

            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                const p = try nextPage.call(self, gpa, args);
                return switch (p) {
                    .err => p,
                    .optional => |opt| if (opt == null)
                        .{ .bool = false }
                    else
                        .{ .bool = true },
                    else => unreachable,
                };
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
            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                const p = try prevPage.call(self, gpa, args);
                return switch (p) {
                    .err => p,
                    .optional => |opt| if (opt == null)
                        .{ .bool = false }
                    else
                        .{ .bool = true },

                    else => unreachable,
                };
            }
        };

        pub const permalink = struct {
            pub const signature: Signature = .{ .ret = .str };
            pub const description =
                \\Returns the URL of the target page.
            ;
            pub const examples =
                \\$page.permalink()
            ;
            pub fn call(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
                _ = gpa;
                if (args.len != 0) return .{ .err = "expected 0 arguments" };
                return .{ .string = self._meta.permalink };
            }
        };
    };
};

pub const Value = union(enum) {
    template: *Template,
    site: *Site,
    page: *Page,
    alternative: *Page.Alternative,
    dynamic: ziggy.dynamic.Value,
    iterator: Iterator,
    iterator_element: IterElement,
    optional: ?Optional,
    string: []const u8,
    date: DateTime,
    bool: bool,
    int: i64,
    float: f64,
    err: []const u8,

    pub const call = scripty.defaultCall(Value);

    pub const Optional = union(enum) {
        iter_elem: IterElement,
        page: *Page,
        bool: bool,
        int: i64,
        string: []const u8,
    };

    pub const Iterator = union(enum) {
        string_it: SliceIterator([]const u8),
        page_it: SliceIterator(Page),
        alt_it: SliceIterator(Page.Alternative),

        pub fn len(self: Iterator) usize {
            const l: usize = switch (self) {
                inline else => |v| v.len(),
            };

            return l;
        }
        pub fn next(self: *Iterator, gpa: std.mem.Allocator) ?Optional {
            switch (self.*) {
                inline else => |*v| {
                    const n = v.next(gpa) orelse return null;
                    const l = self.len();

                    const elem_type = @typeInfo(@TypeOf(n)).Pointer.child;
                    const by_ref = @typeInfo(elem_type) == .Struct and @hasDecl(elem_type, "PassByRef") and elem_type.PassByRef;
                    const it = if (by_ref)
                        IterElement.IterValue.from(n)
                    else
                        IterElement.IterValue.from(n.*);
                    return .{
                        .iter_elem = .{
                            .it = it,
                            .idx = v.idx,
                            .first = v.idx == 0,
                            .last = v.idx == l - 1,
                        },
                    };
                },
            }
        }

        pub fn dot(self: Iterator, gpa: std.mem.Allocator, path: []const u8) Value {
            _ = path;
            _ = gpa;
            _ = self;
            return .{ .err = "field access on an iterator value" };
        }
    };

    pub const IterElement = struct {
        it: IterValue,
        idx: usize,
        first: bool,
        last: bool,

        const IterValue = union(enum) {
            string: []const u8,
            page: *Page,
            alternative: *Page.Alternative,

            pub fn from(v: anytype) IterValue {
                return switch (@TypeOf(v)) {
                    []const u8 => .{ .string = v },
                    *Page => .{ .page = v },
                    *Page.Alternative => .{ .alternative = v },
                    else => @compileError("TODO: implement IterElement.IterValue.from for " ++ @typeName(@TypeOf(v))),
                };
            }
        };

        pub const dot = scripty.defaultDot(IterElement, Value);
    };

    pub fn fromStringLiteral(s: []const u8) Value {
        return .{ .string = s };
    }

    pub fn fromNumberLiteral(bytes: []const u8) Value {
        const num = std.fmt.parseInt(i64, bytes, 10) catch {
            return .{ .err = "error parsing numeric literal" };
        };
        return .{ .int = num };
    }

    pub fn fromBooleanLiteral(b: bool) Value {
        return .{ .bool = b };
    }

    pub fn from(gpa: std.mem.Allocator, v: anytype) Value {
        _ = gpa;
        return switch (@TypeOf(v)) {
            *Template => .{ .template = v },
            *Site => .{ .site = v },
            *Page => .{ .page = v },
            *Page.Alternative => .{ .alternative = v },
            []const Page.Alternative => .{ .iterator = .{ .alt_it = .{ .items = v } } },
            // IterElement => .{ .iteration_element = v },
            DateTime => .{ .date = v },
            []const u8 => .{ .string = v },
            bool => .{ .bool = v },
            i64, usize => .{ .int = @intCast(v) },
            ?Value => if (v) |o| o else .{ .err = "trying to access nil value" },
            *Value => v.*,
            IterElement.IterValue => switch (v) {
                .string => |s| .{ .string = s },
                .page => |p| .{ .page = p },
                .alternative => |p| .{ .alternative = p },
            },
            Optional => switch (v) {
                .iter_elem => |ie| .{ .iterator_element = ie },
                .page => |p| .{ .page = p },
                .bool => |b| .{ .bool = b },
                .string => |s| .{ .string = s },
                .int => |i| .{ .int = i },
            },

            ?Optional => .{ .optional = v orelse @panic("TODO: null optional reached Value.from") },
            ziggy.dynamic.Value => .{ .dynamic = v },
            []const []const u8 => .{ .iterator = .{ .string_it = .{ .items = v } } },
            else => @compileError("TODO: implement Value.from for " ++ @typeName(@TypeOf(v))),
        };
    }
    pub fn dot(
        self: *Value,
        gpa: std.mem.Allocator,
        path: []const u8,
    ) error{OutOfMemory}!Value {
        switch (self.*) {
            .string,
            .bool,
            .int,
            .float,
            .err,
            .date,
            => return .{ .err = "field access on primitive value" },
            .dynamic => return .{ .err = "field access on dynamic value" },
            .optional => return .{ .err = "field access on optional value" },
            // .iteration_element => return
            .iterator_element => |*v| return v.dot(gpa, path),
            inline else => |v| return v.dot(gpa, path),
        }
    }

    pub fn builtinsFor(comptime tag: @typeInfo(Value).Union.tag_type.?) type {
        const StringBuiltins = struct {
            pub const len = struct {
                pub const signature: Signature = .{ .ret = .int };
                pub const description =
                    \\Returns the length of a string.
                    \\
                ;
                pub const examples =
                    \\$page.title.len()
                ;
                pub fn call(str: []const u8, gpa: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len != 0) return .{ .err = "'len' wants no arguments" };
                    return Value.from(gpa, str.len);
                }
            };

            pub const suffix = struct {
                pub const signature: Signature = .{
                    .params = &.{ .str, .{ .many = .str } },
                    .ret = .str,
                };
                pub const description =
                    \\Concatenates strings together (left-to-right).
                    \\
                ;
                pub const examples =
                    \\$page.title.suffix("Foo","Bar", "Baz")
                ;
                pub fn call(str: []const u8, gpa: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len == 0) return .{ .err = "'suffix' wants at least one argument" };
                    var out = std.ArrayList(u8).init(gpa);
                    errdefer out.deinit();

                    try out.appendSlice(str);
                    for (args) |a| {
                        const fx = switch (a) {
                            .string => |s| s,
                            else => return .{ .err = "'suffix' arguments must be strings" },
                        };

                        try out.appendSlice(fx);
                    }

                    return .{ .string = try out.toOwnedSlice() };
                }
            };
            pub const syntaxHighlight = struct {
                pub const signature: Signature = .{
                    .params = &.{.str},
                    .ret = .str,
                };
                pub const description =
                    \\Applies syntax highlighting to a string.
                    \\The argument specifies the language name.
                    \\
                ;
                pub const examples =
                    \\<pre><code class="ziggy" var="$page.custom.get('sample', '').syntaxHighLight('ziggy')"></code></pre>
                ;
                pub fn call(str: []const u8, gpa: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len != 1) return .{ .err = "'syntaxHighlight' wants one argument" };
                    var out = std.ArrayList(u8).init(gpa);
                    errdefer out.deinit();

                    const lang = switch (args[0]) {
                        .string => |s| s,
                        else => return .{ .err = "the argument to 'syntaxHighlight' must be of type string" },
                    };

                    // _ = lang;
                    // _ = str;
                    hl.highlightCode(gpa, lang, str, out.writer()) catch |err| switch (err) {
                        error.NoLanguage => return .{ .err = "unable to find a parser for the provided language" },
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return .{ .err = "error while syntax highlighting" },
                    };

                    return .{ .string = try out.toOwnedSlice() };
                }
            };
        };
        const DynamicBuiltins = struct {
            pub const @"get?" = struct {
                pub const signature: Signature = .{ .params = &.{.str}, .ret = .{ .opt = .dyn } };
                pub const description =
                    \\Tries to get a dynamic value, to be used in conjuction with an `if` attribute.
                    \\
                ;
                pub const examples =
                    \\<div if="$page.custom.get?('myValue')"></div>
                ;
                pub fn call(dyn: ziggy.dynamic.Value, gpa: std.mem.Allocator, args: []const Value) Value {
                    _ = gpa;
                    const bad_arg = .{ .err = "'get?' wants 1 string argument" };
                    if (args.len != 1) return bad_arg;

                    const path = switch (args[0]) {
                        .string => |s| s,
                        else => return bad_arg,
                    };

                    if (dyn == .null) return .{ .optional = null };
                    if (dyn != .kv) return .{ .err = "get? on a non-map dynamic value" };

                    if (dyn.kv.fields.get(path)) |value| {
                        switch (value) {
                            .null => return .{ .optional = null },
                            .bool => |b| return .{ .optional = .{ .bool = b } },
                            .integer => |i| return .{ .optional = .{ .int = i } },
                            .bytes => |s| return .{ .optional = .{ .string = s } },
                            inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
                        }
                    }

                    return .{ .optional = null };
                }
            };

            pub const get = struct {
                pub const signature: Signature = .{ .params = &.{ .str, .str }, .ret = .str };
                pub const description =
                    \\Tries to get a dynamic value, uses the provided default value otherwise.
                    \\
                ;
                pub const examples =
                    \\$page.custom.get('coauthor', 'nobody')
                ;
                pub fn call(dyn: ziggy.dynamic.Value, gpa: std.mem.Allocator, args: []const Value) Value {
                    _ = gpa;
                    const bad_arg = .{ .err = "'get' wants 2 string arguments" };
                    if (args.len != 2) return bad_arg;

                    const path = switch (args[0]) {
                        .string => |s| s,
                        else => return bad_arg,
                    };

                    const fallback = switch (args[1]) {
                        .string => |s| s,
                        else => return bad_arg,
                    };

                    if (dyn == .null) return .{ .string = fallback };
                    if (dyn != .kv) return .{ .err = "get on a non-map dynamic value" };

                    if (dyn.kv.fields.get(path)) |value| {
                        switch (value) {
                            .null => return .{ .string = fallback },
                            .bool => |b| return .{ .bool = b },
                            .integer => |i| return .{ .int = i },
                            .bytes => |s| return .{ .string = s },
                            inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
                        }
                    }

                    return .{ .string = fallback };
                }
            };
        };

        const DateBuiltins = struct {
            pub const format = struct {
                pub const signature: Signature = .{ .params = &.{.str}, .ret = .str };
                pub const description =
                    \\Formats a datetime according to the specified format string.
                    \\
                ;
                pub const examples =
                    \\$page.date.format("January 02, 2006")
                    \\$page.date.format("06-Jan-02")
                ;
                pub fn call(dt: DateTime, gpa: std.mem.Allocator, args: []const Value) !Value {
                    const argument_error = .{ .err = "'format' wants one (string) argument" };
                    if (args.len != 1) return argument_error;
                    const string = switch (args[0]) {
                        .string => |s| s,
                        else => return argument_error,
                    };

                    if (!std.mem.eql(u8, string, "January 02, 2006")) {
                        @panic("TODO: implement more date formatting options");
                    }

                    const formatted_date = try std.fmt.allocPrint(gpa, "{s} {:0>2}, {}", .{
                        dt._dt.date.monthName(),
                        dt._dt.date.day,
                        dt._dt.date.year,
                    });

                    return .{ .string = formatted_date };
                }
            };

            pub const formatHTTP = struct {
                pub const signature: Signature = .{ .ret = .str };
                pub const description =
                    \\Formats a datetime according to the HTTP spec.
                    \\
                ;
                pub const examples =
                    \\$page.date.formatHTTP()
                ;
                pub fn call(dt: DateTime, gpa: std.mem.Allocator, args: []const Value) !Value {
                    const argument_error = .{ .err = "'formatHTTP' wants no argument" };
                    if (args.len != 0) return argument_error;

                    // Fri, 16 Jun 2023 00:00:00 +0000
                    const formatted_date = try std.fmt.allocPrint(
                        gpa,
                        "{s}, {:0>2} {s} {} 00:00:00 +0000",
                        .{
                            dt._dt.date.weekdayName()[0..3],
                            dt._dt.date.day,
                            dt._dt.date.monthName()[0..3],
                            dt._dt.date.year,
                        },
                    );

                    return .{ .string = formatted_date };
                }
            };
        };
        const BoolBuiltins = struct {
            pub const not = struct {
                pub const signature: Signature = .{ .ret = .bool };
                pub const description =
                    \\Negates a boolean value.
                    \\
                ;
                pub const examples =
                    \\$page.draft.not()
                ;
                pub fn call(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len != 0) return .{ .err = "'not' wants no arguments" };
                    return .{ .bool = !b };
                }
            };
            pub const @"and" = struct {
                pub const signature: Signature = .{
                    .params = &.{ .bool, .{ .many = .bool } },
                    .ret = .bool,
                };

                pub const description =
                    \\Computes logical `and` between the receiver value and any other value passed as argument.
                    \\
                ;
                pub const examples =
                    \\$page.draft.and($site.tags.len().eq(10))
                ;
                pub fn call(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len == 0) return .{ .err = "'and' wants at least one argument" };
                    for (args) |a| switch (a) {
                        .bool => {},
                        else => return .{ .err = "wrong argument type" },
                    };
                    if (!b) return .{ .bool = false };
                    for (args) |a| if (!a.bool) return .{ .bool = false };

                    return .{ .bool = true };
                }
            };
            pub const @"or" = struct {
                pub const signature: Signature = .{
                    .params = &.{ .bool, .{ .many = .bool } },
                    .ret = .bool,
                };
                pub const description =
                    \\Computes logical `or` between the receiver value and any other value passed as argument.
                    \\
                ;
                pub const examples =
                    \\$page.draft.or($site.tags.len().eq(0))
                ;
                pub fn call(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
                    if (args.len == 0) return .{ .err = "'or' wants at least one argument" };
                    for (args) |a| switch (a) {
                        .bool => {},
                        else => return .{ .err = "wrong argument type" },
                    };
                    if (b) return .{ .bool = true };
                    for (args) |a| if (a.bool) return .{ .bool = true };

                    return .{ .bool = false };
                }
            };
        };
        const IntBuiltins = struct {
            pub const eq = struct {
                pub const signature: Signature = .{
                    .params = &.{.int},
                    .ret = .bool,
                };
                pub const description =
                    \\Tests if two integers have the same value.
                    \\
                ;
                pub const examples =
                    \\$page.wordCount().eq(200)
                ;
                pub fn call(num: i64, _: std.mem.Allocator, args: []const Value) !Value {
                    const argument_error = .{ .err = "'plus' wants one int argument" };
                    if (args.len != 1) return argument_error;

                    switch (args[0]) {
                        .int => |rhs| {
                            return .{ .bool = num == rhs };
                        },
                        else => return argument_error,
                    }
                }
            };

            pub const plus = struct {
                pub const signature: Signature = .{
                    .params = &.{.int},
                    .ret = .int,
                };
                pub const description =
                    \\Sums two integers.
                    \\
                ;
                pub const examples =
                    \\$page.wordCount().plus(10)
                ;
                pub fn call(num: i64, _: std.mem.Allocator, args: []const Value) !Value {
                    const argument_error = .{ .err = "'plus' wants one (int|float) argument" };
                    if (args.len != 1) return argument_error;

                    switch (args[0]) {
                        .int => |add| {
                            return .{ .int = num +| add };
                        },
                        .float => @panic("TODO: int with float argument"),
                        else => return argument_error,
                    }
                }
            };
            pub const div = struct {
                pub const signature: Signature = .{
                    .params = &.{.int},
                    .ret = .int,
                };
                pub const description =
                    \\Divides the receiver by the argument.
                    \\
                ;
                pub const examples =
                    \\$page.wordCount().div(10)
                ;
                pub fn call(num: i64, _: std.mem.Allocator, args: []const Value) !Value {
                    const argument_error = .{ .err = "'div' wants one (int|float) argument" };
                    if (args.len != 1) return argument_error;

                    switch (args[0]) {
                        .int => |den| {
                            const res = std.math.divTrunc(i64, num, den) catch |err| {
                                return .{ .err = @errorName(err) };
                            };

                            return .{ .int = res };
                        },
                        .float => @panic("TODO: div with float argument"),
                        else => return argument_error,
                    }
                }
            };
        };
        return switch (tag) {
            .site => Site.Builtins,
            .page => Page.Builtins,
            .string => StringBuiltins,
            .date => DateBuiltins,
            .int => IntBuiltins,
            .bool => BoolBuiltins,
            .dynamic => DynamicBuiltins,
            else => struct {},
        };
    }
};

pub fn SliceIterator(comptime Element: type) type {
    return struct {
        items: []const Element,
        idx: usize = 0,

        pub fn len(self: @This()) usize {
            return self.items.len;
        }
        pub fn index(self: @This()) usize {
            return self.items.idx;
        }
        pub fn next(self: *@This(), gpa: std.mem.Allocator) ?*Element {
            _ = gpa;
            if (self.idx == self.items.len) return null;
            const result: ?*Element = @constCast(&self.items[self.idx]);
            self.idx += 1;
            return result;
        }
    };
}

// pub const Dynamic = struct {
//     _value: std.json.Value = .null,

//     pub fn dot(self: *Dynamic, gpa: std.mem.Allocator, path: []const u8) Value {
//         _ = path;
//         _ = gpa;
//         _ = self;
//         return .{ .err = "field access on a dynamic value" };
//     }

//     pub const call = scripty.defaultCall(Value);
// };
