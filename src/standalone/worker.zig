const std = @import("std");
const builtin = @import("builtin");
const supermd = @import("supermd");
const superhtml = @import("superhtml");
const ziggy = @import("ziggy");
const fatal = @import("../fatal.zig");
const context = @import("../context.zig");
const Build = @import("../Build.zig");
const StringTable = @import("../StringTable.zig");
const PathTable = @import("../PathTable.zig");
const Variant = @import("../Variant.zig");
const Template = @import("../Template.zig");
const highlight = @import("../highlight.zig");
const Channel = @import("channel.zig").Channel;
const String = StringTable.String;
const Path = PathTable.Path;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const Page = context.Page;
const assert = std.debug.assert;

const log = std.log.scoped(.worker);

// singleton
var ch_buf: [64]Job = undefined;
var ch: Channel(Job) = .init(&ch_buf);
var wg: std.Thread.WaitGroup = .{};
var threads: []std.Thread = &.{};

pub threadlocal var cmark: supermd.Ast.CmarkParser = undefined;
pub const extensions: [*]supermd.c.cmark_llist = undefined;

const gpa = @import("../main.zig").gpa;

pub const Job = union(enum) {
    template_parse: struct {
        table: *const StringTable,
        templates: *const Build.Templates,
        layouts_dir: std.fs.Dir,
        template: *Template,
        name: []const u8,
        is_layout: bool,
    },
    scan: struct {
        variant: *Variant,
        base_dir: std.fs.Dir,
        content_dir_path: []const u8,
    },
    section_activate: struct {
        variant: *const Variant,
        section: *Variant.Section,
        page: *Page,
    },
    page_parse: struct {
        progress: std.Progress.Node,
        variant: *const Variant,
        page: *Page,
    },
    page_analyze: struct {
        progress: std.Progress.Node,
        build: *const Build,
        variant_id: u32,
        page: *Page,
    },
    page_render: struct {
        progress: std.Progress.Node,
        build: *const Build,
        variant_id: u32,
        page: *Page,
    },

    variant_assets_install: struct {
        progress: std.Progress.Node,
        variant: *const Variant,
        install_dir: std.fs.Dir,
    },

    leave,
};

pub fn start() void {
    std.debug.assert(threads.len == 0);
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    supermd.c.cmark_gfm_core_extensions_ensure_registered();

    if (builtin.single_threaded) {
        cmark = supermd.Ast.CmarkParser.default();
        return;
    }

    const thread_count = @max(1, std.Thread.getCpuCount() catch 1);
    threads = try gpa.alloc(std.Thread, thread_count);

    for (0..thread_count) |idx| {
        const _cmark = supermd.Ast.CmarkParser.default();
        threads[idx] = std.Thread.spawn(
            .{ .allocator = gpa },
            workerFn,
            .{_cmark},
        ) catch |err| fatal.msg("error: unable to spawn thread pool: {s}\n", .{
            @errorName(err),
        });
    }
}

pub fn stopWaitAndDeinit() void {
    if (builtin.mode != .Debug) return;
    if (builtin.single_threaded) addJob(.leave);

    for (threads) |_| addJob(.leave);
    for (threads) |t| t.join();
    gpa.free(threads);
}

var single_threaded_arena_state = std.heap.ArenaAllocator.init(gpa);
const single_threaded_arena = single_threaded_arena_state.allocator();
pub fn addJob(job: Job) void {
    if (builtin.single_threaded) {
        const continue_ = runOneJob(single_threaded_arena, job);
        _ = single_threaded_arena_state.reset(.retain_capacity);

        if (builtin.mode == .Debug and !continue_) {
            single_threaded_arena_state.deinit();
        }
    } else {
        wg.start();
        ch.put(job);
    }
}

pub fn wait() void {
    if (builtin.single_threaded) return;

    wg.wait();
    wg.reset();
}

fn workerFn(
    _cmark: supermd.Ast.CmarkParser,
) void {
    cmark = _cmark;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    while (runOneJob(arena, ch.get())) {
        _ = arena_state.reset(.retain_capacity);
        wg.finish();
    }
}

