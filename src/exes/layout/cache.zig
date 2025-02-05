const std = @import("std");
const supermd = @import("supermd");
const ziggy = @import("ziggy");
const zine = @import("zine");
const join = zine.join;
const context = zine.context;
const Allocator = std.mem.Allocator;
const DepWriter = zine.DepWriter;
const wuffs = @import("wuffs");

const log = std.log.scoped(.layout_cache);

// Must be called once at program start.
pub fn initAll(
    _gpa: Allocator,
    title: []const u8,
    host_url: []const u8,
    url_path_prefix: []const u8,
    build_root_path: []const u8,
    content_dir_path: []const u8,
    assets_dir_path: []const u8,
    _index_dir_path: []const u8,
    output_path_prefix: []const u8,
    locales: []const Locale,
    _dep_writer: DepWriter,
    asset_list_writer: std.io.AnyWriter,
) error{OutOfMemory}!void {
    gpa = _gpa;
    dep_writer = _dep_writer;
    index_dir_path = _index_dir_path;
    context.assetFind = asset_finder.find;
    context.assetCollect = asset_collector.collect;
    context.pageFind = page_finder.find;
    context.pageGet = pages.get;
    context.pageGetRoot = pages.getRootPage;
    context.siteGet = sites.get;
    context.allSites = sites.all;

    if (locales.len > 0) {
        try sites.initMulti(host_url, locales);
    } else {
        try sites.initSimple(
            title,
            host_url,
            url_path_prefix,
            content_dir_path,
            output_path_prefix,
        );
    }

    pages.init();

    try page_finder.init(build_root_path);

    try asset_finder.init(
        build_root_path,
        assets_dir_path,
    );
    try asset_collector.init(
        url_path_prefix,
        output_path_prefix,
        asset_list_writer,
    );
}

var gpa: Allocator = undefined;
var dep_writer: DepWriter = undefined;
var index_dir_path: []const u8 = undefined;

pub const sites = struct {
    var multi: bool = undefined;
    var items: []const context.Site = &.{};

    pub fn initMulti(host_url: []const u8, locales: []const Locale) !void {
        const _items = try gpa.alloc(context.Site, locales.len);
        for (locales, _items) |l, *it| {
            const output_path_prefix = l.output_prefix_override orelse
                l.code;
            const url_path_prefix = l.output_prefix_override orelse
                if (l.host_url_override != null) "" else l.code;

            it.* = .{
                .host_url = l.host_url_override orelse host_url,
                .title = l.site_title,
                ._meta = .{
                    .url_path_prefix = url_path_prefix,
                    .output_path_prefix = output_path_prefix,
                    .content_dir_path = l.content_dir_path,
                    .kind = .{
                        .multi = .{ .code = l.code, .name = l.name },
                    },
                },
            };
        }

        sites.multi = true;
        sites.items = _items;
    }

    pub fn initSimple(
        title: []const u8,
        host_url: []const u8,
        url_path_prefix: []const u8,
        content_dir_path: []const u8,
        output_path_prefix: []const u8,
    ) !void {
        sites.multi = false;
        const simple = try gpa.alloc(context.Site, 1);
        simple[0] = .{
            .title = title,
            .host_url = host_url,
            ._meta = .{
                .kind = .simple,
                .url_path_prefix = url_path_prefix,
                .content_dir_path = content_dir_path,
                .output_path_prefix = output_path_prefix,
            },
        };

        sites.items = simple;
    }

    pub fn getSimple() *const context.Site {
        std.debug.assert(!sites.multi);
        return &sites.items[0];
    }

    pub fn get(code: []const u8) ?*const context.Site {
        std.debug.assert(sites.multi);
        return for (sites.items) |*l| {
            if (std.mem.eql(u8, l._meta.kind.multi.code, code)) break l;
        } else null;
    }

    pub fn all() []const context.Site {
        std.debug.assert(sites.multi);
        return sites.items;
    }
};

pub const pages = struct {
    // keyed by 'site.content_path/md_rel_path'
    var map: std.StringHashMap(*context.Page) = undefined;
    var root: *const context.Page = undefined;

    pub fn init() void {
        pages.map = std.StringHashMap(*context.Page).init(gpa);
    }

    pub fn getRootPage() *const context.Page {
        return root;
    }

    pub fn get(
        site: *const context.Site,
        md_rel_path: []const u8,
        parent_section_path: ?[]const u8,
        index_in_section: ?usize,
        is_root_page: bool,
    ) error{ OutOfMemory, PageLoad }!*context.Page {
        const full_path = try join(gpa, &.{
            site._meta.content_dir_path,
            md_rel_path,
        });

        return pages.map.get(full_path) orelse {
            const p = loadPage(
                site,
                md_rel_path,
                parent_section_path,
                index_in_section,
                is_root_page,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    return error.PageLoad;
                },
            };

            if (is_root_page) pages.root = p;
            try pages.map.put(full_path, p);
            return p;
        };
    }
};

