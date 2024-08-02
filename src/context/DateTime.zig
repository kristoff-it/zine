const DateTime = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const zeit = @import("zeit");
const ziggy = @import("ziggy");
const utils = @import("utils.zig");
const Signature = @import("docgen.zig").Signature;
const Value = @import("../context.zig").Value;

_dt: zeit.Time,
// Use inst() to access this field
_inst: zeit.Instant,
_string_repr: []const u8,

pub fn init(iso8601: []const u8) !DateTime {
    const date = try zeit.Time.fromISO8601(iso8601);
    return .{
        ._string_repr = iso8601,
        ._dt = date,
        ._inst = date.instant(),
    };
}

pub const Builtins = struct {
    pub const gt = struct {
        pub const signature: Signature = .{ .params = &.{.date}, .ret = .bool };
        pub const description =
            \\Return true if lhs is later than rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.gt($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            const argument_error = .{ .err = "'gt' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return .{ .bool = dt._inst.timestamp > rhs._inst.timestamp };
        }
    };
    pub const lt = struct {
        pub const signature: Signature = .{ .params = &.{.date}, .ret = .bool };
        pub const description =
            \\Return true if lhs is earlier than rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.lt($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            const argument_error = .{ .err = "'lt' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return .{ .bool = dt._inst.timestamp < rhs._inst.timestamp };
        }
    };
    pub const eq = struct {
        pub const signature: Signature = .{ .params = &.{.date}, .ret = .bool };
        pub const description =
            \\Return true if lhs is the same instant as the rhs (the argument).
            \\
        ;
        pub const examples =
            \\$page.date.eq($page.custom.expiry_date)
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            const argument_error = .{ .err = "'eq' wants one (date) argument" };
            if (args.len != 1) return argument_error;

            const rhs = switch (args[0]) {
                .date => |d| d,
                else => return argument_error,
            };

            return .{ .bool = dt._inst.timestamp == rhs._inst.timestamp };
        }
    };
    pub const format = struct {
        pub const signature: Signature = .{ .params = &.{.str}, .ret = .str };
        pub const description =
            \\Formats a datetime according to the specified format string.
            \\
        ;
        pub const examples =
            \\$page.date.format("January 02, 2006")
            \\$page.date.format("06-Jan-02")
            \\$page.date.format("2006/01/02")
        ;
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const argument_error = .{ .err = "'format' wants one (string) argument" };
            if (args.len != 1) return argument_error;
            const string = switch (args[0]) {
                .string => |s| s,
                else => return argument_error,
            };
            inline for (@typeInfo(DateFormats).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, string)) {
                    return .{ .string = try @call(.auto, @field(DateFormats, decl.name), .{ dt, gpa }) };
                }
            } else {
                return .{ .err = "unsupported date format" };
            }
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
        pub fn call(
            dt: DateTime,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const argument_error = .{ .err = "'formatHTTP' wants no argument" };
            if (args.len != 0) return argument_error;

            // Fri, 16 Jun 2023 00:00:00 +0000
            const dse = zeit.daysSinceEpoch(dt._inst.unixTimestamp());
            const weekday = zeit.weekdayFromDays(dse);

            const formatted_date = try std.fmt.allocPrint(
                gpa,
                "{s}, {:0>2} {s} {} 00:00:00 +0000",
                .{
                    weekday.shortName(),
                    dt._dt.day,
                    dt._dt.month.shortName(),
                    dt._dt.year,
                },
            );

            return .{ .string = formatted_date };
        }
    };
};
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

        try writer.print("@date(\"{}\")", .{std.zig.fmtEscapes(value._string_repr)});
    }

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

const DateFormats = struct {
    pub fn @"January 02, 2006"(dt: DateTime, gpa: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(gpa, "{s} {:0>2}, {}", .{
            dt._dt.month.name(),
            dt._dt.day,
            dt._dt.year,
        });
    }
    pub fn @"06-Jan-02"(dt: DateTime, gpa: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(gpa, "{:0>2}-{s}-{:0>2}", .{
            dt._dt.day,
            dt._dt.month.shortName(),
            @mod(dt._dt.year, 100),
        });
    }
    pub fn @"2006/01/02"(dt: DateTime, gpa: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(gpa, "{}/{:0>2}/{:0>2}", .{
            dt._dt.year,
            @intFromEnum(dt._dt.month),
            dt._dt.day,
        });
    }
};
