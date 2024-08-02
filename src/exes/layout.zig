const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const options = @import("options");
const ziggy = @import("ziggy");
const super = @import("superhtml");
const zine = @import("zine");
const context = zine.context;
const md = @import("markdown-renderer.zig");

const log = std.log.scoped(.layout);
pub const std_options: std.Options = .{
    .log_level = .err,
    .log_scope_levels = options.log_scope_levels,
};

pub var asset_finder: AssetFinder = undefined;
pub var asset_collector: AssetCollector = undefined;
pub var page_finder: PageFinder = undefined;
pub var page_loader: PageLoader = undefined;

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
    const index_dir_path = args[13];
    const assets_dir_path = args[14];
    const content_dir_path = args[15];
    const md_path = args[16];
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
    const dep_writer = dep_buf_writer.writer();
    dep_writer.print("target: ", .{}) catch |err| {
        fatal("error writing to the dep file: {s}", .{@errorName(err)});
    };

    var locale: ?[]const u8 = null;
    const i18n: ziggy.dynamic.Value = blk: {
        if (std.mem.eql(u8, i18n_path, "null")) break :blk .null;

        locale = std.fs.path.stem(i18n_path);
        const bytes = readFile(build_root, i18n_path, arena) catch |err| {
            fatal("error while opening the i18n file:\n{s}\n{s}\n", .{
                i18n_path,
                @errorName(err),
            });
        };

        var diag: ziggy.Diagnostic = .{
            .path = i18n_path,
        };

        break :blk ziggy.parseLeaky(ziggy.dynamic.Value, arena, bytes, .{
            .diagnostic = &diag,
        }) catch {
            std.debug.print("unable to load i18n file:\n{s}\n\n", .{
                diag,
            });
            std.process.exit(1);
        };
    };

    const ti: []const context.Page.Translation = blk: {
        if (std.mem.eql(u8, translation_index_path, "null")) break :blk &.{};
        const bytes = readFile(build_root, translation_index_path, arena) catch |err| {
            fatal("error while opening the translation index file:\n{s}\n{s}\n", .{
                translation_index_path,
                @errorName(err),
            });
        };

        var diag: ziggy.Diagnostic = .{
            .path = i18n_path,
        };

        const ti = ziggy.parseLeaky([]const context.Page.Translation, arena, bytes, .{
            .diagnostic = &diag,
        }) catch {
            std.debug.panic("unable to load translation index:\n{s}\n\n", .{
                diag,
            });
        };
        break :blk ti;
    };

    // assets
    {
        asset_finder = .{
            .dep_writer = dep_writer.any(),
            .content_dir_path = std.fs.path.join(arena, &.{
                build_root_path,
                content_dir_path,
            }) catch oom(),
            .assets_dir_path = std.fs.path.join(arena, &.{
                build_root_path,
                assets_dir_path,
            }) catch oom(),
            .build_index_dir_path = std.fs.path.join(
                arena,
                &.{ index_dir_path, "a" },
            ) catch oom(),
        };
    }

    // host externs
    {
        page_finder = .{
            .dep_writer = dep_writer.any(),
            .page_index_dir_path = std.fs.path.join(
                arena,
                &.{ index_dir_path, "s" },
            ) catch oom(),
        };

        page_loader = .{
            .dep_writer = dep_writer.any(),
            .content_dir_path = std.fs.path.join(arena, &.{
                build_root_path,
                content_dir_path,
            }) catch oom(),
        };

        asset_collector = .{
            .output_path_prefix = output_path_prefix,
            .url_path_prefix = url_path_prefix,
            .asset_list_writer = asset_list_writer.any(),
        };
    }

    const site: context.Site = .{
        .host_url = site_host_url,
        .title = site_title,
        ._meta = .{
            .locale = locale,
        },
    };

    const page = md.render(
        arena,
        md_path,
        md_rel_path,
        url_path_prefix,
        index_in_section,
        parent_section_path,
        dep_writer.any(),
    ) catch |err| {
        fatal("error while trying to parse {s}: {s}", .{
            md_rel_path,
            @errorName(err),
        });
    };

    var ctx: context.Template = .{
        .site = site,
        .page = page,
        .i18n = i18n,
    };

    // TODO: implement this feature so we can remove this
    //       limitation.
    ctx.page._meta.is_root = true;
    ctx.build._assets = &asset_finder.host_extern;
    ctx.site._assets = &asset_finder.host_extern;
    ctx.page._assets = &asset_finder.host_extern;
    ctx.page._pages = &page_finder.host_extern;

    // if (subpages_meta) |sub| {gg
    //     ctx.page._meta.subpages = try ziggy.parseLeaky([]const context.Page, arena, sub, .{});
    //     ctx.page._meta.is_section = true;
    // }

    // if (prev_meta) |prev| {
    //     ctx.page._meta.prev = try ziggy.parseLeaky(*context.Page, arena, prev, .{});
    // }

    // if (next_meta) |next| {
    //     ctx.page._meta.next = try ziggy.parseLeaky(*context.Page, arena, next, .{});
    // }

    ctx.page._meta.translations = ti;

    const SuperVM = super.VM(
        context.Template,
        context.Value,
        context.Resources,
    );

    var super_vm = SuperVM.init(
        arena,
        &ctx,
        layout_name,
        layout_path,
        layout_html,
        std.mem.endsWith(u8, layout_name, ".xml"),
        md_rel_path,
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
                build_root_path,
                templates_dir_path,
                template_name,
            });

            log.debug("loading template = '{s}'", .{template_path});
            const template_html = readFile(build_root, template_path, arena) catch |ioerr| {
                super_vm.reportResourceFetchError(@errorName(ioerr));
                std.process.exit(1);
            };

            super_vm.insertTemplate(
                template_path,
                template_html,
                std.mem.endsWith(u8, template_name, ".xml"),
            );
            try dep_writer.print("{s} ", .{template_path});
        },
    };

    try out_buf_writer.flush();
    try asset_list_buf_writer.flush();
    try dep_writer.writeAll("\n");
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

