const String = @This();

const std = @import("std");
const Writer = std.Io.Writer;
const options = @import("options");
const superhtml = @import("superhtml");
const hl = @import("../highlight.zig");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const log = utils.log;
const Allocator = std.mem.Allocator;
const Value = context.Value;

value: []const u8,

pub fn init(str: []const u8) Value {
    return .{ .string = .{ .value = str } };
}

pub const docs_description = "A string.";
pub const PassByRef = false;
pub const Builtins = struct {
    pub const len = struct {
        pub const signature: Signature = .{ .ret = .Int };
        pub const docs_description =
            \\Returns the length of a string.
            \\
        ;
        pub const examples =
            \\$page.title.len()
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return Value.from(gpa, str.value.len);
        }
    };

    pub const contains = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Returns true if the receiver contains the provided string.
            \\
        ;
        pub const examples =
            \\$page.permalink().contains("/blog/")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const needle = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            return Value.from(gpa, std.mem.indexOf(u8, str.value, needle) != null);
        }
    };

    pub const endsWith = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Returns true if the receiver ends with the provided string.
            \\
        ;
        pub const examples =
            \\$page.permalink().endsWith("/blog/")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const needle = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const result = std.mem.endsWith(u8, str.value, needle);
            log.debug("endsWith('{s}', '{s}') = {}", .{ str.value, needle, result });

            return Value.from(gpa, result);
        }
    };

    pub const startsWith = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Returns true if the receiver starts with the provided string.
            \\
        ;
        pub const examples =
            \\$page.permalink().startsWith("/blog/")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;

            const needle = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            const result = std.mem.startsWith(u8, str.value, needle);

            return Value.from(gpa, result);
        }
    };

    pub const eql = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Returns true if the receiver equals the provided string.
            \\
        ;
        pub const examples =
            \\$page.author.eql("Loris Cro")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected 1 string argument",
            };
            if (args.len != 1) return bad_arg;
            const needle = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            return Value.from(gpa, std.mem.eql(u8, str.value, needle));
        }
    };

    pub const basename = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the last component of a path.
        ;
        pub const examples =
            \\TODO
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            return Value.from(gpa, std.fs.path.basename(str.value));
        }
    };
    pub const suffix = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Many = .String } },
            .ret = .String,
        };
        pub const docs_description =
            \\Concatenates strings together (left-to-right).
            \\
        ;
        pub const examples =
            \\$page.title.suffix("Foo","Bar", "Baz")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len == 0) return .{ .err = "'suffix' wants at least one argument" };
            var out = std.ArrayList(u8).init(gpa);
            errdefer out.deinit();

            try out.appendSlice(str.value);
            for (args) |a| {
                const fx = switch (a) {
                    .string => |s| s.value,
                    else => return .{ .err = "'suffix' arguments must be strings" },
                };

                try out.appendSlice(fx);
            }

            return Value.from(gpa, try out.toOwnedSlice());
        }
    };
    pub const prefix = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Many = .String } },
            .ret = .String,
        };
        pub const docs_description =
            \\Concatenates strings together (left-to-right) and
            \\prepends them to the receiver string.
        ;
        pub const examples =
            \\$page.title.prefix("Foo","Bar", "Baz")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{
                .err = "expected at least 1 string argument",
            };
            if (args.len == 0) return bad_arg;

            var out = std.ArrayList(u8).init(gpa);
            errdefer out.deinit();

            for (args) |a| {
                const fx = switch (a) {
                    .string => |s| s.value,
                    else => return bad_arg,
                };

                try out.appendSlice(fx);
            }

            try out.appendSlice(str.value);

            return Value.from(gpa, try out.toOwnedSlice());
        }
    };
    pub const fmt = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Many = .String } },
            .ret = .String,
        };
        pub const docs_description =
            \\Looks for '{}' placeholders in the receiver string and 
            \\replaces them with the provided arguments.
            \\
        ;
        pub const examples =
            \\$i18n.get!("welcome-message").fmt($page.custom.get!("name"))
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len == 0) return .{ .err = "expected 1 or more argument(s)" };
            var out = std.ArrayList(u8).init(gpa);
            errdefer out.deinit();

            var it = std.mem.splitSequence(u8, str.value, "{}");
            for (args) |a| {
                const str_arg = switch (a) {
                    .string => |s| s.value,
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

            return Value.from(gpa, try out.toOwnedSlice());
        }
    };

    pub const addPath = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .{ .Many = .String } },
            .ret = .String,
        };
        pub const docs_description =
            \\Joins URL path segments automatically adding `/` as needed. 
        ;
        pub const examples =
            \\$site.host_url.addPath("rss.xml")
            \\$site.host_url.addPath("foo/bar", "/baz")
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len == 0) return .{ .err = "'path' wants at least one argument" };
            var out = std.ArrayList(u8).init(gpa);
            errdefer out.deinit();

            try out.appendSlice(str.value);
            if (!std.mem.endsWith(u8, str.value, "/")) {
                try out.append('/');
            }

            for (args) |a| {
                const fx = switch (a) {
                    .string => |s| s.value,
                    else => return .{ .err = "'path' arguments must be strings" },
                };

                if (fx.len == 0) continue;
                if (fx[0] == '/') {
                    try out.appendSlice(fx[1..]);
                } else {
                    try out.appendSlice(fx);
                }
            }

            return Value.from(gpa, try out.toOwnedSlice());
        }
    };
    pub const syntaxHighlight = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .String,
        };
        pub const docs_description =
            \\Applies syntax highlighting to a string.
            \\The argument specifies the language name.
            \\
        ;
        pub const examples =
            \\<pre>
            \\  <code class="ziggy" 
            \\        :html="$page.custom.get('sample').syntaxHighLight('ziggy')"
            \\  ></code>
            \\</pre>
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 1) return .{ .err = "'syntaxHighlight' wants one argument" };
            var out: Writer.Allocating = .init(gpa);
            errdefer out.deinit();

            const lang = switch (args[0]) {
                .string => |s| s.value,
                else => return .{
                    .err = "the argument to 'syntaxHighlight' must be of type string",
                },
            };

            if (!options.enable_treesitter) {
                out.writer.print("{f}", .{superhtml.HtmlSafe{
                    .bytes = str.value,
                }}) catch return error.OutOfMemory;
                return Value.from(gpa, try out.toOwnedSlice());
            }

            hl.highlightCode(gpa, lang, str.value, &out.writer) catch |err| switch (err) {
                error.NoLanguage => return .{ .err = "unable to find a parser for the provided language" },
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .err = "error while syntax highlighting" },
            };

            return Value.from(gpa, out.getWritten());
        }
    };

    pub const parseInt = struct {
        pub const signature: Signature = .{ .ret = .Int };
        pub const docs_description =
            \\Parses an integer out of a string
            \\
        ;
        pub const examples =
            \\$page.custom.get!('not-a-num-for-some-reason').parseInt()
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const parsed = std.fmt.parseInt(i64, str.value, 10) catch |err| {
                return Value.errFmt(gpa, "error parsing int from '{s}': {s}", .{
                    str.value, @errorName(err),
                });
            };

            return Value.from(gpa, parsed);
        }
    };

    pub const parseDate = struct {
        pub const signature: Signature = .{ .ret = .Date };
        pub const docs_description =
            \\Parses a Date out of a string.
        ;
        pub const examples =
            \\$page.custom.get('foo').parseDate()
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const dt = context.DateTime.init(str.value) catch |err| {
                return Value.errFmt(
                    gpa,
                    "unable to parse '{s}' as date: '{s}'",
                    .{ str.value, @errorName(err) },
                );
            };

            return Value.from(gpa, dt);
        }
    };

    pub const splitN = struct {
        pub const signature: Signature = .{
            .params = &.{ .String, .Int },
            .ret = .String,
        };
        pub const docs_description =
            \\Splits the string using the first string argument as delimiter and then
            \\returns the Nth substring (where N is the second argument).
            \\
            \\Indices start from 0.
            \\
        ;
        pub const examples =
            \\$page.author.splitN(" ", 1)
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 2) return .{ .err = "expected 2 (string, int) arguments" };

            const split = switch (args[0]) {
                .string => |s| s.value,
                else => return .{ .err = "the first argument must be a string" },
            };

            const n: usize = switch (args[1]) {
                .int => |i| if (i.value >= 0) @intCast(i.value) else return .{
                    .err = "the second argument must be non-negative",
                },
                else => return .{ .err = "the second argument must be an integer" },
            };

            var it = std.mem.splitSequence(u8, str.value, split);
            const too_short: Value = .{ .err = "sequence ended too early" };
            for (0..n) |_| _ = it.next() orelse return too_short;

            const result = it.next() orelse return too_short;
            return Value.from(gpa, result);
        }
    };
    pub const lower = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns a lowercase version of the target string.
            \\
        ;
        pub const examples =
            \\$page.title.lower()
        ;
        pub fn call(
            str: String,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const l = try gpa.dupe(u8, str.value);
            for (l) |*ch| ch.* = std.ascii.toLower(ch.*);

            return Value.from(gpa, l);
        }
    };
};
