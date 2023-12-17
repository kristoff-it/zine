const std = @import("std");
const scripty = @import("scripty");

pub const Page = struct {
    title: []const u8,
    author: []const u8,
    layout: []const u8,
    draft: bool = false,
    tags: []const []const u8 = &.{},
    custom: std.json.Value = .null,
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

        if (std.mem.eql(u8, path, "content")) {
            return .{ .ok = .{ .string = self.content } };
        }
        if (std.mem.eql(u8, path, "title")) {
            return .{ .ok = .{ .string = self.title } };
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

        std.debug.panic("TODO: implement `{s}` for Zine.Template", .{path});
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