inline fn runOneJob(
    arena: Allocator,
    job: Job,
) bool {
    switch (job) {
        .leave => {
            supermd.c.cmark_parser_free(cmark.parser);
            return false;
        },
        .template_parse => |tp| tp.template.parse(
            gpa,
            arena,
            tp.table,
            tp.templates,
            tp.layouts_dir,
            tp.name,
            tp.is_layout,
        ),
        .scan => |s| s.variant.scanContentDir(
            gpa,
            arena,
            s.base_dir,
            s.content_dir_path,
        ),
        .section_activate => |ap| ap.section.activate(
            gpa,
            ap.variant,
            ap.page,
        ),
        .page_parse => |pp| pp.page.parse(gpa, cmark, pp.progress, pp.variant),
        .page_render => |pr| renderPage(
            arena,
            pr.progress,
            pr.build,
            pr.variant_id,
            pr.page,
        ),
        .page_analyze => |pa| analyzePage(
            arena,
            pa.progress,
            pa.build,
            pa.variant_id,
            pa.page,
        ),

        .variant_assets_install => |vai| vai.variant.installAssets(
            vai.progress,
            vai.install_dir,
        ),
    }
    return true;
}

fn analyzePage(
    arena: Allocator,
    progress: std.Progress.Node,
    build: *const Build,
    variant_id: u32,
    page: *Page,
) void {
    assert(page._parse.status == .parsed);
    if (builtin.mode == .Debug) {
        const last = page._debug.stage.swap(.analyzed, .monotonic);
        assert(last == .parsed);
    }

    const p = progress.start(page._scan.md_name.slice(&build.variants[variant_id].string_table), 1);
    defer p.end();

    // We do not set all of analysis because it might contain a missing
    // layout error put there by the main thread.
    // page._analysis = .{};

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    try analyzeFrontmatter(page);
    try analyzeContent(arena, build, variant_id, page);
}

fn analyzeFrontmatter(p: *Page) error{OutOfMemory}!void {
    // We don't validate layout because it will be validated
    // later on by the main function where we will also check
    // if the file exists or not. Leaving this check here
    // would result in duplicated error reporting.
    // if (p.layout.len == 0) try errors.append(gpa, .layout);

    const errors = &p._analysis.frontmatter;

    for (p.aliases, 0..) |a, aidx| {
        const is_ascii = for (a) |c| {
            if (!std.ascii.isAscii(c)) break false;
        } else true;

        if (a.len == 0 or !is_ascii) try errors.append(gpa, .{
            .alias = @intCast(aidx),
        });
    }

    for (p.alternatives, 0..) |alt, aidx| {
        const is_ascii = for (alt.output) |c| {
            if (!std.ascii.isAscii(c)) break false;
        } else true;

        if (alt.output.len == 0 or !is_ascii) try errors.append(gpa, .{
            .alternative = .{
                .id = @intCast(aidx),
                .kind = .path,
            },
        });

        if (alt.name.len == 0) try errors.append(gpa, .{
            .alternative = .{
                .id = @intCast(aidx),
                .kind = .name,
            },
        });
    }
}

