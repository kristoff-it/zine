const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const ziggy = @import("ziggy");
const supermd = @import("supermd");
const fatal = @import("fatal.zig");
const worker = @import("worker.zig");
const context = @import("context.zig");
const Build = @import("Build.zig");
const Variant = @import("Variant.zig");
const StringTable = @import("StringTable.zig");
const PathTable = @import("PathTable.zig");
const String = StringTable.String;
const Path = PathTable.Path;
const PathName = PathTable.PathName;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.run);
pub var progress_buf: [4096]u8 = undefined;
pub var progress: std.Progress.Node = undefined;

pub fn run(gpa: Allocator) Build {
    assert(worker.started);

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var build: Build = blk: {
        const tracy_frame = tracy.namedFrame("load build");
        defer tracy_frame.end();
        break :blk Build.load(gpa, arena, &.{});
    };
    _ = arena_state.reset(.retain_capacity);

    var static_assets_errors = false;
    {
        const tracy_frame = tracy.namedFrame("scan content");
        defer tracy_frame.end();
        switch (build.cfg) {
            .Site => |s| {
                build.variants = try gpa.alloc(Variant, 1);
                worker.addJob(.{
                    .scan = .{
                        .variant = &build.variants[0],
                        .base_dir = build.base_dir,
                        .content_dir_path = s.content_dir_path,
                        .variant_id = 0,
                        .multilingual = null,
                    },
                });
            },
            .Multilingual => |ml| {
                build.variants = try gpa.alloc(Variant, ml.locales.len);
                for (ml.locales, 0..) |locale, idx| {
                    worker.addJob(.{
                        .scan = .{
                            .variant = &build.variants[idx],
                            .base_dir = build.base_dir,
                            .content_dir_path = locale.content_dir_path,
                            .variant_id = @intCast(idx),
                            .multilingual = .{
                                .i18n_dir = build.i18n_dir,
                                .i18n_dir_path = ml.i18n_dir_path,
                                .locale_code = locale.code,
                            },
                        },
                    });
                }
            },
        }

        // Before we wait for content dirs to be scanned, we scan the layouts
        // directory in this thread.
        // TODO: find a better moment for this work
        try build.scanTemplates(gpa);
        try build.scanSiteAssets(gpa, arena);
        _ = arena_state.reset(.retain_capacity);

        for (build.cfg.getStaticAssets()) |path| {
            if (PathName.get(&build.st, &build.pt, path)) |pn| {
                if (build.site_assets.getPtr(pn)) |rc| {
                    rc.raw = 1;
                    continue;
                }
            }

            static_assets_errors = true;
            std.debug.print("error: static asset '{s}' does not exist\n", .{
                path,
            });
        }

        worker.wait(); // variants done scanning their content + i18n ziggy file

    }

    // Activate sectinos by parsing their index.smd page
    var i18n_errors = false;
    var any_content = false;
    {
        const tracy_frame = tracy.namedFrame("activate sections");
        defer tracy_frame.end();
        for (build.variants) |*v| {
            if (v.i18n_diag.errors.items.len > 0) {
                i18n_errors = true;

                var buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = std.fmt.bufPrint(&buf, "{}", .{std.fs.path.fmtJoin(&.{
                    build.cfg.Multilingual.i18n_dir_path,
                    v.i18n_diag.path.?,
                })}) catch v.i18n_diag.path.?;

                v.i18n_diag.path = path;
                std.debug.print("{}\n\n", .{v.i18n_diag.fmt(v.i18n_src)});
                continue;
            }

            for (v.sections.items[1..]) |*s| {
                any_content = true;
                worker.addJob(.{
                    .section_activate = .{
                        .variant = v,
                        .section = s,
                        .page = &v.pages.items[s.index],
                    },
                });
            }
        }

        // Stop if there is no content at all to analyze
        if (!any_content) fatal.msg(
            "No content found, start by adding a index.smd file to your content directory.\n",
            .{},
        );

        // Never a deadlock because we check that at least one page exists.
        worker.wait(); // sections have been activated (by parsing index.smd files)

    }
    // This second time, as we scan sections, we also propagate section
    // deactivation downward to avoid processing unreachable sections.
    var pages_to_parse: usize = 0;
    var progress_parse = progress.start("Parse pages", 0);
    var sites: std.StringArrayHashMapUnmanaged(context.Site) = .empty;
    {
        const tracy_frame = tracy.namedFrame("parse pages");
        defer tracy_frame.end();
        for (build.variants) |*v| {
            v.sections.items[0].active = true;
            for (v.sections.items[1..], 1..) |*s, idx| {
                assert(s.parent_section < idx);
                // This will access section 0 but its 'active' field is set correctly
                // (see 4 lines above)
                const parent = v.sections.items[s.parent_section];
                log.debug("section {} parent {} parent.active = {}", .{
                    idx, s.parent_section, parent.active,
                });

                if (!parent.active) s.active = false;
                if (!s.active) continue;

                pages_to_parse += s.pages.items.len;

                const index_smd: String = @enumFromInt(1);
                assert(v.string_table.get("index.smd").? == index_smd);
                for (s.pages.items) |page_index| {
                    const p = &v.pages.items[page_index];
                    if (p._scan.md_name == index_smd) continue; // already parsed
                    worker.addJob(.{
                        .page_parse = .{
                            .progress = progress_parse,
                            .variant = v,
                            .page = p,
                        },
                    });
                }
            }
        }

        progress_parse.setEstimatedTotalItems(pages_to_parse);

        switch (build.cfg) {
            .Site => |s| {
                try sites.putNoClobber(gpa, "", .{
                    .host_url = s.host_url,
                    .title = s.title,
                    ._meta = .{
                        .variant_id = 0,
                        .kind = .{ .simple = s.url_path_prefix },
                    },
                });
            },
            .Multilingual => |ml| {
                try sites.ensureTotalCapacity(gpa, build.variants.len);
                for (ml.locales, 0..) |loc, idx| sites.putAssumeCapacityNoClobber(loc.code, .{
                    .host_url = loc.host_url_override orelse ml.host_url,
                    .title = loc.site_title,
                    ._meta = .{
                        .variant_id = @intCast(idx),
                        .kind = .{
                            .multi = loc,
                        },
                    },
                });
            },
        }

        // In case all pages are section indexes, we might have content but no
        // pages to analyze at thist stage.
        if (pages_to_parse > 0) worker.wait(); // all active pages have been loaded and parsed
        progress_parse.end();
    }

    // TODO: move this onto the worker pool, we don't need to look at
    // sections for a while after this point, ideally it would require
    // having its own waitgroup.
    for (build.variants) |*v| {
        for (v.sections.items) |*s| {
            s.sortPages(v.pages.items);
        }
    }

    var parse_errors = false;
    var pages_to_analyze: usize = 0;
    var progress_page_analyze = progress.start("Analyze pages", 0);
    {
        const tracy_frame = tracy.namedFrame("analyze pages");
        defer tracy_frame.end();
        for (build.variants, 0..) |*v, vidx| {
            for (v.pages.items) |*p| {
                if (!p._parse.active) continue;

                // First we need to check the frontmatter as the ast will be valid
                // only if the frontmatter has been correctly identifed as well.
                switch (p._parse.status) {
                    .empty => {
                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        const path = buf[0..p._scan.md_path.bytesSlice(
                            &v.string_table,
                            &v.path_table,
                            &buf,
                            std.fs.path.sep,
                            p._scan.md_name,
                        )];
                        // Page is empty, print warning and skip it
                        std.debug.print("WARNING: Ignoring empty file '{s}'\n", .{path});
                        continue;
                    },

                    .frontmatter => |err| {
                        if (!parse_errors) {
                            parse_errors = true;
                        }

                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        const path = buf[0..p._scan.md_path.bytesSlice(
                            &v.string_table,
                            &v.path_table,
                            &buf,
                            std.fs.path.sep,
                            p._scan.md_name,
                        )];

                        const note = switch (err) {
                            error.MissingFrontmatter => "the document doesn't start with '---' (a frontmatter frame delimiter)",
                            error.OpenFrontmatter => "the frontmatter is missing a closing '---' frontmatter delimiter",
                        };

                        std.debug.print(
                            \\{s}:{}:1 error: frontmatter framing error
                            \\   {s}
                            \\
                        , .{ path, p._parse.fm.lines, note });
                        continue;
                    },

                    .ziggy => |*diag| {
                        if (!parse_errors) {
                            parse_errors = true;
                        }

                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        const path = buf[0..p._scan.md_path.bytesSlice(
                            &v.string_table,
                            &v.path_table,
                            &buf,
                            std.fs.path.sep,
                            p._scan.md_name,
                        )];

                        diag.path = path;
                        std.debug.print("{}\n\n", .{diag.fmt(p._parse.full_src)});
                        continue;
                    },

                    .parsed => {},
                }

                // Validate the layout field and reference count so that we
                // know to only load layouts that are actively used.
                // This is in some ways frontmatter analysis work but it's done
                // here because we have to scan all pages for errors anyway.
                layout: {
                    const layout_name = try build.st.intern(gpa, p.layout);
                    const layout = build.templates.getPtr(
                        .fromString(layout_name, true),
                    ) orelse {
                        // We can use analysis because a page that has
                        // parse.status == ok will have initialized the field for
                        // us.
                        try p._analysis.frontmatter.append(gpa, .layout);
                        break :layout;
                    };

                    if (layout.rc.fetchAdd(1, .monotonic) == 0) {
                        // We found the first active reference, submit a worker job
                        // to load the layout.
                        worker.addJob(.{
                            .template_parse = .{
                                .table = &build.st,
                                .templates = &build.templates,
                                .layouts_dir = build.layouts_dir,
                                .template = layout,
                                .name = p.layout,
                                .is_layout = true,
                            },
                        });
                    }

                    for (p.alternatives, 0..) |alt, aidx| {
                        const alt_layout_name = try build.st.intern(
                            gpa,
                            alt.layout,
                        );
                        const alt_layout = build.templates.getPtr(
                            .fromString(alt_layout_name, true),
                        ) orelse {
                            // We can use analysis because a page that has
                            // parse.status == ok will have initialized the field for
                            // us.
                            try p._analysis.frontmatter.append(gpa, .{
                                .alternative = .{
                                    .id = @intCast(aidx),
                                    .kind = .layout,
                                },
                            });
                            break :layout;
                        };

                        if (alt_layout.rc.fetchAdd(1, .monotonic) == 0) {
                            // We found the first active reference, submit a worker job
                            // to load the layout.
                            worker.addJob(.{
                                .template_parse = .{
                                    .table = &build.st,
                                    .templates = &build.templates,
                                    .layouts_dir = build.layouts_dir,
                                    .template = alt_layout,
                                    .name = alt.layout,
                                    .is_layout = true,
                                },
                            });
                        }
                    }
                }

                if (p._parse.ast.errors.len > 0) {
                    if (!parse_errors) {
                        parse_errors = true;
                    }
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const path = buf[0..p._scan.md_path.bytesSlice(
                        &v.string_table,
                        &v.path_table,
                        &buf,
                        std.fs.path.sep,
                        p._scan.md_name,
                    )];
                    printSuperMdErrors(
                        arena,
                        v.content_dir_path,
                        path,
                        &p._parse.ast,
                        p._parse.full_src[p._parse.fm.offset..],
                        p._parse.fm.lines,
                    );

                    // Do not schedule the page for analysis if contains parsing
                    // errors.
                    continue;
                }

                // Reaching here means that the page does not contain any parsing
                // error and can be scheduled for analysis. In theory we could
                // isolate ziggy syntax errors and only analize the supermd content
                // but it seems a minor optimization not worth the extra complexity.
                pages_to_analyze += 1;
                worker.addJob(.{
                    .page_analyze = .{
                        .progress = progress_page_analyze,
                        .build = &build,
                        .variant_id = @intCast(vidx),
                        .page = p,
                    },
                });
            }
        }

        progress_page_analyze.setEstimatedTotalItems(pages_to_analyze);
        worker.wait(); // layouts have been loaded and pages have been analyzed
        progress_page_analyze.end();
    }

    var analysis_errors = false;
    for (build.variants) |*v| {
        for (v.pages.items) |*p| {
            if (!p._parse.active) continue;
            if (p._parse.status != .parsed) continue;

            const fm_errors = &p._analysis.frontmatter;
            if (fm_errors.items.len > 0) {
                if (!analysis_errors) {
                    analysis_errors = true;
                }

                var buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = buf[0..p._scan.md_path.bytesSlice(
                    &v.string_table,
                    &v.path_table,
                    &buf,
                    std.fs.path.sep,
                    p._scan.md_name,
                )];

                const full_src = p._parse.full_src;
                const ast = ziggy.Ast.init(
                    arena,
                    full_src,
                    false,
                    true,
                    true,
                    null,
                ) catch unreachable;

                for (fm_errors.items) |err| {
                    const loc = err.location(full_src, ast);
                    const sel = loc.getSelection(full_src);
                    const line_off = loc.line(full_src);

                    const line_trim_left = std.mem.trimLeft(u8, line_off.line, &std.ascii.whitespace);
                    const start_trim_left = line_off.start + line_off.line.len - line_trim_left.len;

                    const caret_len = loc.end - loc.start;
                    const caret_spaces_len = loc.start -| start_trim_left;

                    const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

                    var hl_buf: [1024]u8 = undefined;

                    const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
                        const h = hl_buf[0 .. caret_len + caret_spaces_len];
                        @memset(h[0..caret_spaces_len], ' ');
                        @memset(h[caret_spaces_len..][0..caret_len], '^');
                        break :blk h;
                    } else "";

                    std.debug.print(
                        \\{s}/{s}:{}:{}: error: {s}
                        \\|    {s}
                        \\|    {s}
                        \\
                        \\
                    , .{
                        v.content_dir_path, path,      sel.start.line, sel.start.col,
                        err.title(),        line_trim, highlight,
                    });
                }
            }

            const page_errors = &p._analysis.page;
            if (page_errors.items.len > 0) {
                if (!analysis_errors) {
                    analysis_errors = true;
                }

                for (page_errors.items) |err| {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const path = buf[0..p._scan.md_path.bytesSlice(
                        &v.string_table,
                        &v.path_table,
                        &buf,
                        std.fs.path.sep,
                        p._scan.md_name,
                    )];

                    const n = err.node;
                    const range = n.range();
                    const md_src = p._parse.full_src[p._parse.fm.offset..];
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

                    var hl_buf: [1024]u8 = undefined;

                    const highlight = if (caret_len + caret_spaces_len + 1 < 1024) blk: {
                        const h = hl_buf[0 .. caret_len + caret_spaces_len + 1];
                        @memset(h[0..caret_spaces_len], ' ');
                        @memset(h[caret_spaces_len..][0 .. caret_len + 1], '^');
                        break :blk h;
                    } else "";

                    const fm_lines = p._parse.fm.lines;
                    std.debug.print(
                        \\{s}/{s}:{}:{}: error: {s}
                        \\|    {s}
                        \\|    {s}
                        \\
                        \\
                    , .{
                        v.content_dir_path, path,        fm_lines + n.startLine(),
                        n.startColumn(),    err.title(), line_trim,
                        highlight,
                    });
                }
            }
        }
    }

    // Output URL collision detection.
    // This code solves a simplified version of actual URL collision.
    // It assumes that directories can't have dots in their name, and
    // that files always have an extension, reducing collision detection
    // to just detecting duplicate paths. This simplified version
    // of the problem can be solved with a hash map, while solving the
    // full version will require using a tree for the `zine serve` case
    // and perhaps some clever scan algorithm in the `zine release` case.
    // Alternatively, if this algo proves to be sufficiently more efficent
    // than the tree case, we could default to this method and then only
    // switch to the more expensive approach if necessary.
    if (!parse_errors) {
        const tracy_frame = tracy.namedFrame("url collision");
        defer tracy_frame.end();
        for (build.variants) |*v| {
            for (v.pages.items, 0..) |p, pidx| {
                if (!p._parse.active) continue;
                if (p._parse.status != .parsed) continue;

                // page_main
                // const smd_out_dir_path: []const String = smd_out: {
                //     const path = p._scan.md_path;
                //     const name = p._scan.md_name;

                //     const index_smd: String = @enumFromInt(1);
                //     const index_html: String = @enumFromInt(11);
                //     assert(v.string_table.get("index.smd").? == index_smd);
                //     assert(v.string_table.get("index.html").? == index_html);
                //     const url: PathName = blk: {
                //         if (name == index_smd) break :blk .{
                //             .path = path,
                //             .name = index_html,
                //         };

                //         const name_no_ext = std.fs.path.stem(name.slice(&v.string_table));
                //         break :blk .{
                //             .path = try v.path_table.internExtend(
                //                 gpa,
                //                 path.slice(&v.path_table),
                //                 try v.string_table.intern(gpa, name_no_ext),
                //             ),
                //             .name = index_html,
                //         };
                //     };

                //     const loc: Variant.LocationHint = .{
                //         .kind = .page_main,
                //         .id = @intCast(pidx),
                //     };

                //     const gop = try v.urls.getOrPut(gpa, url);
                //     if (!gop.found_existing) {
                //         gop.value_ptr.* = loc;
                //     } else {
                //         try v.collisions.append(gpa, .{
                //             .url = url,
                //             .loc = loc,
                //             .previous = gop.value_ptr.*,
                //         });
                //     }
                //     break :smd_out url.path.slice(&v.path_table);
                // };

                // aliases
                for (p.aliases) |a| {
                    assert(std.mem.indexOfScalar(u8, a, '\\') == null);
                    assert(std.fs.path.extension(a).len > 0);
                    assert(std.mem.indexOfScalar(
                        u8,
                        std.fs.path.dirnamePosix(a) orelse "",
                        '.',
                    ) == null);
                    const path, const name = try v.path_table.internPathWithName(
                        gpa,
                        &v.string_table,
                        &.{},
                        a,
                    );

                    const url: PathName = .{
                        .path = path,
                        .name = name,
                    };

                    const loc: Variant.LocationHint = .{
                        .kind = .page_alias,
                        .id = @intCast(pidx),
                    };

                    const gop = try v.urls.getOrPut(gpa, url);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = loc;
                    } else {
                        try v.collisions.append(gpa, .{
                            .url = url,
                            .loc = loc,
                            .previous = gop.value_ptr.*,
                        });
                    }
                }

                // alternatives
                for (p.alternatives) |alt| {
                    assert(std.mem.indexOfScalar(u8, alt.output, '\\') == null);
                    assert(std.fs.path.extension(alt.output).len > 0);
                    assert(std.mem.indexOfScalar(
                        u8,
                        std.fs.path.dirnamePosix(alt.output) orelse "",
                        '.',
                    ) == null);

                    const path, const name = try v.path_table.internPathWithName(
                        gpa,
                        &v.string_table,
                        &.{},
                        alt.output,
                    );

                    const url: PathName = .{
                        .path = path,
                        .name = name,
                    };

                    const loc: Variant.LocationHint = .{
                        .kind = .{ .page_alternative = alt.name },
                        .id = @intCast(pidx),
                    };

                    const gop = try v.urls.getOrPut(gpa, url);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = loc;
                    } else {
                        try v.collisions.append(gpa, .{
                            .url = url,
                            .loc = loc,
                            .previous = gop.value_ptr.*,
                        });
                    }
                }
            }
        }
    }

    var collision_errors = false;
    for (build.variants) |v| {
        if (v.collisions.items.len > 0) {
            if (!collision_errors) {
                collision_errors = true;
            }
            for (v.collisions.items) |c| {
                std.debug.print(
                    \\{s}: error: output url collision detected
                    \\   between  {}
                    \\   and      {}
                    \\
                    \\
                , .{
                    c.url.fmt(&v.string_table, &v.path_table),
                    c.previous.fmt(&v.string_table, &v.path_table, v.pages.items),
                    c.loc.fmt(&v.string_table, &v.path_table, v.pages.items),
                });
            }
        }
    }

    worker.wait(); // layouts are done loading

    var template_errors = false;
    for (build.templates.keys(), build.templates.values()) |name, *template| {
        if (template.rc.load(.acquire) == 0) continue;
        if (template.html_ast.errors.len > 0) {
            if (!template_errors) {
                template_errors = true;
            }

            const path = try std.fs.path.join(arena, &.{
                build.cfg.getLayoutsDirPath(),
                name.toString().slice(&build.st),
            });

            std.debug.lockStdErr();
            defer std.debug.unlockStdErr();
            template.html_ast.printErrors(
                template.src,
                path,
            );
            continue;
        }

        if (template.ast.errors.len > 0) {
            if (!template_errors) {
                template_errors = true;
            }

            const path = try std.fs.path.join(arena, &.{
                build.cfg.getLayoutsDirPath(),
                name.toString().slice(&build.st),
            });

            std.debug.lockStdErr();
            defer std.debug.unlockStdErr();
            template.ast.printErrors(
                template.src,
                path,
            );
        }

        if (template.missing_parent) {
            const path = try std.fs.path.join(arena, &.{
                build.cfg.getLayoutsDirPath(),
                if (name.is_layout) "" else "templates",
                name.toString().slice(&build.st),
            });
            const parent_name = template.ast.nodes[template.ast.extends_idx].templateValue().span.slice(template.src);
            std.debug.print(
                \\{s}: error: extending a template that doesn't exist 
                \\   template '{s}' does not exist
                \\
            , .{
                path, parent_name,
            });
        }
    }

    if (static_assets_errors or i18n_errors or collision_errors or
        parse_errors or analysis_errors or template_errors)
    {
        // std.process.exit(1);
        return build;
    }

    // if (cmd == .tree) {
    //     try showTree(arena, &build);
    //     std.process.exit(0);
    // }

    var pages_to_render: usize = 0;
    var progress_page_render = progress.start("Render pages", 0);
    {
        const tracy_frame = tracy.namedFrame("page rendering");
        defer tracy_frame.end();
        for (build.variants) |*v| {
            for (v.pages.items) |*p| {
                // This seems a clear case where active should be
                // stored in a more compact fashion.
                if (!p._parse.active) continue;
                if (p._parse.status != .parsed) continue;

                pages_to_render += 1;

                if (builtin.single_threaded) std.debug.print("Rendering {s}...\n", .{
                    (PathName{
                        .path = p._scan.md_path,
                        .name = p._scan.md_name,
                    }).fmt(&v.string_table, &v.path_table),
                });
                worker.addJob(.{
                    .page_render = .{
                        .progress = progress_page_render,
                        .build = &build,
                        .sites = &sites,
                        .page = p,
                        .kind = .main,
                    },
                });

                for (0..p.alternatives.len) |aidx| {
                    worker.addJob(.{
                        .page_render = .{
                            .progress = progress_page_render,
                            .build = &build,
                            .sites = &sites,
                            .page = p,
                            .kind = .{ .alternative = @intCast(aidx) },
                        },
                    });
                }
            }
        }

        progress_page_render.setEstimatedTotalItems(pages_to_render);
        worker.wait(); // pages done rendering
        progress_page_render.end();
    }

    var progress_install_assets = progress.start("Install assets", 0);
    for (build.variants) |*v| {
        worker.addJob(.{
            .variant_assets_install = .{
                .progress = progress_install_assets,
                .install_dir = build.install_dir,
                .variant = v,
            },
        });
    }

    // install site assets
    {
        const site_assets_install_dir = switch (build.cfg) {
            .Site => build.install_dir,
            .Multilingual => |ml| blk: {
                if (ml.assets_prefix_path.len == 0) {
                    break :blk build.install_dir;
                } else {
                    break :blk build.install_dir.openDir(
                        ml.assets_prefix_path,
                        .{},
                    ) catch |err| fatal.dir(ml.assets_prefix_path, err);
                }
            },
        };

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var site_it = build.site_assets.iterator();
        while (site_it.next()) |entry| {
            const key = entry.key_ptr.*;
            const path = buf[0..key.path.bytesSlice(
                &build.st,
                &build.pt,
                &buf,
                std.fs.path.sep,
                key.name,
            )];

            if (entry.value_ptr.raw > 0) {
                _ = build.site_assets_dir.updateFile(
                    path,
                    site_assets_install_dir,
                    path,
                    .{},
                ) catch |err| fatal.file(path, err);
            }
        }
    }

    worker.wait(); // done installing assets
    progress_install_assets.end();

    return build;
}