const page_finder = struct {
    var page_index_dir_path: []const u8 = undefined;

    fn init(build_root_path: []const u8) error{OutOfMemory}!void {
        _ = build_root_path;
        page_finder.page_index_dir_path = try join(
            gpa,
            &.{
                // build_root_path,
                index_dir_path,
                "s",
            },
        );
    }

    fn find(search: context.PageSearchStrategy) !context.Value {
        switch (search) {
            .ref => |ref| {
                // `foo/bar` can be one of:
                //  - foo/bar.smd
                //  - foo/bar/index.smd

                var md_path = try join(gpa, &.{
                    ref.site._meta.content_dir_path,
                    ref.path,
                    "index.smd",
                });

                std.fs.cwd().access(md_path, .{}) catch {
                    const end = md_path.len - "/index.smd".len + ".smd".len;
                    md_path = md_path[0..end];
                    md_path[md_path.len - 4 .. end][0..4].* = ".smd".*;

                    std.fs.cwd().access(md_path, .{}) catch {
                        return context.Value.errFmt(gpa, "unable to find '{s}'", .{
                            ref.path,
                        });
                    };
                };

                const md_rel_path = md_path[ref.site._meta.content_dir_path.len + 1 ..];

                const val = pages.get(
                    ref.site,
                    md_rel_path,
                    null,
                    null,
                    false,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.PageLoad => return .{
                        .err = "error loading page",
                    },
                };

                log.debug("found page = {*}", .{val});

                return .{ .page = val };
            },
            .next, .prev => |page| {
                const idx = page._meta.index_in_section.?;
                const idx_entry: [2]usize = switch (search) {
                    .next => .{ idx, idx + 1 },
                    .prev => .{ idx - 1, idx },
                    else => unreachable,
                };
                var buf: [1024]u8 = undefined;
                const index_in_section = std.fmt.bufPrint(&buf, "{d}_{d}", .{
                    idx_entry[0],
                    idx_entry[1],
                }) catch @panic("programming error: asset path buf is too small!");

                const prefix = switch (page._meta.site._meta.kind) {
                    .simple => "",
                    .multi => |m| m.code,
                };
                const index_path = try join(gpa, &.{
                    page_index_dir_path,
                    prefix,
                    page._meta.parent_section_path.?,
                    index_in_section,
                });

                log.debug("dep: '{s}'", .{index_path});

                dep_writer.writePrereq(index_path) catch {
                    std.debug.panic(
                        "error while writing to dep file file: '{s}'",
                        .{index_path},
                    );
                };

                const ps = std.fs.cwd().readFileAlloc(
                    gpa,
                    index_path,
                    std.math.maxInt(u32),
                ) catch |err| {
                    std.debug.panic("error while trying to read page index '{s}': {s}", .{
                        index_path,
                        @errorName(err),
                    });
                };

                var it = std.mem.splitScalar(u8, ps, '\n');
                if (search == .next) _ = it.next().?;
                const md_rel_path = it.next().?;

                if (md_rel_path.len == 0) {
                    return .{ .optional = null };
                }

                const val = pages.get(
                    page._meta.site,
                    md_rel_path,
                    page._meta.parent_section_path,
                    switch (search) {
                        .prev => idx - 1,
                        .next => idx + 1,
                        else => unreachable,
                    },
                    false,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.PageLoad => return .{
                        .err = "error loading page",
                    },
                };

                return context.Optional.init(gpa, val);
            },
            .subpages => |page| {
                const path = page._meta.md_rel_path;
                if (std.mem.endsWith(u8, path, "index.smd")) {
                    const prefix = switch (page._meta.site._meta.kind) {
                        .simple => "",
                        .multi => |m| m.code,
                    };
                    const index_path = try join(gpa, &.{
                        page_index_dir_path,
                        prefix,
                        path[0 .. path.len - "index.smd".len],
                        "s",
                    });

                    log.debug("dep: '{s}'", .{index_path});

                    dep_writer.writePrereq(index_path) catch {
                        std.debug.panic(
                            "error while writing to dep file file: '{s}'",
                            .{index_path},
                        );
                    };

                    const ps = std.fs.cwd().readFileAlloc(
                        gpa,
                        index_path,
                        std.math.maxInt(u32),
                    ) catch {
                        std.debug.panic(
                            "error while reading page index file '{s}'",
                            .{index_path},
                        );
                    };

                    const total_subpages = std.mem.count(u8, ps, "\n");
                    var it = std.mem.tokenizeScalar(u8, ps, '\n');

                    const subpages = try gpa.alloc(context.Value, total_subpages);

                    for (subpages, 0..) |*sp, idx| {
                        const next_page_path = it.next() orelse unreachable;
                        const next_page = context.pageGet(
                            page._meta.site,
                            next_page_path,
                            page._meta.md_asset_dir_rel_path,
                            idx,
                            false,
                        ) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.PageLoad => @panic("TODO: report page load errors"),
                        };

                        sp.* = .{ .page = next_page };
                    }

                    return context.Array.init(gpa, context.Value, subpages);
                }
                return context.Array.init(gpa, context.Value, &.{});
            },
        }
    }
};

