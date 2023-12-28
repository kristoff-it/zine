const std = @import("std");
const scripty = @import("scripty");
const super = @import("super");
const datetime = @import("datetime").datetime;
const timezones = @import("datetime").timezones;

pub const DateTime = struct {
    _dt: datetime.Datetime,
    _string_repr: []const u8,

    pub fn jsonStringify(value: DateTime, jws: anytype) !void {
        try jws.write(value._string_repr);
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!DateTime {
        const raw_date = try source.nextAllocMax(allocator, .alloc_always, options.max_value_len.?);
        if (raw_date != .allocated_string) return error.SyntaxError;

        const date = datetime.Date.parseIso(raw_date.allocated_string[0..10]) catch return error.SyntaxError;
        return .{
            ._string_repr = raw_date.allocated_string,
            ._dt = .{
                .date = date,
                .time = datetime.Time.create(0, 0, 0, 0) catch unreachable,
                .zone = &timezones.UTC,
            },
        };
    }

    pub fn lessThan(self: DateTime, rhs: DateTime) bool {
        return self._dt.lt(rhs._dt);
    }
};

pub const Template = struct {
    page: Page,

    // Globals specific to Super
    loop: ?Value = null,
    @"if": ?Value = null,

    pub const dot = scripty.defaultDot(Template, Value);
};

pub const Page = struct {
    title: []const u8,
    description: []const u8 = "",
    author: []const u8,
    date: DateTime,
    layout: []const u8,
    draft: bool = false,
    tags: []const []const u8 = &.{},
    _meta: struct {
        word_count: usize = 0,
        prev: ?*Page = null,
        next: ?*Page = null,
    } = .{},
    custom: std.json.Value = .null,
    content: []const u8 = "",

    pub const dot = scripty.defaultDot(Page, Value);
    pub const PassByRef = true;
    pub const Builtins = struct {
        pub fn wordCount(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            return .{ .int = self._meta.word_count };
        }

        pub fn nextPage(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            if (self._meta.next) |next| {
                return .{ .optional = .{ .page = next } };
            } else {
                return .{ .optional = null };
            }
        }
        pub fn prevPage(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };
            if (self._meta.prev) |prev| {
                return .{ .optional = .{ .page = prev } };
            } else {
                return .{ .optional = null };
            }
        }
        pub fn hasNext(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
            const p = try nextPage(self, gpa, args);
            return switch (p) {
                .err => p,
                .optional => |opt| if (opt == null)
                    .{ .bool = false }
                else
                    .{ .bool = true },
                else => unreachable,
            };
        }
        pub fn hasPrev(self: *Page, gpa: std.mem.Allocator, args: []const Value) !Value {
            const p = try prevPage(self, gpa, args);
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
};

pub const Value = union(enum) {
    template: *Template,
    page: *Page,
    dynamic: std.json.Value,
    iterator: Iterator,
    iterator_element: IterElement,
    optional: ?Optional,
    string: []const u8,
    date: DateTime,
    bool: bool,
    int: usize,
    float: f64,
    err: []const u8,

    pub const call = scripty.defaultCall(Value);

    pub const Optional = union(enum) {
        page: *Page,
        iter_elem: IterElement,
    };

    pub const Iterator = union(enum) {
        string_it: SliceIterator([]const u8),
        // value_it: SliceIterator(Value),

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

                    return .{
                        .iter_elem = .{
                            .it = n,
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
        it: []const u8,
        idx: usize,
        first: bool,
        last: bool,

        pub const dot = scripty.defaultDot(IterElement, Value);
    };

    pub fn fromStringLiteral(s: []const u8) Value {
        return .{ .string = s };
    }

    pub fn fromNumberLiteral(bytes: []const u8) Value {
        const num = std.fmt.parseInt(usize, bytes, 10) catch {
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
            *Page => .{ .page = v },
            IterElement => .{ .iteration_element = v },
            DateTime => .{ .date = v },
            []const u8 => .{ .string = v },
            bool => .{ .bool = v },
            usize => .{ .int = v },
            ?Value => if (v) |o| o else .{ .err = "trying to access nil value" },

            ?Optional => .{ .optional = v orelse @panic("TODO: null optional reached Value.from") },
            std.json.Value => .{ .dynamic = v },
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
            pub fn len(str: []const u8, gpa: std.mem.Allocator, args: []const Value) !Value {
                if (args.len != 0) return .{ .err = "'len' wants no arguments" };
                return Value.from(gpa, str.len);
            }
        };
        // const DynamicBuiltins = struct {
        //     pub fn get(dyn: Dynamic, gpa: std.mem.Allocator, args: []const Value) Value {
        //         _ = gpa;
        //         _ = dyn;
        //         if (args.len != 1) return .{ .err = "'get' wants 1 string argument" };
        //         @panic("TODO: get() for Dynamic");
        //     }
        // };

        const DateBuiltins = struct {
            pub fn format(dt: DateTime, gpa: std.mem.Allocator, args: []const Value) !Value {
                std.debug.print("date.format\n", .{});
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

                std.debug.print("formatted date: {s}\n", .{formatted_date});

                return .{ .string = formatted_date };
            }
        };
        const BoolBuiltins = struct {
            pub fn not(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
                if (args.len != 0) return .{ .err = "'not' wants no arguments" };
                return .{ .bool = !b };
            }
            pub fn @"and"(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
                if (args.len == 0) return .{ .err = "'and' wants at least one argument" };
                for (args) |a| switch (a) {
                    .bool => {},
                    else => return .{ .err = "wrong argument type" },
                };
                if (!b) return .{ .bool = false };
                for (args) |a| if (!a.bool) return .{ .bool = false };

                return .{ .bool = true };
            }
            pub fn @"or"(b: bool, _: std.mem.Allocator, args: []const Value) !Value {
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
        const IntBuiltins = struct {
            pub fn plus(num: usize, _: std.mem.Allocator, args: []const Value) !Value {
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
            pub fn div(num: usize, _: std.mem.Allocator, args: []const Value) !Value {
                const argument_error = .{ .err = "'div' wants one (int|float) argument" };
                if (args.len != 1) return argument_error;

                switch (args[0]) {
                    .int => |den| {
                        const res = std.math.divTrunc(usize, num, den) catch |err| {
                            return .{ .err = @errorName(err) };
                        };

                        return .{ .int = res };
                    },
                    .float => @panic("TODO: div with float argument"),
                    else => return argument_error,
                }
            }
        };
        return switch (tag) {
            .page => Page.Builtins,
            .string => StringBuiltins,
            .date => DateBuiltins,
            .int => IntBuiltins,
            .bool => BoolBuiltins,
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
        pub fn next(self: *@This(), gpa: std.mem.Allocator) ?Element {
            _ = gpa;
            if (self.idx == self.items.len) return null;
            const result = self.items[self.idx];
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