fn analyzeContent(
    arena: Allocator,
    b: *const Build,
    variant_id: u32,
    page: *Page,
) error{OutOfMemory}!void {
    const ast = &page._parse.ast;
    const errors = &page._analysis.page;
    const variant = &b.variants[variant_id];
    const index_smd: String = @enumFromInt(1);
    assert(variant.string_table.get("index.smd") == index_smd);
    const index_html: String = @enumFromInt(11);
    assert(variant.string_table.get("index.html") == index_html);

    var current: ?supermd.Node = ast.md.root.firstChild();
    outer: while (current) |n| : (current = n.next(ast.md.root)) {
        const directive = n.getDirective() orelse continue;

        switch (directive.kind) {
            .section, .block, .heading, .text => {},
            .code => |code| {
                const path = switch (code.src.?) {
                    else => unreachable,
                    .page_asset => @panic("TODO"),
                    .build_asset => @panic("TODO"),
                    .site_asset => |ref| blk: {
                        if (PathName.get(&b.st, &b.pt, ref)) |pn| {
                            if (b.site_assets.getPtr(pn)) |rc| {
                                _ = rc.fetchAdd(1, .acq_rel);
                                break :blk ref;
                            }
                        }

                        try errors.append(gpa, .{
                            .node = n,
                            .kind = .{
                                .missing_asset = .{
                                    .ref = ref,
                                    .kind = .site,
                                },
                            },
                        });

                        // Stop analyzing this node.
                        continue :outer;
                    },
                };

                const src = std.fs.cwd().readFileAlloc(
                    gpa,
                    path,
                    std.math.maxInt(u32),
                ) catch |err| fatal.file(path, err);

                const lang = code.language orelse {
                    directive.kind.code.src = .{ .url = src };
                    continue;
                };

                if (std.mem.eql(u8, lang, "=html")) {
                    directive.kind.code.src = .{ .url = src };
                    continue;
                }

                var buf = std.ArrayList(u8).init(gpa);

                highlight.highlightCode(arena, lang, src, buf.writer()) catch |err| switch (err) {
                    // else => unreachable,
                    else => @panic("unexpected error in syntax highlighter\n"),
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidLanguage => {
                        try errors.append(gpa, .{
                            .node = n,
                            .kind = .{
                                .unknown_language = .{
                                    .lang = lang,
                                },
                            },
                        });
                        continue :outer;
                    },
                };
                directive.kind.code.src = .{ .url = buf.items };
            },

            // Link, Image, Video directives
            inline else => |*val, tag| {
                switch (val.src.?) {
                    .url => continue :outer,
                    .self_page => {
                        // This value is only expected for Link directives.
                        if (@TypeOf(val.*) != supermd.context.Link) continue :outer;

                        var path_bytes = std.ArrayList(u8).init(gpa);
                        if (val.alternative) |alt_name| {
                            for (page.alternatives) |alt| {
                                if (std.mem.eql(u8, alt.name, alt_name)) {
                                    try path_bytes.appendSlice(alt.output);
                                    break;
                                }
                            } else {
                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_alternative = .{
                                            .name = alt_name,
                                        },
                                    },
                                });
                            }
                        }

                        if (val.ref) |ref| {
                            try path_bytes.append('#');
                            try path_bytes.appendSlice(ref);
                            if (!val.ref_unsafe and !ast.ids.contains(ref)) {
                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_ref = .{
                                            .ref = ref,
                                        },
                                    },
                                });
                            }
                        }

                        @field(directive.kind, @tagName(tag)).src = .{ .url = path_bytes.items };
                        continue :outer;
                    },

                    .page => |p| {
                        // This value is only expected for Link directives.
                        if (@TypeOf(val.*) != supermd.context.Link) continue :outer;

                        // page: struct {
                        //     kind: enum {
                        //         absolute,
                        //         sub,
                        //         sibling,
                        //     },
                        //     ref: []const u8,
                        //     locale: ?[]const u8 = null,
                        // },
                        //

                        // Here we will place the path as we compose it
                        // and later on we will append to it ref/alt
                        // information as needed.
                        var path_bytes = std.ArrayList(u8).init(gpa);
                        try path_bytes.append('/');
                        const pn: PathName = switch (p.kind) {
                            .absolute => blk: {
                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    p.ref,
                                )) |path| {
                                    try path_bytes.appendSlice(p.ref);
                                    break :blk .{
                                        .path = path,
                                        .name = index_html,
                                    };
                                }

                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_page = .{
                                            .ref = p.ref,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                            .sibling => blk: {
                                try path_bytes.writer().print("{s}{s}", .{
                                    page._scan.md_path.fmt(
                                        &variant.string_table,
                                        &variant.path_table,
                                        true,
                                    ),
                                    p.ref,
                                });

                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    path_bytes.items,
                                )) |path| {
                                    break :blk .{
                                        .path = path,
                                        .name = index_html,
                                    };
                                }

                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_page = .{
                                            .ref = p.ref,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                            .sub => blk: {
                                try path_bytes.writer().print("{s}", .{
                                    page._scan.md_path.fmt(
                                        &variant.string_table,
                                        &variant.path_table,
                                        true,
                                    ),
                                });
                                if (page._scan.md_name != index_smd) {
                                    try path_bytes.writer().print("{s}/", .{
                                        page._scan.md_name.slice(
                                            &variant.string_table,
                                        ),
                                    });
                                }

                                try path_bytes.appendSlice(p.ref);

                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    path_bytes.items,
                                )) |path| {
                                    break :blk .{
                                        .path = path,
                                        .name = index_html,
                                    };
                                }

                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_page = .{
                                            .ref = p.ref,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                        };

                        const hint = variant.urls.get(pn) orelse {
                            try errors.append(gpa, .{
                                .node = n,
                                .kind = .{
                                    .unknown_page = .{
                                        .ref = p.ref,
                                    },
                                },
                            });
                            continue :outer;
                        };

                        switch (hint.kind) {
                            .page_main => {},
                            else => {
                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .resource_kind_mismatch = .{
                                            .expected = .page_main,
                                            .got = hint.kind,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                        }

                        const other_page = variant.pages.items[hint.id];

                        if (val.alternative) |alt_name| {
                            for (other_page.alternatives) |alt| {
                                if (std.mem.eql(u8, alt.name, alt_name)) {
                                    // TODO: semantics for relative output paths
                                    assert(std.mem.startsWith(u8, alt.output, "/"));
                                    try path_bytes.appendSlice(alt.output);
                                    break;
                                }
                            } else {
                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_alternative = .{
                                            .name = alt_name,
                                        },
                                    },
                                });
                                continue :outer;
                            }
                        }

                        if (val.ref) |ref| {
                            if (!val.ref_unsafe and !other_page._parse.ast.ids.contains(ref)) {
                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_ref = .{
                                            .ref = ref,
                                        },
                                    },
                                });
                                continue :outer;
                            }

                            try path_bytes.append('#');
                            try path_bytes.appendSlice(ref);
                        }

                        @field(directive.kind, @tagName(tag)).src = .{ .url = path_bytes.items };
                        // const page_site = if (p.locale) |lc|
                        //     sites.get(lc) orelse reportError(
                        //         n,
                        //         md_src,
                        //         md_rel_path,
                        //         md_path,
                        //         fm_offset,
                        //         is_section,
                        //         try std.fmt.allocPrint(
                        //             gpa,
                        //             "could not find locale '{s}'",
                        //             .{lc},
                        //         ),
                        //     )
                        // else
                        //     site;
                        // if (@hasField(@TypeOf(val), "alternative")) {
                    },

                    .page_asset, .site_asset => |ref| { //ref
                        assert(std.mem.indexOfScalar(u8, ref, '\\') == null);

                        var path_bytes = std.ArrayList(u8).init(gpa);
                        try path_bytes.append('/');
                        switch (val.src.?) {
                            else => unreachable,
                            // NOTE: site assets are stored in the build string
                            //       and path tables, and must be serched in the
                            //       build's assets hashmap.
                            .site_asset => blk: {
                                const dirname = std.fs.path.dirnamePosix(ref) orelse "";
                                if (b.pt.getPathNoName(&b.st, dirname)) |path| {
                                    const basename = std.fs.path.basenamePosix(ref);
                                    if (b.st.get(basename)) |name| {
                                        try path_bytes.appendSlice(ref);
                                        const pn: PathName = .{
                                            .path = path,
                                            .name = name,
                                        };

                                        if (b.site_assets.getPtr(pn)) |rc| {
                                            _ = rc.fetchAdd(1, .acq_rel);
                                            break :blk;
                                        }
                                    }
                                }

                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .missing_asset = .{
                                            .ref = ref,
                                            .kind = .site,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                            .page_asset => blk: {
                                try path_bytes.writer().print("{s}", .{
                                    page._scan.md_path.fmt(
                                        &variant.string_table,
                                        &variant.path_table,
                                        ref[0] != '/',
                                    ),
                                });
                                try path_bytes.appendSlice(ref);

                                const dirname = std.fs.path.dirnamePosix(path_bytes.items) orelse "";
                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    dirname,
                                )) |path| {
                                    const basename = std.fs.path.basenamePosix(ref);
                                    if (variant.string_table.get(basename)) |name| {
                                        const pn: PathName = .{
                                            .path = path,
                                            .name = name,
                                        };

                                        if (variant.urls.getPtr(pn)) |hint| {
                                            switch (hint.kind) {
                                                .page_asset => |*rc| {
                                                    _ = rc.fetchAdd(1, .acq_rel);
                                                    break :blk;
                                                },
                                                else => {},
                                            }
                                        }
                                    }
                                }

                                try errors.append(gpa, .{
                                    .node = n,
                                    .kind = .{
                                        .missing_asset = .{
                                            .ref = ref,
                                            .kind = .page,
                                        },
                                    },
                                });
                                continue :outer;
                            },
                        }

                        // Asset was found successfully.

                        // if (directive.kind == .image) blk: {
                        // const image_handle = std.fs.cwd().openFile(path_bytes.items, .{}) catch break :blk;
                        // defer image_handle.close();
                        // var image_header_buf: [2048]u8 = undefined;
                        // const image_header_len = image_handle.readAll(&image_header_buf) catch break :blk;
                        // const image_header = image_header_buf[0..image_header_len];

                        // const img_size = getImageSize(image_header) catch break :blk;
                        // directive.kind.image.size = .{ .w = img_size.w, .h = img_size.h };
                        // }
                        @field(directive.kind, @tagName(tag)).src = .{ .url = path_bytes.items };
                    },
                    .build_asset => @panic("TODO"),
                }
            },
        }
    }
}