const asset_finder = struct {
    // site assets directory
    var assets_dir_path: []const u8 = undefined;
    // build assets
    var build_index_dir_path: []const u8 = undefined;

    fn init(
        build_root_path: []const u8,
        _assets_dir_path: []const u8,
    ) error{OutOfMemory}!void {
        asset_finder.assets_dir_path = try join(gpa, &.{
            build_root_path,
            _assets_dir_path,
        });
        asset_finder.build_index_dir_path = try join(
            gpa,
            &.{ index_dir_path, "a" },
        );
    }

    fn find(
        ref: []const u8,
        kind: context.AssetKindUnion,
    ) !context.Value {
        const base_path = switch (kind) {
            .site => asset_finder.assets_dir_path,
            .page => |p| p._meta.md_asset_dir_path,
            // separate workflow that doesn't return a base path
            .build => {
                const hash = std.hash.Wyhash.hash(1990, ref);
                var buf: [32]u8 = undefined;
                const entry_name = std.fmt.bufPrint(&buf, "{x}", .{
                    hash,
                }) catch unreachable;
                const full_path = try join(gpa, &.{
                    asset_finder.build_index_dir_path,
                    entry_name,
                });

                const paths = std.fs.cwd().readFileAlloc(
                    gpa,
                    full_path,
                    std.math.maxInt(u16),
                ) catch {
                    return context.Value.errFmt(
                        gpa,
                        "build asset '{s}' doesn't exist",
                        .{ref},
                    );
                };

                log.debug("dep: '{s}'", .{full_path});
                dep_writer.writePrereq(full_path) catch {
                    std.debug.panic(
                        "error while writing to dep file file: '{s}'",
                        .{ref},
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
                        ._meta = .{
                            .kind = .{ .build = asset_install_path },
                            .ref = ref,
                            .path = asset_path,
                        },
                    },
                };
            },
        };

        log.debug("finder opening '{s}'", .{base_path});
        const dir = std.fs.cwd().openDir(base_path, .{}) catch {
            return context.Value.errFmt(gpa, "unable to open asset directory '{s}'", .{
                base_path,
            });
        };

        dir.access(ref, .{}) catch |err| {
            return context.Value.errFmt(gpa, "unable to access '{s}': {}", .{
                ref,
                err,
            });
        };

        const full_path = try join(gpa, &.{
            base_path,
            ref,
        });

        log.debug("dep: '{s}'", .{full_path});
        dep_writer.writePrereq(full_path) catch {
            std.debug.panic(
                "error while writing to dep file file: '{s}'",
                .{ref},
            );
        };

        return .{
            .asset = .{
                ._meta = .{
                    .kind = kind,
                    .ref = ref,
                    .path = full_path,
                },
            },
        };
    }
};

const asset_collector = struct {
    var output_path_prefix: []const u8 = undefined;
    var url_path_prefix: []const u8 = undefined;
    var asset_list_writer: std.io.AnyWriter = undefined;

    fn init(
        _url_path_prefix: []const u8,
        _output_path_prefix: []const u8,
        _asset_list_writer: std.io.AnyWriter,
    ) error{OutOfMemory}!void {
        asset_collector.output_path_prefix = _output_path_prefix;
        asset_collector.url_path_prefix = _url_path_prefix;
        asset_collector.asset_list_writer = _asset_list_writer;
    }

    pub fn collect(
        ref: []const u8,
        // full path to the asset
        path: []const u8,
        kind: context.AssetKindUnion,
    ) error{OutOfMemory}![]const u8 {
        const install_rel_path = switch (kind) {
            .site, .page => ref,
            .build => |bip| bip.?,
        };

        const maybe_page_rel_path = switch (kind) {
            .page => |p| p._meta.md_asset_dir_rel_path,
            else => "",
        };

        const install_path = try join(gpa, &.{
            asset_collector.output_path_prefix,
            maybe_page_rel_path,
            install_rel_path,
        });

        log.debug("collect asset: '{s}' -> '{s}'", .{ path, install_path });

        asset_collector.asset_list_writer.print("{s}\n{s}\n\n", .{
            path,
            install_path,
        }) catch {
            std.debug.panic(
                "error while writing to asset list file file: '{s}'",
                .{path},
            );
        };

        return switch (kind) {
            // Links to page assets are relative
            .page => |p| blk: {
                const root = pages.getRootPage();
                if (root == p) break :blk ref;

                const page_link = try context.Page.Builtins.link.call(
                    p,
                    gpa,
                    &.{},
                );
                break :blk join(gpa, &.{
                    page_link.string.value,
                    ref,
                });
            },
            // Links to site assets are absolute
            .site => try join(gpa, &.{
                "/",
                asset_collector.url_path_prefix,
                ref,
            }),
            // Links to build assets are absolute
            .build => |bip| try join(gpa, &.{
                "/",
                asset_collector.url_path_prefix,
                bip.?,
            }),
        };
    }
};

