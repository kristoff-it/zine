const std = @import("std");
const super = @import("super");
const frontmatter = super.frontmatter;
const contexts = @import("contexts.zig");

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
    const out_path = args[1];
    const content_dir_path = args[2];
    const rendered_md_path = args[3];
    const md_name = args[4];
    const layout_path = args[5];
    const layout_name = args[6];
    const templates_dir_path = args[7];
    const dep_file_path = args[8];

    const rendered_md_string = readFile(rendered_md_path, arena) catch |err| {
        fatal("error while opening the rendered markdown file:\n{s}\n{s}\n", .{
            rendered_md_path,
            @errorName(err),
        });
    };

    const layout_html = readFile(layout_path, arena) catch |err| {
        fatal("error while opening the layout file:\n{s}\n{s}\n", .{
            layout_path,
            @errorName(err),
        });
    };

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        fatal("error while creating output file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };
    defer out_file.close();

    const dep_file = std.fs.cwd().createFile(dep_file_path, .{}) catch |err| {
        fatal("error while creating dep file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };
    defer dep_file.close();

    var dep_buf_writer = std.io.bufferedWriter(dep_file.writer());
    const dep_writer = dep_buf_writer.writer();
    dep_writer.print("target: {s} {s} ", .{ rendered_md_path, layout_path }) catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };

    var out_buf_writer = std.io.bufferedWriter(out_file.writer());
    const out_writer = out_buf_writer.writer();

    const fm_path = try std.fs.path.join(arena, &.{ content_dir_path, md_name });
    const fm_string = readFile(fm_path, arena) catch |err| {
        fatal("error reading the frontmatter file: {s}", .{@errorName(err)});
    };

    var fbs = std.io.fixedBufferStream(fm_string);
    const fm = try frontmatter.parse(contexts.Page, fbs.reader(), arena);
    var ctx: contexts.Template = .{
        .page = fm,
    };
    ctx.page.content = rendered_md_string;
    var super_vm = super.SuperVM.init(
        arena,
        &ctx,
        layout_name,
        layout_path,
        layout_html,
        md_name,
        out_writer,
        std.io.getStdErr().writer(),
    );

    while (true) super_vm.run() catch |err| switch (err) {
        error.Done => break,
        error.Fatal => std.process.exit(1),
        error.OutOfMemory => {
            std.debug.print("out of memory\n", .{});
            std.process.exit(1);
        },
        error.OutIO, error.ErrIO => {
            std.debug.print("I/O error\n", .{});
            std.process.exit(1);
        },
        error.Quota => super_vm.setQuota(100),
        error.WantSnippet => @panic("TODO: looad snippet"),
        error.WantTemplate => {
            const template_name = super_vm.wantedTemplateName();
            const template_path = try std.fs.path.join(arena, &.{
                templates_dir_path,
                template_name,
            });
            const template_html = readFile(template_path, arena) catch |ioerr| {
                super_vm.resourceFetchError(ioerr);
                std.process.exit(1);
            };

            super_vm.insertTemplate(template_path, template_html);
            try dep_file.writeAll(template_path);
        },
    };

    try out_buf_writer.flush();
    try dep_writer.writeAll("\n");
    try dep_buf_writer.flush();
}

fn readFile(path: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});

    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    return r.readAllAlloc(arena, 4096);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}
