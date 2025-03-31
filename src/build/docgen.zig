const std = @import("std");
const zine = @import("zine");
const context = zine.context;
const Value = context.Value;
const Template = context.Template;
const Param = context.ScriptyParam;

const ref: Reference = .{
    .global = analyzeFields(Template),
    .values = analyzeValues(),
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
        \\.title = "SuperHTML Scripty Reference",
        \\.description = "",
        \\.author = "Loris Cro",
        \\.layout = "scripty-reference.shtml",
        \\.date = @date("2023-06-16T00:00:00"),
        \\.draft = false,
        \\---
        \\
    );
    try w.writeAll(std.fmt.comptimePrint("{}", .{ref}));
    try buf_writer.flush();
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("out of memory", .{});
}

pub const Reference = struct {
    global: []const Field,
    values: []const Type,

    pub const Field = struct {
        name: []const u8,
        type_name: Param,
        description: []const u8,
    };

    pub const Type = struct {
        name: Param,
        description: []const u8,
        fields: []const Field,
        builtins: []const Builtin,
    };

    pub const Builtin = struct {
        name: []const u8,
        signature: context.Signature,
        description: []const u8,
        examples: []const u8,
    };

    pub fn format(
        r: Reference,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("# [Global Scope]($section.id('global'))\n\n", .{});
        for (r.global) |f| {
            try out_stream.print(
                \\## `${s}` : {s}
                \\
                \\{s}
                \\
                \\
            , .{
                f.name,
                f.type_name.link(false),
                f.description,
            });
        }

        for (r.values[1..]) |v| {
            try out_stream.print(
                \\# [{s}]($section.id('{s}'))
                \\
                \\{s}
                \\
                \\
            , .{ v.name.string(false), v.name.id(), v.description });

            if (v.fields.len > 0)
                try out_stream.print("## Fields\n\n", .{});

            for (v.fields) |f| {
                try out_stream.print(
                    \\### `{s}` : {s}
                    \\
                    \\{s}
                    \\
                    \\
                , .{ f.name, f.type_name.link(false), f.description });
            }

            if (v.builtins.len > 0)
                try out_stream.print("## Functions\n\n", .{});

            for (v.builtins) |b| {
                try out_stream.print(
                    \\### []($heading.id("{s}.{s}")) [`fn`]($link.ref("{s}.{s}")) {s} {s}
                    \\
                    \\{s}
                    \\
                    \\#### Examples
                    \\
                    \\```superhtml
                    \\{s}
                    \\```
                    \\
                , .{
                    // Type.Function
                    v.name.string(false),
                    b.name,

                    // Type.Function
                    v.name.string(false),
                    b.name,

                    b.name,
                    b.signature,
                    b.description,
                    b.examples,
                });
            }
        }
    }
};

pub fn analyzeValues() []const Reference.Type {
    const info = @typeInfo(context.Value).@"union";
    var values: [info.fields.len]Reference.Type = undefined;
    inline for (info.fields, &values) |f, *v| {
        const t = getStructType(f.type) orelse {
            std.debug.assert(f.type == []const u8);
            v.* = .{
                .name = .err,
                .fields = &.{},
                .builtins = &.{},
                .description =
                \\A Scripty error.
                \\
                \\In Scripty all errors are unrecoverable.
                \\When available, you can use `?` variants 
                \\of functions (e.g. `get?`) to obtain a null
                \\value instead of an error. 
                ,
            };
            continue;
        };
        v.* = analyzeType(t);
    }
    const out = values;
    return &out;
}
pub fn analyzeType(T: type) Reference.Type {
    const builtins = analyzeBuiltins(T);
    const fields = analyzeFields(T);
    return .{
        .name = Param.fromType(T),
        .description = T.docs_description,
        .fields = fields,
        .builtins = builtins,
    };
}

fn getStructType(T: type) ?type {
    switch (@typeInfo(T)) {
        .@"struct" => return T,
        .pointer => |p| switch (p.size) {
            .one => return getStructType(p.child),
            else => return null,
        },
        .optional => |opt| return getStructType(opt.child),
        else => return null,
    }
}

fn analyzeBuiltins(T: type) []const Reference.Builtin {
    const info = @typeInfo(T.Builtins).@"struct";
    var decls: [info.decls.len]Reference.Builtin = undefined;
    inline for (info.decls, &decls) |decl, *b| {
        const t = @field(T.Builtins, decl.name);
        b.* = .{
            .name = decl.name,
            .signature = t.signature,
            .description = t.docs_description,
            .examples = t.examples,
        };
    }
    const out = decls;
    return &out;
}

fn analyzeFields(T: type) []const Reference.Field {
    const info = @typeInfo(T).@"struct";
    var reference_fields: [info.fields.len]Reference.Field = undefined;
    var idx: usize = 0;
    for (info.fields) |tf| {
        if (!@hasDecl(T, "Fields")) continue;
        if (tf.name[0] == '_') continue;
        reference_fields[idx] = .{
            .name = tf.name,
            .description = @field(T.Fields, tf.name),
            .type_name = Param.fromType(tf.type),
        };
        idx += 1;
    }
    const out = reference_fields[0..idx].*;
    return &out;
}