const PageFinder = struct {
    page_index_dir_path: []const u8,
    dep_writer: std.io.AnyWriter,
    host_extern: context.PageExtern = .{ .ext_fn = ext },

    fn ext(
        he: *const context.PageExtern,
        gpa: Allocator,
        args: context.PageExtern.Args,
    ) !context.Value {
        const f: *const PageFinder = @fieldParentPtr("host_extern", he);
        log.debug("page fetcher: '{any}'", .{
            args,
        });

        switch (args.kind) {
            .next, .prev => |idx| {
                const idx_entry: [2]usize = switch (args.kind) {
                    .next => .{ idx, idx + 1 },
                    .prev => .{ idx - 1, idx },
                    else => unreachable,
                };
                var buf: [1024]u8 = undefined;
                const index_in_section = std.fmt.bufPrint(&buf, "{d}_{d}", .{
                    idx_entry[0],
                    idx_entry[1],
                }) catch @panic("programming error: asset path buf is too small!");

                const index_path = try std.fs.path.join(gpa, &.{
                    f.page_index_dir_path,
                    args.parent_section_path,
                    index_in_section,
                });

                log.debug("dep: '{s}'", .{index_path});

                f.dep_writer.print("{s} ", .{index_path}) catch {
                    std.debug.panic(
                        "error while writing to dep file file: '{s}'",
                        .{index_path},
                    );
                };

                const pages = std.fs.cwd().readFileAlloc(
                    gpa,
                    index_path,
                    std.math.maxInt(u32),
                ) catch |err| {
                    std.debug.panic("error while trying to read page index '{s}': {s}", .{
                        index_path,
                        @errorName(err),
                    });
                };

                var it = std.mem.tokenizeScalar(u8, pages, '\n');
                if (args.kind == .next) _ = it.next().?;
                const md_rel_path = it.next().?;

                if (args.just_check) {
                    return .{ .bool = md_rel_path.len > 0 };
                }

                if (md_rel_path.len == 0) {
                    return .{ .optional = null };
                }

                const val = try page_loader.host_extern.call(gpa, .{
                    .md_rel_path = md_rel_path,
                    .url_path_prefix = args.url_path_prefix,
                    .index_in_section = switch (args.kind) {
                        .prev => idx - 1,
                        .next => idx + 1,
                        else => unreachable,
                    },
                    .parent_section_path = args.parent_section_path,
                });

                return .{ .optional = .{ .page = val.page } };
            },
            .subpages => {
                const path = args.md_rel_path;
                if (std.mem.endsWith(u8, path, "index.md")) {
                    const index_path = try std.fs.path.join(gpa, &.{
                        f.page_index_dir_path,
                        path[0 .. path.len - "index.md".len],
                        "s",
                    });

                    log.debug("dep: '{s}'", .{index_path});

                    f.dep_writer.print("{s} ", .{index_path}) catch {
                        std.debug.panic(
                            "error while writing to dep file file: '{s}'",
                            .{index_path},
                        );
                    };

                    const pages = std.fs.cwd().readFileAlloc(
                        gpa,
                        index_path,
                        std.math.maxInt(u32),
                    ) catch {
                        std.debug.panic(
                            "error while reading page index file '{s}'",
                            .{index_path},
                        );
                    };

                    return .{
                        .iterator = .{
                            .page_it = context.PageIterator.init(
                                args.parent_section_path,
                                args.url_path_prefix,
                                pages,
                                &page_loader.host_extern,
                            ),
                        },
                    };
                }
                return .{
                    .iterator = .{
                        .page_it = context.PageIterator.init(
                            "",
                            "",
                            "",
                            &page_loader.host_extern,
                        ),
                    },
                };
            },
        }
    }
};