// Must be kept in sync with the same decl in build.zig
pub const Locale = struct {
    code: []const u8,
    name: []const u8,
    content_dir_path: []const u8,
    site_title: []const u8,
    host_url_override: ?[]const u8 = null,
    /// |  output_ |     host_     |     resulting    |    resulting    |
    /// |  prefix_ |      url_     |        url       |      path       |
    /// | override |   override    |      prefix      |     prefix      |
    /// | -------- | ------------- | ---------------- | --------------- |
    /// |   null   |      null     | site.com/en-US/  | zig-out/en-US/  |
    /// |   null   | "us.site.com" | us.site.com/     | zig-out/en-US/  |
    /// |   "foo"  |      null     | site.com/foo/    | zig-out/foo/    |
    /// |   "foo"  | "us.site.com" | us.site.com/foo/ | zig-out/foo/    |
    /// |    ""    |      null     | site.com/        | zig-out/        |
    output_prefix_override: ?[]const u8 = null,
};

fn loadPage(
    site: *const context.Site,
    md_rel_path: []const u8,
    parent_section_path: ?[]const u8,
    index_in_section: ?usize,
    is_root_page: bool,
) !*context.Page {
    log.debug("load page '{s}' '{s}'", .{
        site._meta.content_dir_path,
        md_rel_path,
    });
    var time = std.time.Timer.start() catch unreachable;

    const md_path = try join(gpa, &.{
        site._meta.content_dir_path,
        md_rel_path,
    });

    defer log.debug(
        "Analyzing '{s}' took {}ms ({}ns)\n",
        .{
            md_path,
            time.read() / std.time.ns_per_ms,
            time.read(),
        },
    );

    var is_section = false;
    var md_asset_dir_path: []const u8 = undefined;
    var md_asset_dir_rel_path: []const u8 = undefined;
    if (std.mem.endsWith(u8, md_path, "index.smd")) {
        is_section = true;
        md_asset_dir_path = md_path[0 .. md_path.len - "index.smd".len];
        md_asset_dir_rel_path = md_rel_path[0 .. md_rel_path.len - "index.smd".len];
    } else {
        md_asset_dir_path = md_path[0 .. md_path.len - ".smd".len];
        md_asset_dir_rel_path = md_rel_path[0 .. md_rel_path.len - ".smd".len];
    }

    const in_file = std.fs.cwd().openFile(md_path, .{}) catch |err| {
        std.debug.print("Error while opening file: {s}\n", .{md_path});
        return err;
    };
    defer in_file.close();

    var buf_reader = std.io.bufferedReader(in_file.reader());
    const r = buf_reader.reader();
    const fm = try ziggy.frontmatter.Parser(context.Page).parse(gpa, r, null);
    const page = switch (fm) {
        .success => |s| blk: {
            const page = try gpa.create(context.Page);
            page.* = s.header;
            break :blk page;
        },
        else => unreachable,
    };

    const md_src = try r.readAllAlloc(gpa, 1024 * 1024 * 10);

    const psp: ?[]const u8 = parent_section_path orelse blk: {
        if (std.mem.eql(u8, md_rel_path, "index.smd")) break :blk null;

        const path_to_hash = std.fs.path.dirname(md_rel_path) orelse "";
        var hash = std.hash.Wyhash.init(1990);
        switch (site._meta.kind) {
            .simple => {},
            .multi => |ml| {
                hash.update(ml.code);
            },
        }
        if (std.mem.endsWith(u8, md_rel_path, "/index.smd")) {
            hash.update(std.fs.path.dirname(path_to_hash) orelse "");
        } else {
            hash.update(path_to_hash);
        }

        const ps_index_file_path = try join(gpa, &.{
            index_dir_path,
            "ps",
            try std.fmt.allocPrint(gpa, "{x}", .{hash.final()}),
        });

        log.debug("ps_index_file_path:'{s}' '{s}' '{s}'", .{
            index_dir_path,
            "ps",
            try std.fmt.allocPrint(gpa, "{x}", .{hash.final()}),
        });
        const ps_path = std.fs.cwd().readFileAlloc(
            gpa,
            ps_index_file_path,
            std.math.maxInt(u32),
        ) catch @panic("i/o");

        log.debug("dep: '{s}'", .{ps_index_file_path});
        dep_writer.writePrereq(ps_index_file_path) catch {
            std.debug.panic(
                "error while writing to dep file file: '{s}'",
                .{ps_index_file_path},
            );
        };

        break :blk ps_path;
    };
    const iis: ?usize = index_in_section orelse blk: {
        const ps_path = psp orelse break :blk null;

        const ps_file_path = try join(gpa, &.{
            index_dir_path,
            "s",

            switch (site._meta.kind) {
                .simple => "",
                .multi => |ml| ml.code,
            },
            ps_path,
        });
        const section = std.fs.cwd().readFileAlloc(
            gpa,
            ps_file_path,
            std.math.maxInt(u32),
        ) catch @panic("i/o");

        log.debug("dep: '{s}'", .{ps_file_path});
        dep_writer.writePrereq(ps_file_path) catch {
            std.debug.panic(
                "error while writing to dep file file: '{s}'",
                .{ps_file_path},
            );
        };

        var it = std.mem.tokenizeScalar(u8, section, '\n');
        var idx: usize = 0;
        while (it.next()) |page_path| : (idx += 1) {
            if (std.mem.eql(u8, page_path, md_rel_path)) {
                break;
            }
        } else {
            std.debug.panic(
                \\Failed to find a parent section match for a page.
                \\
                \\md_rel_path = '{s}'
                \\section_path = '{s}'
                \\section file contents: 
                \\```
                \\{s}
                \\```
            , .{ md_rel_path, ps_file_path, section });
        }

        var total = idx;
        while (it.next()) |_| {
            total += 1;
        }

        // We do total - idx because the sorting order in a `s` file is
        // newest to oldest, which is the inverse of what the prev/next page
        // indes does.
        // TODO: change the index file format to start with the total line count
        //       so that we can turn this full-file-scan into a constant time
        //       operation.
        break :blk total - idx;
    };

    page._meta = .{
        // TODO: unicode this
        .word_count = @intCast(md_src.len / 6),
        .is_section = std.mem.endsWith(u8, md_path, "/index.smd"),
        .md_path = md_path,
        .md_rel_path = md_rel_path,
        .md_asset_dir_path = md_asset_dir_path,
        .md_asset_dir_rel_path = md_asset_dir_rel_path,
        .parent_section_path = if (psp) |p| std.fs.path.dirnamePosix(p) else null, // remove '/s'
        .index_in_section = iis,
        .site = site,
        .src = md_src,
        .is_root = is_root_page,
    };

    for (page.alternatives) |*alt| @constCast(alt)._prefix = site._meta.url_path_prefix;

    if (page.translation_key) |tk| {
        const tk_index_path = try join(gpa, &.{ index_dir_path, "tk", tk });
        const tk_index = try std.fs.cwd().readFileAlloc(
            gpa,
            tk_index_path,
            std.math.maxInt(u32),
        );

        var tks = std.ArrayList(context.Page.Translation).init(gpa);
        var it = std.mem.tokenizeScalar(u8, tk_index, '\n');
        while (it.next()) |code| {
            const path = it.next() orelse @panic("bad tk index");
            try tks.append(.{
                .site = sites.get(code).?,
                .md_rel_path = path,
            });
        }
        page._meta.key_variants = tks.items;
    }
    const fm_offset = std.mem.count(u8, fm.success.code, "\n") + 2;
    const ast = try supermd.Ast.init(gpa, md_src);
    page._meta.ast = ast;

    // Only root page gets analized
    if (!is_root_page) {
        return page;
    }

    if (ast.errors.len != 0) {
        std.debug.print(
            \\
            \\---------- MARKDOWN SYNTAX ERROR ----------
            \\
            \\A syntax error was found in a content file.
            \\
            // \\It's strongly recommended to setup your editor to
            // \\leverage the `supermd` CLI tool in order to obtain
            // \\in-editor syntax checking and autoformatting.
            // \\
            // \\Download it from here:
            // \\   https://github.com/kristoff-it/supermd
            \\
        , .{});

        for (ast.errors) |err| {
            const range = err.main;
            const line = blk: {
                var it = std.mem.splitScalar(u8, md_src, '\n');
                for (1..range.start.row) |_| _ = it.next();
                break :blk it.next().?;
            };

            const line_trim_left = std.mem.trimLeft(
                u8,
                line,
                &std.ascii.whitespace,
            );

            const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

            const start_trim_left = line.len - line_trim_left.len;
            const caret_len = if (range.start.row == range.end.row)
                range.end.col - range.start.col
            else
                line_trim.len - start_trim_left;
            const caret_spaces_len = range.start.col - 1 - start_trim_left;

            var buf: [1024]u8 = undefined;

            const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
                const h = buf[0 .. caret_len + caret_spaces_len];
                @memset(h[0..caret_spaces_len], ' ');
                @memset(h[caret_spaces_len..][0..caret_len], '^');
                break :blk h;
            } else "";

            const msg = switch (err.kind) {
                .scripty => |s| s.err,
                else => "",
            };

            // std.debug.print("fm: {}\nerr: {s}\nrange start: {any}\nrange end: {any}", .{
            //     fm_offset,
            //     @tagName(err.kind),
            //     err.main.start,
            //     err.main.end,
            // });

            // Saturating subtraction because of a bug related to html comments
            // in markdown.
            const lines = range.end.row -| range.start.row;
            const lines_fmt = if (lines == 0) "" else try std.fmt.allocPrint(
                gpa,
                "(+{} lines)",
                .{lines},
            );

            const tag_name = switch (err.kind) {
                .html => |h| switch (h.tag) {
                    inline else => |t| @tagName(t),
                },
                else => @tagName(err.kind),
            };
            std.debug.print(
                \\
                \\[{s}] {s}
                \\{s}:{}:{}: {s}
                \\    {s}
                \\    {s}
                \\
            , .{
                tag_name,        msg,
                md_path,         fm_offset + range.start.row,
                range.start.col, lines_fmt,
                line_trim,       highlight,
            });
        }
        std.process.exit(1);
    }

    var current: ?supermd.Node = ast.md.root.firstChild();
    while (current) |n| : (current = n.next(ast.md.root)) {
        const directive = n.getDirective() orelse continue;

        switch (directive.kind) {
            .section, .block, .heading, .text => {},
            .code => |code| {
                const value = switch (code.src.?) {
                    else => unreachable,
                    .page_asset => |ref| try asset_finder.find(ref, .{
                        .page = page,
                    }),
                    .site_asset => |ref| try asset_finder.find(ref, .site),
                    .build_asset => |ref| try asset_finder.find(ref, .{
                        .build = null,
                    }),
                };
                if (value == .err) reportError(
                    n,
                    md_src,
                    md_rel_path,
                    md_path,
                    fm_offset,
                    is_section,
                    value.err,
                );

                const src = std.fs.cwd().readFileAlloc(
                    gpa,
                    value.asset._meta.path,
                    std.math.maxInt(u32),
                ) catch @panic("i/o");

                log.debug("dep: '{s}'", .{value.asset._meta.path});

                dep_writer.writePrereq(value.asset._meta.path) catch {
                    std.debug.panic(
                        "error while writing to dep file file: '{s}'",
                        .{value.asset._meta.path},
                    );
                };

                const lang = code.language orelse {
                    directive.kind.code.src = .{ .url = src };
                    continue;
                };

                if (std.mem.eql(u8, lang, "=html")) {
                    directive.kind.code.src = .{ .url = src };
                    continue;
                }

                var buf = std.ArrayList(u8).init(gpa);

                zine.highlight.highlightCode(
                    gpa,
                    lang,
                    src,
                    buf.writer(),
                ) catch |err| switch (err) {
                    else => unreachable,
                    error.InvalidLanguage => {
                        reportError(
                            n,
                            md_src,
                            md_rel_path,
                            md_path,
                            fm_offset,
                            is_section,
                            "Unknown Language",
                        );
                    },
                };
                directive.kind.code.src = .{ .url = buf.items };
            },
            inline else => |val, tag| {
                const res: context.Value = switch (val.src.?) {
                    .url => continue,
                    .self_page => blk: {
                        if (@hasField(@TypeOf(val), "alternative")) {
                            if (val.alternative) |alt_name| {
                                for (page.alternatives) |alt| {
                                    if (std.mem.eql(u8, alt.name, alt_name)) {
                                        const abs = try join(gpa, &.{
                                            "/",
                                            site._meta.url_path_prefix,
                                            alt.output,
                                            "/",
                                        });
                                        break :blk context.String.init(abs);
                                    }
                                } else reportError(
                                    n,
                                    md_src,
                                    md_rel_path,
                                    md_path,
                                    fm_offset,
                                    is_section,
                                    "the page has no alternative with this name",
                                );
                            }
                        }
                        break :blk context.String.init("");
                    },

                    .page => |p| blk: {
                        const page_site = if (p.locale) |lc|
                            sites.get(lc) orelse reportError(
                                n,
                                md_src,
                                md_rel_path,
                                md_path,
                                fm_offset,
                                is_section,
                                try std.fmt.allocPrint(
                                    gpa,
                                    "could not find locale '{s}'",
                                    .{lc},
                                ),
                            )
                        else
                            site;

                        const ref = switch (p.kind) {
                            .absolute => p.ref,
                            .sub => sub: {
                                if (!is_section) reportError(
                                    n,
                                    md_src,
                                    md_rel_path,
                                    md_path,
                                    fm_offset,
                                    is_section,
                                    "the homepage has no siblings",
                                );

                                const end = md_rel_path.len - "index.smd".len;
                                break :sub try join(gpa, &.{
                                    md_rel_path[0..end],
                                    p.ref,
                                });
                            },
                            .sibling => sibl: {
                                // don't use psp for this as it has a `/s` suffix
                                const ps_base = page._meta.parent_section_path orelse reportError(
                                    n,
                                    md_src,
                                    md_rel_path,
                                    md_path,
                                    fm_offset,
                                    is_section,
                                    "the homepage has no siblings",
                                );

                                break :sibl try join(gpa, &.{
                                    ps_base,
                                    p.ref,
                                });
                            },
                        };

                        const res = try page_finder.find(.{
                            .ref = .{
                                .site = page_site,
                                .path = ref,
                            },
                        });

                        switch (res) {
                            else => unreachable,
                            .err => break :blk res,
                            .page => |pp| {
                                if (@hasField(@TypeOf(val), "ref")) ref: {
                                    const hash = val.ref orelse break :ref;
                                    if (!pp._meta.ast.?.ids.contains(hash)) {
                                        reportError(
                                            n,
                                            md_src,
                                            md_rel_path,
                                            md_path,
                                            fm_offset,
                                            is_section,
                                            try std.fmt.allocPrint(
                                                gpa,
                                                "'{s}' is not a valid content id for '{s}', available ids are: {s}",
                                                .{ hash, ref, pp._meta.ast.?.ids.keys() },
                                            ),
                                        );
                                    }
                                }

                                if (@hasField(@TypeOf(val), "alternative")) {
                                    if (val.alternative) |alt_name| {
                                        for (pp.alternatives) |alt| {
                                            if (std.mem.eql(u8, alt.name, alt_name)) {
                                                const abs = try join(gpa, &.{
                                                    "/",
                                                    pp._meta.site._meta.url_path_prefix,
                                                    alt.output,
                                                    "/",
                                                });
                                                break :blk context.String.init(abs);
                                            }
                                        } else reportError(
                                            n,
                                            md_src,
                                            md_rel_path,
                                            md_path,
                                            fm_offset,
                                            is_section,
                                            "the page has no alternative with this name",
                                        );
                                    }
                                }

                                if (page_site == site) {
                                    break :blk try context.Page.Builtins.link.call(
                                        pp,
                                        gpa,
                                        &.{},
                                    );
                                } else {
                                    @panic("TODO: implement linking to pages in other locales");
                                }
                            },
                        }
                    },
                    .page_asset => |ref| try asset_finder.find(ref, .{
                        .page = page,
                    }),
                    .site_asset => |ref| try asset_finder.find(ref, .site),
                    .build_asset => |ref| try asset_finder.find(ref, .{
                        .build = null,
                    }),
                };

                if (res == .err) reportError(
                    n,
                    md_src,
                    md_rel_path,
                    md_path,
                    fm_offset,
                    is_section,
                    res.err,
                );

                switch (res) {
                    else => unreachable,
                    .string => |s| {
                        @field(directive.kind, @tagName(tag)).src = .{ .url = s.value };
                    },
                    .asset => |a| {
                        const url = try asset_collector.collect(
                            a._meta.ref,
                            a._meta.path,
                            a._meta.kind,
                        );
                        @field(directive.kind, @tagName(tag)).src = .{ .url = url };
                        if (directive.kind == .image) blk: {
                            const image_handle = std.fs.cwd().openFile(a._meta.path, .{}) catch break :blk;
                            defer image_handle.close();
                            var image_header_buf: [2048]u8 = undefined;
                            const image_header_len = image_handle.readAll(&image_header_buf) catch break :blk;
                            const image_header = image_header_buf[0..image_header_len];

                            const img_size = getImageSize(image_header) catch break :blk;
                            directive.kind.image.size = .{ .w = img_size.w, .h = img_size.h };
                        }
                    },
                }
            },
        }
    }
    return page;
}

