const std = @import("std");
const Writer = std.Io.Writer;
const ziggy = @import("ziggy");
const superhtml = @import("superhtml");
const context = @import("../context.zig");
const Value = context.Value;

pub const Signature = struct {
    params: []const ScriptyParam = &.{},
    ret: ScriptyParam,

    pub fn format(s: Signature, w: *Writer) !void {
        try w.writeAll("(");
        for (s.params, 0..) |p, idx| {
            @setEvalBranchQuota(1_000_000);
            try w.writeAll(p.link(true));
            if (idx < s.params.len - 1) {
                try w.writeAll(", ");
            }
        }
        try w.writeAll(") -> ");
        try w.writeAll(s.ret.link(false));
    }
};

pub const ScriptyParam = union(enum) {
    Site,
    Page,
    Build,
    Git,
    Asset,
    Alternative,
    ContentSection,
    Footnote,
    Iterator,
    Array,
    String,
    Int,
    Float,
    Bool,
    Date,
    Ctx,
    KV,
    any,
    err,
    Map: Base,
    Opt: Base,
    Many: Base,

    pub const Base = union(enum) {
        Site,
        Page,
        Alternative,
        ContentSection,
        Footnote,
        Iterator,
        String,
        Int,
        Bool,
        Date,
        KV,
        any,
        Many: Base2,

        pub const Base2 = enum {
            Footnote,
        };
    };

    pub fn fromType(t: type) ScriptyParam {
        return switch (t) {
            context.Template => .any,
            ?context.Value => .any,
            context.Page, *const context.Page => .Page,
            context.Site, *const context.Site => .Site,
            context.Build => .Build,
            context.Git => .Git,
            superhtml.utils.Ctx(context.Value) => .Ctx,
            context.Page.Alternative => .Alternative,
            context.Page.ContentSection => .ContentSection,
            context.Page.Footnote => .Footnote,
            context.Asset => .Asset,
            // context.Slice => .any,
            context.Optional, ?*const context.Optional => .{ .Opt = .any },
            context.String => .String,
            context.Bool => .Bool,
            context.Int => .Int,
            context.Float => .Float,
            context.DateTime => .Date,
            context.Map, context.Map.ZiggyMap => .{ .Map = .any },
            context.Map.KV => .KV,
            context.Array => .Array,
            context.Iterator => .Iterator,
            ?*context.Iterator => .{ .Opt = .Iterator },
            []const context.Page.Alternative => .{ .Many = .Alternative },
            []const context.Page.Footnote => .{ .Many = .Footnote },
            ?[]const context.Page.Footnote => .{ .Opt = .{ .Many = .Footnote } },
            []const u8 => .String,
            ?[]const u8 => .{ .Opt = .String },
            []const []const u8 => .{ .Many = .String },
            bool => .Bool,
            usize => .Int,
            ziggy.dynamic.Value => .any,
            context.Value => .any,
            else => @compileError("TODO: add support for " ++ @typeName(t)),
        };
    }

    pub fn string(
        p: ScriptyParam,
        comptime is_fn_param: bool,
    ) []const u8 {
        switch (p) {
            inline .Many => |m| switch (m) {
                inline else => {
                    const dots = if (is_fn_param) "..." else "";
                    return "[" ++ @tagName(m) ++ dots ++ "]";
                },
            },
            .Opt => |o| switch (o) {
                .Many => |om| switch (om) {
                    inline else => |omm| return "?[" ++ @tagName(omm) ++ "]",
                },
                inline else => return "?" ++ @tagName(o),
            },
            inline else => return @tagName(p),
        }
    }
    pub fn link(
        p: ScriptyParam,
        comptime is_fn_param: bool,
    ) []const u8 {
        switch (p) {
            inline .Many => |m| switch (m) {
                inline else => {
                    const dots = if (is_fn_param) "..." else "";
                    return std.fmt.comptimePrint(
                        \\[[{0t}]($link.ref("{0t}")){1s}]{2s}
                    , .{
                        m, dots, if (is_fn_param or m == .any) "" else 
                        \\ *(see also [[any]]($link.ref("Array")))*   
                    });
                },
            },
            inline .Opt => |o| switch (o) {
                inline .Many => |om| switch (om) {
                    inline else => |omm| return comptime std.fmt.comptimePrint(
                        \\?[[{0t}]($link.ref("{0t}"))]
                    , .{omm}),
                },
                inline else => return comptime std.fmt.comptimePrint(
                    \\?[{0t}]($link.ref("{0t}"))
                , .{o}),
            },
            inline else => |_, t| return comptime std.fmt.comptimePrint(
                \\[{0t}]($link.ref("{0t}"))
            , .{t}),
        }
    }

    pub fn id(p: ScriptyParam) []const u8 {
        switch (p) {
            .Opt, .Many => |o| switch (o) {
                inline else => return @tagName(o),
            },
            inline else => return @tagName(p),
        }
    }
};
