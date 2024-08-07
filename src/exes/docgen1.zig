const std = @import("std");
const zine = @import("zine");
const context = zine.context;
const Value = context.Value;

pub const Reference = struct {
    globals: []const Field,
    primitives: []const Primitive,

    pub const Field = struct {
        name: []const u8,
        type: Type,
    };

    pub const Type = union(enum) {
        primitive: Primitive,
        @"struct": Struct,
    };

    pub const Primitive = struct {
        name: []const u8,
        builtins: []const Builtin = &.{},
    };

    pub const Struct = struct {
        name: []const u8,
        description: []const u8,
        fields: []const Field = &.{},
        builtins: []const Builtin = &.{},
        optional: bool = false,
    };

    pub const Builtin = struct {
        name: []const u8,
        signature: context.Signature,
        doc: []const u8,
        examples: []const u8,
    };
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

    var ref: Reference = .{
        .globals = &.{
            .{
                .name = "$site",
                .type =                
            },
        },
        .primitives = &.{},
    };
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("out of memory", .{});
}
