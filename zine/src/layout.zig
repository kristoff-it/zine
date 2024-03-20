const std = @import("std");
const options = @import("options");
const ziggy = @import("ziggy");
const super = @import("super");
const contexts = @import("contexts.zig");

const log = std.log.scoped(.layout);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
    const out_path = args[1];
    const rendered_md_path = args[2];
    const page_meta_path = args[3];
    const md_name = args[4];
    const layout_path = args[5];
    const layout_name = args[6];
    const templates_dir_path = args[7];
    const dep_file_path = args[8];
    const site_base_url = args[9];
    const site_title = args[10];
    const prev_path = args[11];
    const next_path = args[12];
    const subpages_path = args[13];

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

    const page_meta = readFile(page_meta_path, arena) catch |err| {
        fatal("error while opening the page meta file:\n{s}\n{s}\n", .{
            layout_path,
            @errorName(err),
        });
    };

    const prev_meta: ?[:0]const u8 = blk: {
        if (std.mem.eql(u8, prev_path, "null")) break :blk null;
        break :blk readFile(prev_path, arena) catch |err| {
            fatal("error while opening the prev meta file:\n{s}\n{s}\n", .{
                layout_path,
                @errorName(err),
            });
        };
    };

    const next_meta: ?[:0]const u8 = blk: {
        if (std.mem.eql(u8, next_path, "null")) break :blk null;
        break :blk readFile(next_path, arena) catch |err| {
            fatal("error while opening the next meta file:\n{s}\n{s}\n", .{
                layout_path,
                @errorName(err),
            });
        };
    };

    const subpages_meta: ?[:0]const u8 = blk: {
        if (std.mem.eql(u8, subpages_path, "null")) break :blk null;
        break :blk readFile(subpages_path, arena) catch |err| {
            fatal("error while opening the subpages meta file:\n{s}\n{s}\n", .{
                layout_path,
                @errorName(err),
            });
        };
    };

    var dep_buf_writer = std.io.bufferedWriter(dep_file.writer());
    const dep_writer = dep_buf_writer.writer();
    dep_writer.print("target: {s} {s} ", .{ rendered_md_path, layout_path }) catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };

    var out_buf_writer = std.io.bufferedWriter(out_file.writer());
    const out_writer = out_buf_writer.writer();

    const site: contexts.Site = .{ .base_url = site_base_url, .title = site_title };

    const page = try ziggy.parseLeaky(contexts.Page, arena, page_meta, .{});

    var ctx: contexts.Template = .{
        .site = site,
        .page = page,
    };
    ctx.page.content = rendered_md_string;

    if (subpages_meta) |sub| {
        ctx.page._meta.subpages = try ziggy.parseLeaky([]const contexts.Page, arena, sub, .{});
        ctx.page._meta.is_section = true;
    }

    if (prev_meta) |prev| {
        ctx.page._meta.prev = try ziggy.parseLeaky(*contexts.Page, arena, prev, .{});
    }

    if (next_meta) |next| {
        ctx.page._meta.next = try ziggy.parseLeaky(*contexts.Page, arena, next, .{});
    }

    var super_vm = super.SuperVM(contexts.Template, contexts.Value).init(
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
            try dep_writer.print("{s} ", .{template_path});
            log.debug("loaded template: '{s}'", .{template_path});
        },
    };

    try out_buf_writer.flush();
    try dep_writer.writeAll("\n");
    try dep_buf_writer.flush();
}

fn readFile(path: []const u8, arena: std.mem.Allocator) ![:0]const u8 {
    return std.fs.cwd().readFileAllocOptions(arena, path, ziggy.max_size, null, 1, 0);
}

pub fn fatald(diag: ziggy.Diagnostic) noreturn {
    fatal("{}", .{diag});
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}
