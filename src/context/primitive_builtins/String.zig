const std = @import("std");
const Allocator = std.mem.Allocator;
const hl = @import("../../highlight.zig");
const utils = @import("../utils.zig");
const log = utils.log;
const Signature = @import("../docgen.zig").Signature;
const Value = @import("../../context.zig").Value;

pub const len = struct {
    pub const signature: Signature = .{ .ret = .int };
    pub const description =
        \\Returns the length of a string.
        \\
    ;
    pub const examples =
        \\$page.title.len()
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len != 0) return .{ .err = "expected 0 arguments" };
        return Value.from(gpa, str.len);
    }
};

pub const contains = struct {
    pub const signature: Signature = .{
        .params = &.{.str},
        .ret = .bool,
    };
    pub const description =
        \\Returns true if the receiver contains the provided string.
        \\
    ;
    pub const examples =
        \\$page.permalink().contains("/blog/")
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        _ = gpa;
        const bad_arg = .{
            .err = "expected 1 string argument",
        };
        if (args.len != 1) return bad_arg;

        const needle = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        return .{ .bool = std.mem.indexOf(u8, str, needle) != null };
    }
};

pub const endsWith = struct {
    pub const signature: Signature = .{
        .params = &.{.str},
        .ret = .bool,
    };
    pub const description =
        \\Returns true if the receiver ends with the provided string.
        \\
    ;
    pub const examples =
        \\$page.permalink().endsWith("/blog/")
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        _ = gpa;
        const bad_arg = .{
            .err = "expected 1 string argument",
        };
        if (args.len != 1) return bad_arg;

        const needle = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        const result = std.mem.endsWith(u8, str, needle);
        log.debug("endsWith('{s}', '{s}') = {}", .{ str, needle, result });

        return .{ .bool = result };
    }
};
pub const eql = struct {
    pub const signature: Signature = .{
        .params = &.{.str},
        .ret = .bool,
    };
    pub const description =
        \\Returns true if the receiver equals the provided string.
        \\
    ;
    pub const examples =
        \\$page.author.eql("Loris Cro")
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        _ = gpa;
        const bad_arg = .{
            .err = "expected 1 string argument",
        };
        if (args.len != 1) return bad_arg;
        const needle = switch (args[0]) {
            .string => |s| s,
            else => return bad_arg,
        };

        return .{ .bool = std.mem.eql(u8, str, needle) };
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
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
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
pub const fmt = struct {
    pub const signature: Signature = .{
        .params = &.{ .str, .{ .many = .str } },
        .ret = .str,
    };
    pub const description =
        \\Looks for '{}' placeholders in the receiver string and 
        \\replaces them with the provided arguments.
        \\
    ;
    pub const examples =
        \\$i18n.get!("welcome-message").fmt($page.custom.get!("name"))
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len == 0) return .{ .err = "'fmt' wants at least one argument" };
        var out = std.ArrayList(u8).init(gpa);
        errdefer out.deinit();

        var it = std.mem.splitSequence(u8, str, "{}");
        for (args) |a| {
            const str_arg = switch (a) {
                .string => |s| s,
                else => return .{ .err = "'path' arguments must be strings" },
            };
            const before = it.next() orelse {
                return .{ .err = "fmt: more args than placeholders" };
            };

            try out.appendSlice(before);
            try out.appendSlice(str_arg);
        }

        const last = it.next() orelse {
            return .{ .err = "fmt: more args than placeholders" };
        };

        try out.appendSlice(last);

        if (it.next() != null) {
            return .{ .err = "fmt: more placeholders than args" };
        }

        return .{ .string = try out.toOwnedSlice() };
    }
};

pub const addPath = struct {
    pub const signature: Signature = .{
        .params = &.{ .str, .{ .many = .str } },
        .ret = .str,
    };
    pub const description =
        \\Joins URL path segments automatically adding `/` as needed. 
    ;
    pub const examples =
        \\$site.host_url.addPath("rss.xml")
        \\$site.host_url.addPath("foo/bar", "/baz")
    ;
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
        if (args.len == 0) return .{ .err = "'path' wants at least one argument" };
        var out = std.ArrayList(u8).init(gpa);
        errdefer out.deinit();

        try out.appendSlice(str);
        if (!std.mem.endsWith(u8, str, "/")) {
            try out.append('/');
        }

        for (args) |a| {
            const fx = switch (a) {
                .string => |s| s,
                else => return .{ .err = "'path' arguments must be strings" },
            };

            if (fx.len == 0) continue;
            if (fx[0] == '/') {
                try out.appendSlice(fx[1..]);
            } else {
                try out.appendSlice(fx);
            }
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
    pub fn call(
        str: []const u8,
        gpa: Allocator,
        args: []const Value,
        _: *utils.SuperHTMLResource,
    ) !Value {
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
