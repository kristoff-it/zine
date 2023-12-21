const std = @import("std");
const scripty = @import("scripty");
const super = @import("super");
const datetime = @import("datetime").datetime;
const timezones = @import("datetime").timezones;
const DateTime = datetime.Datetime;
const Date = datetime.Date;
const Time = datetime.Time;

const TemplateContext = struct {
    page: Page,

    // Globals specific to Super
    loop: super.LoopContext,
    @"if": super.Optional,
};

pub const Page = struct {
    title: []const u8,
    description: []const u8 = "",
    author: []const u8,
    date: []const u8,
    layout: []const u8,
    draft: bool = false,
    tags: []const []const u8 = &.{},
    // custom: std.json.Value = .null,
    _meta: struct {
        word_count: usize = 0,
        prev: ?*Page = null,
        next: ?*Page = null,
    } = .{},
    content: []const u8 = "",

    pub const ScriptyBuiltins = struct {
        pub fn nextPage(self: *Page, gpa: std.mem.Allocator, args: []const Value) Value {
            if (args.len != 0) return Value.err("expected 0 arguments");
            if (self._meta.next) |next| {
                return super.Optional.something(Value.from(gpa, next));
            } else {
                return super.Optional.nothing();
            }
        }
        pub fn prevPage(self: *Page, gpa: std.mem.Allocator, args: []const Value) Value {
            if (args.len != 0) return Value.err("expected 0 arguments");
            if (self._meta.prev) |prev| {
                return super.Optional.something(Value.from(gpa, prev));
            } else {
                return super.Optional.nothing();
            }
        }
    };
};

const Value = union(enum) {
    page: *Page,
    super_iterator: *LoopIterator,
    super_loop_ctx: *LoopContext,
    super_optional: *Optional,
    string: super.ManagedString,
    date: DateTime,
    bool: bool,
    int: usize,
    float: f64,
    err: []const u8,

    pub const LoopIterator = super.LoopIterator(Value);
    pub const LoopContext = super.LoopContext(Value);
    pub const Optional = super.Optional(Value);

    pub const error_case = .err;
    pub fn err(msg: []const u8) Value {
        return .{ .err = msg };
    }

    pub fn fromStringLiteral(ms: scripty.ManagedString) !Value {
        return .{ .string = .{ .bytes = ms.bytes, .must_free = ms.must_free } };
    }

    pub fn fromNumberLiteral(bytes: []const u8) !Value {
        _ = bytes;
        return .{ .int = 0 };
    }

    pub fn fromBooleanLiteral(b: bool) !Value {
        return .{ .bool = b };
    }

    pub fn from(gpa: std.mem.Allocator, v: anytype) !Value {
        switch(@TypeOf(v)) {
            *Page => .{ .page = v},
            *LoopIterator => .{ .super_iterator = } 
        }
    }
};
