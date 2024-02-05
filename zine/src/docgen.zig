const std = @import("std");
const contexts = @import("contexts.zig");
const Value = contexts.Value;

pub const Signature = struct {
    params: []const ScriptyParam = &.{},
    ret: ScriptyParam,
};

pub const ScriptyParam = union(enum) {
    Site,
    Page,
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
        str,
        int,
        bool,
        date,
        dyn,
    };
};

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
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
        \\  "title": "Scripty Reference",
        \\  "description": "", 
        \\  "author": "Loris Cro",
        \\  "layout": "page.html",
        \\  "date": "2023-06-16T00:00:00",
        \\  "draft": false
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
            .{ .name = "$site", .type_name = "Site", .value = contexts.Site },
            .{ .name = "$page", .type_name = "Page", .value = contexts.Page },
        };

        inline for (globals) |g| {
            try w.print(
                \\## {s} : {s}
                \\
                \\{s}
                \\
            , .{ g.name, g.type_name, g.value.description });
        }
    }

    // Types
    {
        try w.writeAll(
            \\# Types
            \\
        );
        const types = .{
            .{ .name = "Site", .builtins = Value.builtinsFor(.site) },
            .{ .name = "Page", .builtins = Value.builtinsFor(.page) },
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
        try printParam(w, p);
        if (idx < s.params.len - 1) {
            try w.writeAll(", ");
        }
    }
    try w.writeAll(") -> ");
    try printParam(w, s.ret);
}

fn printParam(w: anytype, p: ScriptyParam) !void {
    switch (p) {
        .many => |m| try w.print("[{s}]", .{@tagName(m)}),
        .opt => |m| try w.print("?{s}", .{@tagName(m)}),
        else => try w.writeAll(@tagName(p)),
    }
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("out of memory", .{});
}
