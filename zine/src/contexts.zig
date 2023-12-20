const std = @import("std");
const scripty = @import("scripty");
const datetime = @import("datetime").datetime;
const timezones = @import("datetime").timezones;
const DateTime = datetime.Datetime;
const Date = datetime.Date;
const Time = datetime.Time;

pub const Page = struct {
    title: []const u8,
    description: []const u8 = "",
    author: []const u8,
    date: []const u8,
    layout: []const u8,
    draft: bool = false,
    tags: []const []const u8 = &.{},
    custom: std.json.Value = .null,
    _meta: struct {
        word_count: usize = 0,
        prev: ?*Page = null,
        next: ?*Page = null,
    } = .{},
    content: []const u8 = "",

    pub fn externalValue(self: *Page) scripty.ExternalValue {
        return .{
            .value = self,
            .dot_fn = &dot,
            .call_fn = &call,
            .value_fn = &value,
        };
    }

    fn dot(op: *anyopaque, path: []const u8, arena: std.mem.Allocator) scripty.ScriptResult {
        const self: *Page = @alignCast(@ptrCast(op));

        if (std.mem.eql(u8, path, "title")) {
            return .{ .ok = .{ .string = self.title } };
        }
        if (std.mem.eql(u8, path, "description")) {
            return .{ .ok = .{ .string = self.description } };
        }
        if (std.mem.eql(u8, path, "author")) {
            return .{ .ok = .{ .string = self.author } };
        }
        if (std.mem.eql(u8, path, "content")) {
            return .{ .ok = .{ .string = self.content } };
        }
        if (std.mem.eql(u8, path, "word_count")) {
            return .{ .ok = .{ .int = self._meta.word_count } };
        }
        if (std.mem.eql(u8, path, "prev")) {
            const prev = self._meta.prev orelse return .{ .ok = .nil };
            return .{ .ok = .{ .external = prev.externalValue() } };
        }
        if (std.mem.eql(u8, path, "next")) {
            const next = self._meta.next orelse return .{ .ok = .nil };
            return .{ .ok = .{ .external = next.externalValue() } };
        }
        if (std.mem.eql(u8, path, "has")) {
            std.debug.print("given out has!\n", .{});
            return .{ .ok = .{ .function = has } };
        }
        if (std.mem.eql(u8, path, "hasAny")) {
            std.debug.print("given out has!\n", .{});
            return .{ .ok = .{ .function = hasAny } };
        }
        if (std.mem.eql(u8, path, "date")) {
            const d: DateTime = .{
                .date = Date.parseIso(self.date[0..10]) catch return .{ .err = "unable to parse date" },
                .time = Time.create(0, 0, 0, 0) catch unreachable,
                .zone = &timezones.UTC,
            };
            return .{ .ok = .{ .date = d } };
        }
        if (std.mem.eql(u8, path, "tags")) {
            const res = arena.alloc(scripty.Value, self.tags.len) catch {
                return .{ .err = "oom" };
            };

            for (res, self.tags) |*r, t| r.* = .{ .string = t };

            return .{ .ok = .{ .array = res } };
        }

        std.debug.panic("TODO: implement dot `{s}` for Zine.Page", .{path});
    }

    fn call(op: *anyopaque, args: []const scripty.Value) scripty.ScriptResult {
        _ = op;
        _ = args;
        @panic("TODO call on zine page context");
    }

    fn value(op: *anyopaque) scripty.ScriptResult {
        _ = op;
        @panic("TODO value on zine page context");
    }
};

fn has(args: []const scripty.Value, _: std.mem.Allocator) scripty.ScriptResult {
    std.debug.print("has was called!\n", .{});
    const self: *Page = @alignCast(@ptrCast(args[0].external.value));
    var result = true;
    for (args[1..]) |x| if (std.mem.eql(u8, x.string, "next")) {
        if (self._meta.next == null) result = false;
    } else if (std.mem.eql(u8, x.string, "prev")) {
        if (self._meta.prev == null) result = false;
    };

    return .{ .ok = .{ .bool = result } };
}

fn hasAny(args: []const scripty.Value, _: std.mem.Allocator) scripty.ScriptResult {
    std.debug.print("hasAny was called!\n", .{});
    const self: *Page = @alignCast(@ptrCast(args[0].external.value));
    var result = false;
    for (args[1..]) |x| if (std.mem.eql(u8, x.string, "next")) {
        if (self._meta.next != null) result = true;
    } else if (std.mem.eql(u8, x.string, "prev")) {
        if (self._meta.prev != null) result = true;
    };

    return .{ .ok = .{ .bool = result } };
}

pub const Template = struct {
    page: Page,

    pub fn externalValue(self: *Template) scripty.ExternalValue {
        return .{
            .value = self,
            .dot_fn = &dot,
            .call_fn = &call,
            .value_fn = &value,
        };
    }

    fn dot(op: *anyopaque, path: []const u8, arena: std.mem.Allocator) scripty.ScriptResult {
        const self: *Template = @alignCast(@ptrCast(op));
        _ = arena;

        if (std.mem.eql(u8, path, "page")) {
            return .{ .ok = .{ .external = self.page.externalValue() } };
        }

        std.debug.panic("TODO: explain that '${s}' doesn't exist.", .{path});
    }

    fn call(op: *anyopaque, args: []const scripty.Value) scripty.ScriptResult {
        _ = op;
        _ = args;
        @panic("TODO call on zine template context");
    }

    fn value(op: *anyopaque) scripty.ScriptResult {
        _ = op;
        @panic("TODO value on zine template context");
    }
};

// fn simpleStructDot(comptime T: type) scripty.DotFn {
//     return struct {
//         pub fn dotFn(
//             op: *anyopaque,
//             path: []const u8,
//             arena: std.mem.Allocator,
//         ) scripty.ScriptResult {
//             const self: *T = @alignCast(@ptrCast(op));

//             const info = @typeInfo(T);
//             if (info != .Struct) {
//                 @compileError("simpleStructDot can only be used with structs");
//             }

//             inline for (info.Struct.fields) |field| {
//                 if (std.mem.eql(u8, field.name, path)) {
//                     return scripty.Value.from(@field(self, field.name), arena);
//                 }
//             }
//         }
//     }.dotFn;
// }