const SuperVM = superhtml.VM(context.Template, context.Value);
fn renderPage(
    arena: Allocator,
    progress: std.Progress.Node,
    build: *const Build,
    variant_id: u32,
    page: *Page,
) void {
    _ = gpa;
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const variant = &build.variants[variant_id];

    const md_name = page._scan.md_name.slice(&variant.string_table);
    // const md_name = if (locale_code) |lc| try std.fmt.allocPrint(
    //     arena,
    //     "{s} ({s})",
    //     .{ md_rel_path, lc },
    // ) else md_rel_path;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const md_path = path_buf[0..page._scan.md_path.bytesSlice(
        &variant.string_table,
        &variant.path_table,
        &path_buf,
        std.fs.path.sep,
        null,
    )];

    const p = progress.start(md_path, 0);
    defer p.end();

    page._meta = .{
        // .is_root = true,
        .src = page._parse.full_src[page._parse.fm.offset..],
        .ast = page._parse.ast,
        .word_count = @intCast(page._parse.full_src[page._parse.fm.offset..].len / 6),
        // .index_in_section = 0,
        // .parent_section_path = "",
    };

    const site: context.Site = .{
        .host_url = build.cfg.Site.host_url,
        .title = build.cfg.Site.title,
        ._meta = .{ .kind = .simple },
    };
    var ctx: context.Template = .{
        .site = &site,
        .page = page,
        .i18n = undefined,
        .build = undefined,
        ._meta = .{
            .build = build,
            .variant_id = variant_id,
        },
    };

    const layout_name_str = build.st.get(page.layout).?;
    const layout = build.templates.get(.fromString(layout_name_str, true)).?;

    const index_smd: String = @enumFromInt(1);
    const out_dir_path = if (page._scan.md_name == index_smd)
        md_path
    else
        try std.fs.path.join(arena, &.{
            md_path,
            std.fs.path.stem(md_name),
        });

    // note: do not close build.install_dir
    var out_dir = if (md_path.len == 0) build.install_dir else build.install_dir.makeOpenPath(
        out_dir_path,
        .{},
    ) catch |err| fatal.dir(out_dir_path, err);

    const out_raw = out_dir.createFile(
        "index.html",
        .{},
    ) catch |err| fatal.file("index.html", err);

    var out_buf = std.io.bufferedWriter(out_raw.writer());
    const out = out_buf.writer();

    var super_vm = SuperVM.init(
        arena,
        &ctx,
        page.layout,
        build.cfg.getLayoutsDirPath(),
        layout.src,
        std.mem.endsWith(u8, page.layout, ".xml"),
        md_name,
        out,
        std.io.getStdErr().writer(),
    );

    while (true) super_vm.run() catch |err| switch (err) {
        error.Done => break,
        error.Fatal => std.process.exit(1),
        error.OutOfMemory => fatal.oom(),
        error.OutIO, error.ErrIO => fatal.msg("i/o error in superhtml", .{}),
        error.Quota => super_vm.setQuota(100),
        error.WantSnippet => @panic("TODO: looad snippet"),
        error.WantTemplate => {
            const template_name = super_vm.wantedTemplateName();
            const template_path = try std.fs.path.join(arena, &.{
                build.cfg.getLayoutsDirPath(),
                "templates",
                template_name,
            });

            log.debug("loading template = '{s}'", .{template_path});
            const template_html = readFile(
                arena,
                build.base_dir,
                template_path,
            ) catch |ioerr| {
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
        },
    };

    out_buf.flush() catch |err| fatal.file(md_name, err);
}

fn readFile(
    arena: Allocator,
    dir: std.fs.Dir,
    path: []const u8,
) ![:0]const u8 {
    return dir.readFileAllocOptions(
        arena,
        path,
        1024 * 1024,
        null,
        1,
        0,
    );
}
