const std = @import("std");
const ziggy = @import("ziggy");
const context = @import("context.zig");
const Value = context.Value;

pub const Signature = struct {
    params: []const ScriptyParam = &.{},
    ret: ScriptyParam,

    pub fn format(
        s: Signature,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try out_stream.writeAll("(");
        for (s.params, 0..) |p, idx| {
            try out_stream.writeAll(p.link(true));
            if (idx < s.params.len - 1) {
                try out_stream.writeAll(", ");
            }
        }
        try out_stream.writeAll(") -> ");
        try out_stream.writeAll(s.ret.link(false));
    }
};

pub const ScriptyParam = union(enum) {
    Content,
    anydirective,
    Section,
    Block,
    Heading,
    Link,
    Image,
    Video,
    Code,
    str,
    bool,
    err,
    Many: Base,
    Opt: Base,

    pub const Base = enum {
        str,
    };

    pub fn fromField(T: type, fs: []const u8) ScriptyParam {
        const fe = std.meta.stringToEnum(std.meta.FieldEnum(T), fs).?;
        return switch (fe) {
            .block => .Block,
            .section => .Section,
            .heading => .Heading,
            .image => .Image,
            .video => .Video,
            .link => .Link,
            .code => .Code,
        };
    }

    pub fn fromType(t: type) ScriptyParam {
        return switch (t) {
            context.Content => .Content,
            context.Directive => .anydirective,
            context.Section => .Section,
            context.Block => .Block,
            context.Heading => .Heading,
            context.Link => .Link,
            context.Image => .Image,
            context.Video => .Video,
            context.Code => .Code,

            // context.Template => .any,
            // ?context.Value => .any,
            // context.Page, *const context.Page => .Page,
            // context.Site, *const context.Site => .Site,
            // context.Build => .Build,
            // superhtml.utils.Ctx(context.Value) => .Ctx,
            // context.Page.Alternative => .Alternative,
            // context.Asset => .Asset,
            // // context.Slice => .any,
            // context.Optional, ?*const context.Optional => .{ .Opt = .any },
            // context.String => .String,
            // context.Bool => .Bool,
            // context.Int => .Int,
            // context.Float => .Float,
            // context.DateTime => .Date,
            // context.Map, context.Map.ZiggyMap => .{ .Map = .any },
            // context.Map.KV => .KV,
            // context.Iterator => .Iterator,
            // ?*context.Iterator => .{ .Opt = .Iterator },
            // []const context.Page.Alternative => .{ .Many = .Alternative },
            // []const u8 => .String,
            // ?[]const u8 => .{ .Opt = .String },
            // []const []const u8 => .{ .Many = .String },
            // bool => .Bool,
            // usize => .Int,
            // ziggy.dynamic.Value => .any,
            // context.Value => .any,
            else => @compileError("TODO: add support for " ++ @typeName(t)),
        };
    }

    pub fn string(
        p: ScriptyParam,
        comptime is_fn_param: bool,
    ) []const u8 {
        switch (p) {
            .Many => |m| switch (m) {
                inline else => |mm| {
                    const dots = if (is_fn_param) "..." else "";
                    return "[" ++ @tagName(mm) ++ dots ++ "]";
                },
            },
            .Opt => |o| switch (o) {
                inline else => |oo| return "?" ++ @tagName(oo),
            },
            inline else => return @tagName(p),
        }
    }
    pub fn link(
        p: ScriptyParam,
        comptime is_fn_param: bool,
    ) []const u8 {
        switch (p) {
            .Many => |m| switch (m) {
                .str => {
                    const dots = if (is_fn_param) "..." else "";
                    return std.fmt.comptimePrint(
                        \\[{s}{s}]
                    , .{ @tagName(m), dots });
                },
                // inline else => |mm| {
                //     const dots = if (is_fn_param) "..." else "";
                //     return std.fmt.comptimePrint(
                //         \\[[{0s}]($link.ref("{0s}")){1s}]
                //     , .{ @tagName(mm), dots });
                // },
            },
            .Opt => |o| switch (o) {
                inline else => |oo| return comptime std.fmt.comptimePrint(
                    \\?{s}
                , .{@tagName(oo)}),
            },
            .str,
            .bool,
            => {
                return @tagName(p);
            },
            inline else => |_, t| return comptime std.fmt.comptimePrint(
                \\[{0s}]($link.ref("{0s}"))
            , .{@tagName(t)}),
        }
    }

    pub fn id(p: ScriptyParam) []const u8 {
        switch (p) {
            .Opt,
            .Many,
            => |o| switch (o) {
                inline else => |oo| return @tagName(oo),
            },
            inline else => return @tagName(p),
        }
    }
};