const PageLoader = struct {
    content_dir_path: []const u8,
    dep_writer: std.io.AnyWriter,
    host_extern: context.PageLoaderExtern = .{ .ext_fn = ext },

    fn ext(
        he: *const context.PageLoaderExtern,
        gpa: Allocator,
        args: context.PageLoaderExtern.Args,
    ) !context.Value {
        const f: *const PageLoader = @fieldParentPtr("host_extern", he);
        log.debug("page loader: '{any}'", .{args});

        const md_path = try std.fs.path.join(gpa, &.{
            f.content_dir_path,
            args.md_rel_path,
        });

        log.debug("dep: '{s}'", .{md_path});
        f.dep_writer.print("{s} ", .{md_path}) catch {
            std.debug.panic(
                "error while writing to dep file file: '{s}'",
                .{args.md_rel_path},
            );
        };

        const page = try gpa.create(context.Page);
        page.* = md.render(
            gpa,
            md_path,
            args.md_rel_path,
            args.url_path_prefix,
            args.index_in_section,
            args.parent_section_path,
            // We don't pass a dep writer because we
            // don't want to save assets for real as
            // it will be done by the invocation of layout
            // there that page gets analyzed directly.
            null,
        ) catch |err| {
            fatal("error while trying to parse {s}: {s}", .{
                args.md_rel_path,
                @errorName(err),
            });
        };

        page._assets = &asset_finder.host_extern;
        page._pages = &page_finder.host_extern;

        return .{ .page = page };
    }
};

