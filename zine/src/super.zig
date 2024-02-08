const std = @import("std");
const options = @import("options");
const super = @import("super");
const contexts = @import("contexts.zig");

const log = std.log.scoped(.super_exe);
pub const std_options = struct {
    pub const log_level = .err;
    pub const log_scope_levels = options.log_scope_levels;
};

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
    const out_path = args[1];
    const install_subpath = args[2];
    const rendered_md_path = args[3];
    const md_name = args[4];
    const sections_meta_dir_path = args[5];
    const layout_path = args[6];
    const layout_name = args[7];
    const templates_dir_path = args[8];
    const dep_file_path = args[9];
    const site_base_url = args[10];
    const site_title = args[11];

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

    const index_path = try std.fs.path.join(arena, &.{ sections_meta_dir_path, "__zine-index__.json" });
    const index_bytes = readFile(index_path, arena) catch |err| {
        fatal("error while opening the index file:\n{s}\n{s}\n", .{
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

    const page_path = try std.fs.path.join(arena, &.{ sections_meta_dir_path, install_subpath, "_zine_page.json" });
    const page_string = readFile(page_path, arena) catch |err| {
        fatal("error reading the page meta file '{s}': {s}", .{ page_path, @errorName(err) });
    };

    var scanner = std.json.Scanner.initCompleteInput(arena, page_string);
    defer scanner.deinit();

    var diag: std.json.Diagnostics = .{};
    scanner.enableDiagnostics(&diag);
    errdefer std.debug.print("json err: line {} col {}\n", .{ diag.getLine(), diag.getColumn() });

    var pages = std.ArrayList(contexts.Page).init(arena);
    var it = std.mem.tokenizeScalar(u8, index_bytes, '\n');
    while (it.next()) |line| {
        if (std.mem.eql(u8, line, "rss")) continue;
        const path = try std.fs.path.join(arena, &.{
            sections_meta_dir_path,
            line,
            "_zine_page.json",
        });
        const page_bytes = readFile(path, arena) catch |err| {
            fatal("error reading a page meta file '{s}': {s}", .{
                path,
                @errorName(err),
            });
        };
        var page = try std.json.parseFromSliceLeaky(
            contexts.Page,
            arena,
            page_bytes,
            .{},
        );

        page._meta.permalink = try std.fmt.allocPrint(arena, "/{s}/", .{line});
        try pages.append(page);
    }
    std.mem.reverse(contexts.Page, pages.items);

    var depender: contexts.Depender = .{
        .meta_dir_path = sections_meta_dir_path,
        .dep_writer = dep_writer,
    };
    const site: contexts.Site = .{
        .base_url = site_base_url,
        .title = site_title,
        ._pages = try pages.toOwnedSlice(),
        ._depender = &depender,
    };

    const page = try std.json.parseFromTokenSourceLeaky(contexts.Page, arena, &scanner, .{});

    const prev_next = findPrevNext(index_bytes, install_subpath);
    var ctx: contexts.Template = .{
        .site = site,
        .page = page,
    };
    ctx.page.content = rendered_md_string;
    ctx.page._meta.depender = &depender;
    ctx.page._meta.permalink = try std.fmt.allocPrint(arena, "/{s}/", .{install_subpath});

    if (prev_next.prev) |p| {
        const prev_path = try std.fs.path.join(arena, &.{
            sections_meta_dir_path,
            p,
            "_zine_page.json",
        });
        const prev_page = readFile(prev_path, arena) catch |err| {
            fatal("error reading the prev page meta file '{s}': {s}", .{
                prev_path,
                @errorName(err),
            });
        };
        var prev_meta = try std.json.parseFromSliceLeaky(
            contexts.Page,
            arena,
            prev_page,
            .{},
        );

        prev_meta._meta.permalink = try std.fmt.allocPrint(arena, "/{s}/", .{p});
        ctx.page._meta.prev = &prev_meta;
    }
    if (prev_next.next) |n| {
        const next_path = try std.fs.path.join(arena, &.{
            sections_meta_dir_path,
            n,
            "_zine_page.json",
        });
        const next_page = readFile(next_path, arena) catch |err| {
            fatal("error reading the next page meta file '{s}': {s}", .{
                next_path,
                @errorName(err),
            });
        };
        var next_meta = try std.json.parseFromSliceLeaky(
            contexts.Page,
            arena,
            next_page,
            .{},
        );

        next_meta._meta.permalink = try std.fmt.allocPrint(arena, "/{s}/", .{n});
        ctx.page._meta.next = &next_meta;
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

fn readFile(path: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});

    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    return r.readAllAlloc(arena, 1024 * 1024 * 10);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("out of memory", .{});
}

const PrevNext = struct {
    prev: ?[]const u8 = null,
    next: ?[]const u8 = null,
};

fn findPrevNext(index: []const u8, needle: []const u8) PrevNext {
    var result: PrevNext = .{};
    const prefix = std.fs.path.dirname(needle) orelse return result;

    var it = std.mem.splitScalar(u8, index, '\n');

    while (it.next()) |line| {
        if (std.mem.eql(u8, line, needle)) {
            if (it.next()) |n| {
                if (std.mem.startsWith(u8, n, prefix)) {
                    result.next = n;
                }
            }
            return result;
        }

        if (std.mem.startsWith(u8, line, prefix)) {
            result.prev = line;
        }
    } else {
        @panic("TODO: we're not in the index list?");
    }
}
