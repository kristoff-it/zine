const std = @import("std");
const ziggy = @import("ziggy");
const context = @import("../context.zig");
const Value = context.Value;

pub const Signature = struct {
    params: []const ScriptyParam = &.{},
    ret: ScriptyParam,
};

pub const ScriptyParam = union(enum) {
    Site,
    Page,
    Build,
    Assets,
    Asset,
    Alternative,
    Translation,
    str,
    int,
    bool,
    date,
    dyn,
    opt: Base,
    many: Base,

    pub const Base = enum {
        Site,
        Page,
        Alternative,
        Translation,
        str,
        int,
        bool,
        date,
        dyn,
    };

    pub fn fromType(t: type) ScriptyParam {
        return switch (t) {
            context.Page, *context.Page => .Page,
            []const u8 => .str,
            []const []const u8 => .{ .many = .str },
            context.DateTime => .date,
            usize => .int,
            bool => .bool,
            ziggy.dynamic.Value => .dyn,
            context.Page.Alternative => .Alternative,
            []const context.Page.Alternative => .{ .many = .Alternative },
            context.Page.Translation => .Translation,
            []const context.Page.Translation => .{ .many = .Translation },

            else => @compileError("TODO: add support for " ++ @typeName(t)),
        };
    }

    pub fn name(p: ScriptyParam, comptime is_fn_param: bool) []const u8 {
        switch (p) {
            .many => |m| switch (m) {
                inline else => |mm| {
                    const dots = if (is_fn_param) "..." else "";
                    return "[" ++ dots ++ @tagName(mm) ++ "]";
                },
            },
            .opt => |o| switch (o) {
                inline else => |oo| return "?" ++ @tagName(oo),
            },
            inline else => return @tagName(p),
        }
    }
};