const AssetFinder = struct {
    // site content directory
    content_dir_path: []const u8,
    // site assets directory
    assets_dir_path: []const u8,
    // build assets
    build_index_dir_path: []const u8,

    dep_writer: std.io.AnyWriter,
    host_extern: context.AssetExtern = .{ .ext_fn = ext },

    fn ext(
        he: *const context.AssetExtern,
        gpa: Allocator,
        arg: context.AssetExtern.Args,
    ) !context.Value {
        const f: *const AssetFinder = @fieldParentPtr("host_extern", he);

        const base_path = switch (arg.kind) {
            .site => f.assets_dir_path,
            .page => |p| try std.fs.path.join(gpa, &.{
                f.content_dir_path,
                p,
            }),
            // separate workflow that doesn't return a base path
            .build => {
                const full_path = try std.fs.path.join(gpa, &.{
                    f.build_index_dir_path,
                    arg.ref,
                });

                const paths = std.fs.cwd().readFileAlloc(
                    gpa,
                    full_path,
                    std.math.maxInt(u16),
                ) catch {
                    return context.Value.errFmt(
                        gpa,
                        "build asset '{s}' doesn't exist",
                        .{arg.ref},
                    );
                };

                log.debug("dep: '{s}'", .{full_path});
                f.dep_writer.print("{s} ", .{full_path}) catch {
                    std.debug.panic(
                        "error while writing to dep file file: '{s}'",
                        .{arg.ref},
                    );
                };

                // Index file structure:
                // - first line: asset path in cache
                // - second line: optional install path for asset
                var it = std.mem.tokenizeScalar(u8, paths, '\n');

                const asset_path = it.next().?;
                const asset_install_path = it.next();

                return .{
                    .asset = .{
                        ._collector = &asset_collector.host_extern,
                        ._meta = .{
                            .kind = .{ .build = asset_install_path },
                            .ref = arg.ref,
                            .path = asset_path,
                        },
                    },
                };
            },
        };

        const dir = std.fs.cwd().openDir(base_path, .{}) catch {
            @panic("error while opening asset index dir");
        };

        dir.access(arg.ref, .{}) catch |err| {
            return context.Value.errFmt(gpa, "unable to access '{s}': {}", .{
                arg.ref,
                err,
            });
        };

        const full_path = try std.fs.path.join(gpa, &.{
            base_path,
            arg.ref,
        });

        log.debug("dep: '{s}'", .{full_path});
        f.dep_writer.print("{s} ", .{full_path}) catch {
            std.debug.panic(
                "error while writing to dep file file: '{s}'",
                .{arg.ref},
            );
        };

        return .{
            .asset = .{
                ._collector = &asset_collector.host_extern,
                ._meta = .{
                    .kind = arg.kind,
                    .ref = arg.ref,
                    .path = full_path,
                },
            },
        };
    }
};
const AssetCollector = struct {
    output_path_prefix: []const u8,
    url_path_prefix: []const u8,
    asset_list_writer: std.io.AnyWriter,

    host_extern: context.AssetCollectorExtern = .{ .ext_fn = ext },

    fn ext(
        he: *const context.AssetCollectorExtern,
        gpa: Allocator,
        args: context.AssetCollectorExtern.Args,
    ) !context.Value {
        const ac: *const AssetCollector = @fieldParentPtr("host_extern", he);
        const url = try ac.collect(gpa, args);
        return .{ .string = url };
    }

    pub fn collect(ac: AssetCollector, gpa: Allocator, args: context.AssetCollectorExtern.Args) ![]const u8 {
        const install_rel_path = switch (args.kind) {
            .site, .page => args.ref,
            .build => |bip| bip.?,
        };

        const maybe_page_rel_path = switch (args.kind) {
            .page => |p| p,
            else => "",
        };

        const install_path = try std.fs.path.join(gpa, &.{
            ac.output_path_prefix,
            maybe_page_rel_path,
            install_rel_path,
        });

        log.debug("collect asset: '{s}' -> '{s}'", .{ args.path, install_path });

        ac.asset_list_writer.print("{s}\n{s}\n\n", .{
            args.path,
            install_path,
        }) catch {
            std.debug.panic(
                "error while writing to asset list file file: '{s}'",
                .{args.path},
            );
        };

        return switch (args.kind) {
            // Links to page assets are relative
            .page => args.ref,
            // Links to site assets are absolute
            .site => try std.fs.path.join(gpa, &.{
                "/",
                ac.url_path_prefix,
                args.ref,
            }),
            // Links to build assets are absolute
            .build => |bip| try std.fs.path.join(gpa, &.{
                "/",
                ac.url_path_prefix,
                bip.?,
            }),
        };
    }
};
