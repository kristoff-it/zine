const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const ziggy = @import("ziggy");
const superhtml = @import("superhtml");
const cache = @import("layout/cache.zig");
const join = @import("../root.zig").join;
const zine = @import("zine");
const context = zine.context;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.layout);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

pub fn main() !void {
    defer log.debug("laoyut ended", .{});
    errdefer |err| log.debug("layout ended with a failure: {}", .{err});

    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = std.process.argsAlloc(arena) catch oom();
    const out_path = args[1];
    const build_root_path = args[2];
    const url_path_prefix = args[3];
    const md_rel_path = args[4];
    const layout_path = args[5];
    const layout_name = args[6];
    const templates_dir_path = args[7];
    const dep_file_path = args[8];
    const site_host_url = args[9];
    const site_title = args[10];
    const i18n_path = args[11];
    const translation_index_path = args[12];
    _ = translation_index_path;
    const index_dir_path = args[13];
    const assets_dir_path = args[14];
    const content_dir_path = args[15];
    const md_path = args[16];
    _ = md_path;
    const index_in_section = if (std.mem.eql(u8, args[17], "null"))
        null
    else
        std.fmt.parseInt(usize, args[17], 10) catch unreachable;
    const parent_section_path = if (std.mem.eql(u8, args[18], "null"))
        null
    else
        args[18];

    const asset_list_file_path = args[19];
    const output_path_prefix = args[20];
    const locale_name = args[21];
    _ = locale_name;
    const locales_path = args[22];

    for (args, 0..) |a, idx| log.debug("args[{}]: {s}", .{ idx, a });

    const build_root = std.fs.cwd().openDir(build_root_path, .{}) catch |err| {
        fatal("error while opening the build root dir:\n{s}\n{s}\n", .{
            build_root_path,
            @errorName(err),
        });
    };

    const layout_html = readFile(build_root, layout_path, arena) catch |err| {
        fatal("error while opening the layout file:\n{s}\n{s}\n", .{
            layout_path,
            @errorName(err),
        });
    };

    const out_file = build_root.createFile(out_path, .{}) catch |err| {
        fatal("error while creating output file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };

    var out_buf_writer = std.io.bufferedWriter(out_file.writer());
    const out_writer = out_buf_writer.writer();

    const asset_list_file = build_root.createFile(
        asset_list_file_path,
        .{},
    ) catch |err| {
        fatal("error while creating asset list file: {s}\n{s}\n", .{
            asset_list_file_path,
            @errorName(err),
        });
    };
    var asset_list_buf_writer = std.io.bufferedWriter(asset_list_file.writer());
    const asset_list_writer = asset_list_buf_writer.writer();

    const dep_file = build_root.createFile(dep_file_path, .{}) catch |err| {
        fatal("error while creating dep file: {s}\n{s}\n", .{
            out_path,
            @errorName(err),
        });
    };

    var dep_buf_writer = std.io.bufferedWriter(dep_file.writer());
    const dep_writer = zine.DepWriter.init(dep_buf_writer.writer().any());
    dep_writer.writeTarget("target") catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };

    var locale_code: ?[]const u8 = null;
    const i18n: ziggy.dynamic.Map(ziggy.dynamic.Value) = blk: {
        if (std.mem.eql(u8, i18n_path, "null")) break :blk .{};

        locale_code = std.fs.path.stem(i18n_path);
        const bytes = readFile(build_root, i18n_path, arena) catch |err| {
            fatal("error while opening the i18n file:\n{s}\n{s}\n", .{
                i18n_path,
                @errorName(err),
            });
        };

        var diag: ziggy.Diagnostic = .{
            .path = i18n_path,
        };

        break :blk ziggy.parseLeaky(ziggy.dynamic.Map(ziggy.dynamic.Value), arena, bytes, .{
            .diagnostic = &diag,
        }) catch {
            std.debug.print("unable to load i18n file:\n{s}\n\n", .{
                diag,
            });
            std.process.exit(1);
        };
    };

    const locales: []const cache.Locale = blk: {
        if (std.mem.eql(u8, locales_path, "null")) break :blk &.{};
        const bytes = readFile(build_root, locales_path, arena) catch |err| {
            fatal("error while opening the localized variant file:\n{s}\n{s}\n", .{
                locales_path,
                @errorName(err),
            });
        };

        var diag: ziggy.Diagnostic = .{
            .path = locales_path,
        };

        break :blk ziggy.parseLeaky([]cache.Locale, arena, bytes, .{
            .diagnostic = &diag,
        }) catch {
            std.debug.panic("unable to load translation index:\n{s}\n\n", .{
                diag,
            });
        };
    };

    try cache.initAll(
        arena,
        site_title,
        site_host_url,
        url_path_prefix,
        build_root_path,
        content_dir_path,
        assets_dir_path,
        index_dir_path,
        output_path_prefix,
        locales,
        dep_writer,
        asset_list_writer.any(),
    );

    const site = if (locale_code) |lc|
        cache.sites.get(lc).?
    else
        cache.sites.getSimple();

    const page = try cache.pages.get(
        site,
        md_rel_path,
        parent_section_path,
        index_in_section,
        true,
    );

    var diag: ziggy.Diagnostic = .{
        .path = locales_path,
    };

    const index_dir = std.fs.cwd().openDir(index_dir_path, .{}) catch |err| {
        fatal("error while opening the index dir:\n{s}\n{s}\n", .{
            index_dir_path,
            @errorName(err),
        });
    };

    const git_data_path = try join(arena, &.{
        index_dir_path, "git.ziggy",
    });
    const git_data = try readFile(index_dir, "git.ziggy", arena);

    const git = ziggy.parseLeaky(context.Git, arena, git_data, .{
        .diagnostic = &diag,
    }) catch {
        std.debug.panic("unable to load git info:\n{s}\n\n", .{diag});
    };

    var ctx: context.Template = .{
        .site = site,
        .page = page,
        .i18n = i18n,
        .build = context.Build.init(dep_writer, git_data_path, git),
    };

    const SuperVM = superhtml.VM(
        context.Template,
        context.Value,
    );

    const md_name = if (locale_code) |lc| try std.fmt.allocPrint(
        arena,
        "{s} ({s})",
        .{ md_rel_path, lc },
    ) else md_rel_path;
    var super_vm = SuperVM.init(
        arena,
        &ctx,
        layout_name,
        layout_path,
        layout_html,
        std.mem.endsWith(u8, layout_name, ".xml"),
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
            const template_path = try join(arena, &.{
                build_root_path,
                templates_dir_path,
                template_name,
            });

            log.debug("loading template = '{s}'", .{template_path});
            const template_html = readFile(build_root, template_path, arena) catch |ioerr| {
                super_vm.reportResourceFetchError(@errorName(ioerr));
                std.debug.print(
                    \\
                    \\NOTE: Zine expects templates to be placed under a
                    \\      'templates/' subdirectory in your layouts
                    \\      directory.
                    \\
                    \\Zine tried to find the template here:
                    \\'{s}'
                    \\
                    \\
                , .{template_path});
                std.process.exit(1);
            };

            super_vm.insertTemplate(
                template_path,
                template_html,
                std.mem.endsWith(u8, template_name, ".xml"),
            );
            try dep_writer.writePrereq(template_path);
        },
    };

    try out_buf_writer.flush();
    try asset_list_buf_writer.flush();
    try dep_buf_writer.flush();
}

fn readFile(
    dir: std.fs.Dir,
    path: []const u8,
    arena: Allocator,
) ![:0]const u8 {
    return dir.readFileAllocOptions(
        arena,
        path,
        ziggy.max_size,
        null,
        1,
        0,
    );
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
