const std = @import("std");
const ziggy = @import("ziggy");
const contexts = @import("contexts.zig");
const Value = contexts.Value;

pub const Signature = struct {
    params: []const ScriptyParam = &.{},
    ret: ScriptyParam,
};

pub const ScriptyParam = union(enum) {
    Site,
    Page,
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
            contexts.Page => .Page,
            []const u8 => .str,
            []const []const u8 => .{ .many = .str },
            contexts.DateTime => .date,
            usize => .int,
            bool => .bool,
            ziggy.dynamic.Value => .dyn,
            contexts.Page.Alternative => .Alternative,
            []const contexts.Page.Alternative => .{ .many = .Alternative },

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

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    var arena_impl = std.heap.ArenaAllocator.init(gpa_impl.allocator());
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
    const out_path = args[1];

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        fatal("error while creating output file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };
    defer out_file.close();

    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const w = buf_writer.writer();

    try w.writeAll(
        \\---
        \\{
        \\    .title = "Scripty Reference",
        \\    .description = "",
        \\    .author = "Loris Cro",
        \\    .layout = "scripty-reference.html",
        \\    .date = @date("2023-06-16T00:00:00"),
        \\    .draft = false,
        \\}
        \\---
        \\
    );

    // Globals
    {
        try w.writeAll(
            \\# Globals
            \\
        );

        const globals = .{
            .{ .name = "$site", .type_name = "Site", .desc = contexts.Site.description },
            .{ .name = "$page", .type_name = "Page", .desc = contexts.Page.description },
            .{
                .name = "$loop",
                .type_name = "?Loop",
                .desc =
                \\The iteration element in a loop, only available inside of elements with a `loop` attribute.
                ,
            },
            .{
                .name = "$if",
                .type_name = "?V",
                .desc =
                \\The payload of an optional value, only available inside of elemens with an `if` attribute.
                ,
            },
        };

        inline for (globals) |g| {
            try w.print(
                \\## {s} : {s}
                \\
                \\{s}
                \\
            , .{ g.name, g.type_name, g.desc });
        }
    }

    // Types
    {
        try w.writeAll(
            \\# Types
            \\
        );
        const types = .{
            .{ .name = "Site", .t = contexts.Site, .builtins = Value.builtinsFor(.site) },
            .{ .name = "Page", .t = contexts.Page, .builtins = Value.builtinsFor(.page) },
            .{ .name = "Alternative", .t = contexts.Page.Alternative, .builtins = Value.builtinsFor(.alternative) },
            .{ .name = "str", .builtins = Value.builtinsFor(.string) },
            .{ .name = "date", .builtins = Value.builtinsFor(.date) },
            .{ .name = "int", .builtins = Value.builtinsFor(.int) },
            .{ .name = "bool", .builtins = Value.builtinsFor(.bool) },
            .{ .name = "dyn", .builtins = Value.builtinsFor(.dynamic) },
        };

        inline for (types) |t| {
            try w.print(
                \\## {s}
                \\
            , .{t.name});
            if (@hasField(@TypeOf(t), "t")) {
                inline for (@typeInfo(t.t).Struct.fields) |f| {
                    if (f.name[0] != '_') {
                        try w.print("### {s} : {s}", .{ f.name, ScriptyParam.fromType(f.type).name(false) });

                        if (f.default_value) |d| {
                            const v: *const f.type = @alignCast(@ptrCast(d));
                            switch (f.type) {
                                []const u8 => try w.print(" = \"{s}\"", .{v.*}),
                                []const []const u8 => try w.print(" = []", .{}),
                                std.json.Value => try w.print(" = null", .{}),
                                else => try w.print(" = {any}", .{v.*}),
                            }
                        }
                        try w.writeAll(",\n  ");
                    }
                }
            }

            inline for (@typeInfo(t.builtins).Struct.decls) |d| {
                try w.print("### {s}", .{d.name});
                const decl = @field(t.builtins, d.name);
                try printSignature(w, decl.signature);
                try w.print(
                    \\
                    \\{s}
                    \\
                    \\Examples:
                    \\```
                    \\{s}
                    \\``` 
                    \\
                , .{ decl.description, decl.examples });
            }
        }
    }
    try buf_writer.flush();
}

fn printSignature(w: anytype, s: Signature) !void {
    try w.writeAll("(");
    for (s.params, 0..) |p, idx| {
        try w.writeAll(p.name(true));
        if (idx < s.params.len - 1) {
            try w.writeAll(", ");
        }
    }
    try w.writeAll(") -> ");
    try w.writeAll(s.ret.name(false));
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("out of memory", .{});
}