const max_align = @alignOf(std.c.max_align_t);
fn allocDecoder(
    comptime name: []const u8,
) !struct { []align(max_align) u8, *wuffs.wuffs_base__image_decoder } {
    const size = @field(wuffs, "sizeof__wuffs_" ++ name ++ "__decoder")();
    const init_fn = @field(wuffs, "wuffs_" ++ name ++ "__decoder__initialize");
    const upcast_fn = @field(wuffs, "wuffs_" ++ name ++ "__decoder__upcast_as__wuffs_base__image_decoder");

    const decoder_raw = try gpa.alignedAlloc(u8, max_align, size);
    errdefer gpa.free(decoder_raw);
    for (decoder_raw) |*byte| byte.* = 0;

    try wrapErr(init_fn(@ptrCast(decoder_raw), size, wuffs.WUFFS_VERSION, wuffs.WUFFS_INITIALIZE__ALREADY_ZEROED));

    const upcasted = upcast_fn(@ptrCast(decoder_raw)).?;
    return .{ decoder_raw, upcasted };
}
fn wrapErr(status: wuffs.wuffs_base__status) !void {
    if (wuffs.wuffs_base__status__message(&status)) |_| {
        return error.WuffsError;
    }
}
const Size = struct { w: i64, h: i64 };
fn getImageSize(image_src: []const u8) !Size {
    var g_src = wuffs.wuffs_base__ptr_u8__reader(@constCast(image_src.ptr), image_src.len, true);

    const g_fourcc = wuffs.wuffs_base__magic_number_guess_fourcc(
        wuffs.wuffs_base__io_buffer__reader_slice(&g_src),
        g_src.meta.closed,
    );
    if (g_fourcc < 0) return error.CouldNotGuessFileFormat;

    const decoder_raw, const g_image_decoder = switch (g_fourcc) {
        wuffs.WUFFS_BASE__FOURCC__BMP => try allocDecoder("bmp"),
        wuffs.WUFFS_BASE__FOURCC__GIF => try allocDecoder("gif"),
        wuffs.WUFFS_BASE__FOURCC__JPEG => try allocDecoder("jpeg"),
        wuffs.WUFFS_BASE__FOURCC__NPBM => try allocDecoder("netpbm"),
        wuffs.WUFFS_BASE__FOURCC__NIE => try allocDecoder("nie"),
        wuffs.WUFFS_BASE__FOURCC__PNG => try allocDecoder("png"),
        wuffs.WUFFS_BASE__FOURCC__QOI => try allocDecoder("qoi"),
        wuffs.WUFFS_BASE__FOURCC__TGA => try allocDecoder("tga"),
        wuffs.WUFFS_BASE__FOURCC__WBMP => try allocDecoder("wbmp"),
        wuffs.WUFFS_BASE__FOURCC__WEBP => try allocDecoder("webp"),
        else => {
            return error.UnsupportedImageFormat;
        },
    };
    defer gpa.free(decoder_raw);

    var g_image_config = std.mem.zeroes(wuffs.wuffs_base__image_config);
    try wrapErr(wuffs.wuffs_base__image_decoder__decode_image_config(
        g_image_decoder,
        &g_image_config,
        &g_src,
    ));

    const g_width = wuffs.wuffs_base__pixel_config__width(&g_image_config.pixcfg);
    const g_height = wuffs.wuffs_base__pixel_config__height(&g_image_config.pixcfg);

    return .{ .w = std.math.cast(i64, g_width) orelse return error.Cast, .h = std.math.cast(i64, g_height) orelse return error.Cast };
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn reportError(
    n: supermd.Node,
    md_src: []const u8,
    md_rel_path: []const u8,
    md_path: []const u8,
    fm_offset: usize,
    is_section: bool,
    err: []const u8,
) noreturn {
    const range = n.range();
    const line = blk: {
        var it = std.mem.splitScalar(u8, md_src, '\n');
        for (1..range.start.row) |_| _ = it.next();
        break :blk it.next().?;
    };

    const line_trim_left = std.mem.trimLeft(
        u8,
        line,
        &std.ascii.whitespace,
    );

    const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

    const start_trim_left = line.len - line_trim_left.len;
    const caret_len = if (range.start.row == range.end.row)
        range.end.col - range.start.col
    else
        line_trim.len - start_trim_left;
    const caret_spaces_len = range.start.col - 1 - start_trim_left;

    var buf: [1024]u8 = undefined;

    const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
        const h = buf[0 .. caret_len + caret_spaces_len];
        @memset(h[0..caret_spaces_len], ' ');
        @memset(h[caret_spaces_len..][0..caret_len], '^');
        break :blk h;
    } else "";

    std.debug.print(
        \\
        \\---------- MARKDOWN MISSING ASSET ----------
        \\
        \\An asset referenced in a content file is missing. 
        \\
        \\
        \\[{s}] {s}
        \\({s}) {s}:{}:{}: 
        \\    {s}
        \\    {s}
        \\
        \\{s}
        \\
    , .{
        "missing_asset",             err,

        md_rel_path,                 md_path,
        fm_offset + range.start.row, range.start.col,
        line_trim,                   highlight,

        if (is_section) "" else 
        \\NOTE: assets for this page must be placed under a subdirectory that shares the same name with the corresponding markdown file!
        ,
    });
    std.process.exit(1);
}