fn printSuperMdErrors(
    arena: Allocator,
    content_dir_path: []const u8,
    md_path: []const u8,
    ast: *const supermd.Ast,
    md_src: []const u8,
    fm_lines: usize,
) void {
    _ = arena;
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    // \\It's strongly recommended to setup your editor to
    // \\leverage the `supermd` CLI tool in order to obtain
    // \\in-editor syntax checking and autoformatting.
    // \\
    // \\Download it from here:
    // \\   https://github.com/kristoff-it/supermd

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

        const extra: u32 = if (err.kind == .scripty) 1 else 0;

        const highlight = if (caret_len + caret_spaces_len + extra < 1024) blk: {
            const h = buf[0 .. caret_len + caret_spaces_len + extra];
            @memset(h[0..caret_spaces_len], ' ');
            @memset(h[caret_spaces_len..][0 .. caret_len + extra], '^');
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
        // const lines = range.end.row -| range.start.row;
        // const lines_fmt = if (lines == 0) "" else try std.fmt.allocPrint(
        //     arena,
        //     "(+{} lines)",
        //     .{lines},
        // );

        const tag_name = switch (err.kind) {
            .html => |h| switch (h.tag) {
                inline else => |t| @tagName(t),
            },
            else => @tagName(err.kind),
        };
        std.debug.print(
            \\{s}/{s}:{}:{}: [{s}] {s}
            \\|    {s}
            \\|    {s}
            \\
            \\
        , .{
            content_dir_path, md_path, fm_lines + range.start.row, range.start.col,
            tag_name,         msg,     line_trim,                  highlight,
        });
    }
}

pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    const separator = '/';

    // Find first non-empty path index.
    const first_path_index = blk: {
        for (paths, 0..) |path, index| {
            if (path.len == 0) continue else break :blk index;
        }

        // All paths provided were empty, so return early.
        return &[0]u8{};
    };

    // Calculate length needed for resulting joined path buffer.
    const total_len = blk: {
        var sum: usize = paths[first_path_index].len;
        var prev_path = paths[first_path_index];
        std.debug.assert(prev_path.len > 0);
        var i: usize = first_path_index + 1;
        while (i < paths.len) : (i += 1) {
            const this_path = paths[i];
            if (this_path.len == 0) continue;
            const prev_sep = prev_path[prev_path.len - 1] == separator;
            const this_sep = this_path[0] == separator;
            sum += @intFromBool(!prev_sep and !this_sep);
            sum += if (prev_sep and this_sep) this_path.len - 1 else this_path.len;
            prev_path = this_path;
        }

        break :blk sum;
    };

    const buf = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buf);

    @memcpy(buf[0..paths[first_path_index].len], paths[first_path_index]);
    var buf_index: usize = paths[first_path_index].len;
    var prev_path = paths[first_path_index];
    std.debug.assert(prev_path.len > 0);
    var i: usize = first_path_index + 1;
    while (i < paths.len) : (i += 1) {
        const this_path = paths[i];
        if (this_path.len == 0) continue;
        const prev_sep = prev_path[prev_path.len - 1] == separator;
        const this_sep = this_path[0] == separator;
        if (!prev_sep and !this_sep) {
            buf[buf_index] = separator;
            buf_index += 1;
        }
        const adjusted_path = if (prev_sep and this_sep) this_path[1..] else this_path;
        @memcpy(buf[buf_index..][0..adjusted_path.len], adjusted_path);
        buf_index += adjusted_path.len;
        prev_path = this_path;
    }

    // No need for shrink since buf is exactly the correct size.
    return buf;
}
