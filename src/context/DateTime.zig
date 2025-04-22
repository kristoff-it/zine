const DateTime = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const zeit = @import("zeit");
const ziggy = @import("ziggy");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const Signature = @import("doctypes.zig").Signature;
const Value = context.Value;
const String = context.String;
const Bool = context.Bool;

_inst: zeit.Instant,

pub fn init(iso8601: []const u8) !DateTime {
    const date = try zeit.Time.fromISO8601(iso8601);
    const inst = date.instant();
    return .{
        ._inst = inst,
    };
}

pub fn initUnix(timestamp: i64) !DateTime {
    const date = try zeit.instant(.{
        .source = .{ .unix_timestamp = timestamp },
    });
    return .{ ._inst = date };
}

pub fn initNow() DateTime {
    const date = zeit.instant(.{}) catch unreachable;
    return .{ ._inst = date };
}

pub const docs_description =
    \\A datetime.
;
pub const Builtins = struct {
    pub const gt = struct {
        pub const signature: Signature = .{
            .params = &.{.Date},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Return true if lhs is later than rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.gt($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            const argument_error: Value = .{ .err = "'gt' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return Bool.init(dt._inst.timestamp > rhs._inst.timestamp);
        }
    };
    pub const lt = struct {
        pub const signature: Signature = .{
            .params = &.{.Date},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Return true if lhs is earlier than rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.lt($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            const argument_error: Value = .{ .err = "'lt' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return Bool.init(dt._inst.timestamp < rhs._inst.timestamp);
        }
    };
    pub const eq = struct {
        pub const signature: Signature = .{
            .params = &.{.Date},
            .ret = .Bool,
        };
        pub const docs_description =
            \\Return true if lhs is the same instant as the rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.eq($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            const argument_error: Value = .{ .err = "'eq' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return Bool.init(dt._inst.timestamp == rhs._inst.timestamp);
        }
    };

    pub const in = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .Date,
        };
        pub const docs_description =
            \\Change the Time Zone offset of a date with the offset
            \\of the location provided.
        ;
        pub const examples =
            \\$page.date.in("Europe/Berlin")
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const arg_err: Value = .{
                .err = "expected 1 string argument",
            };

            if (args.len != 1) return arg_err;

            const loc_str = switch (args[0]) {
                .string => |d| d.value,
                else => return arg_err,
            };

            const location = std.meta.stringToEnum(
                zeit.Location,
                loc_str,
            ) orelse {
                return .errFmt(
                    gpa,
                    "unknown time zone location: '{s}'",
                    .{loc_str},
                );
            };

            if (dt._inst.timezone != &zeit.utc) {
                return .{
                    .err = "can only override dates that are expressed in UTC",
                };
            }

            const tz = try gpa.create(zeit.TimeZone);
            tz.* = zeit.loadTimeZone(gpa, location, null) catch |err| {
                return .errFmt(
                    gpa,
                    "unexpected error while loading '{s}' time zone information: '{s}'",
                    .{ loc_str, @errorName(err) },
                );
            };

            return .{ .date = .{ ._inst = dt._inst.in(tz) } };
        }
    };

    pub const add = struct {
        pub const signature: Signature = .{
            .params = &.{ .Int, .String },
            .ret = .Date,
        };
        pub const docs_description =
            \\ Add a given duration to the receiver date.
            \\ A duration is specified as a number of units, with possible units being:
            \\ - 'second'
            \\ - 'minute'
            \\ - 'hour'
            \\ - 'day'
        ;
        pub const examples =
            \\$page.date.add(1, 'day').add(1, 'hour')
        ;
        pub fn call(
            dt: DateTime,
            _: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const arg_err: Value = .{
                .err = "expected 1 non-negative int and 1 string argument",
            };

            if (args.len != 2) return arg_err;

            const num: usize = switch (args[0]) {
                .int => |d| if (d.value >= 0) @intCast(d.value) else return .{
                    .err = "number of units must be positive",
                },
                else => return arg_err,
            };

            const unit_str = switch (args[1]) {
                .string => |d| d.value,
                else => return arg_err,
            };

            const Unit = enum { second, minute, hour, day };
            const unit = std.meta.stringToEnum(Unit, unit_str) orelse {
                return .{ .err = "unknown duration unit" };
            };

            const d: zeit.Duration = switch (unit) {
                .second => .{ .seconds = num },
                .minute => .{ .minutes = num },
                .hour => .{ .hours = num },
                .day => .{ .days = num },
            };

            const new = dt._inst.add(d) catch return .{
                .err = "addition caused overflow",
            };

            return .{ .date = .{ ._inst = new } };
        }
    };

    pub const sub = struct {
        pub const signature: Signature = .{
            .params = &.{ .Int, .String },
            .ret = .Date,
        };
        pub const docs_description =
            \\ Subtract a given duration to the receiver date.
            \\ A duration is specified as a number of units, with possible units being:
            \\ - 'second'
            \\ - 'minute'
            \\ - 'hour'
            \\ - 'day'
        ;
        pub const examples =
            \\$page.date.sub(1, 'hour').add(1, 'hour').eq($page.date)
        ;
        pub fn call(
            dt: DateTime,
            _: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const arg_err: Value = .{
                .err = "expected 1 non-negative int and 1 string argument",
            };

            if (args.len != 2) return arg_err;

            const num: usize = switch (args[0]) {
                .int => |d| if (d.value >= 0) @intCast(d.value) else return .{
                    .err = "number of units must be positive",
                },
                else => return arg_err,
            };

            const unit_str = switch (args[1]) {
                .string => |d| d.value,
                else => return arg_err,
            };

            const Unit = enum { second, minute, hour, day };
            const unit = std.meta.stringToEnum(Unit, unit_str) orelse {
                return .{ .err = "unknown duration unit" };
            };

            const d: zeit.Duration = switch (unit) {
                .second => .{ .seconds = num },
                .minute => .{ .minutes = num },
                .hour => .{ .hours = num },
                .day => .{ .days = num },
            };

            const new = dt._inst.subtract(d) catch return .{
                .err = "subtraction caused underflow",
            };

            return .{ .date = .{ ._inst = new } };
        }
    };

    pub const format = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .String,
        };
        pub const docs_description =
            \\Formats a datetime according to the specified format string.
            \\
            \\Zine uses Go-style format strings, which are all variations based
            \\on a "magic date":
            \\
            \\- `Mon Jan 2 15:04:05 MST 2006`
            \\
            \\By tweaking its components you can specify various formatting styles.
        ;
        pub const examples =
            \\$page.date.format("January 02, 2006")
            \\$page.date.format("06-Jan-02")
            \\$page.date.format("2006/01/02")
            \\$page.date.format("2006/01/02 15:04 MST")
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const argument_error: Value = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return argument_error;

            const fmt_string = switch (args[0]) {
                .string => |s| s.value,
                else => return argument_error,
            };

            var buf = std.ArrayList(u8).init(gpa);
            errdefer buf.deinit();

            dt._inst.time().gofmt(buf.writer(), fmt_string) catch return error.OutOfMemory;

            return String.init(try buf.toOwnedSlice());
        }
    };

    pub const formatHTTP = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Formats a datetime according to the HTTP spec.
            \\
        ;
        pub const examples =
            \\$page.date.formatHTTP()
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const argument_error: Value = .{
                .err = "'formatHTTP' wants no argument",
            };
            if (args.len != 0) return argument_error;

            // Fri, 16 Jun 2023 00:00:00 +0000
            const dse = zeit.daysSinceEpoch(dt._inst.unixTimestamp());
            const weekday = zeit.weekdayFromDays(dse);

            const zdt = dt._inst.time();
            const formatted_date = try std.fmt.allocPrint(
                gpa,
                "{s}, {:0>2} {s} {} {:0>2}:{:0>2}:{:0>2} +0000",
                .{
                    weekday.shortName(),
                    zdt.day,
                    zdt.month.shortName(),
                    zdt.year,
                    zdt.hour,
                    zdt.minute,
                    zdt.second,
                },
            );

            return String.init(formatted_date);
        }
    };
};
pub const ziggy_options = struct {
    //     pub fn stringify(
    //         value: DateTime,
    //         opts: ziggy.serializer.StringifyOptions,
    //         indent_level: usize,
    //         depth: usize,
    //         writer: anytype,
    //     ) !void {
    //         _ = opts;
    //         _ = indent_level;
    //         _ = depth;
    //         std.debug.panic("still used!", .{});

    //         try writer.print("@date(\"{}\")", .{std.zig.fmtEscapes(value._string_repr)});
    //     }

    pub fn parse(
        p: *ziggy.Parser,
        first_tok: ziggy.Tokenizer.Token,
    ) !DateTime {
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

        return DateTime.init(src) catch {
            return p.addError(.{
                .syntax = .{
                    .name = first_tok.tag.lexeme(),
                    .sel = first_tok.loc.getSelection(p.code),
                },
            });
        };
    }
};

pub fn lessThan(self: DateTime, rhs: DateTime) bool {
    return self._inst.timestamp < rhs._inst.timestamp;
}

pub fn eql(self: DateTime, rhs: DateTime) bool {
    return self._inst.timestamp == rhs._inst.timestamp;
}
