const std = @import("std");
const builtin = @import("builtin");
const supermd = @import("supermd");
const superhtml = @import("superhtml");
const ziggy = @import("ziggy");
const tracy = @import("tracy");
const syntax = @import("syntax");
const root = @import("root.zig");
const fatal = @import("fatal.zig");
const context = @import("context.zig");
const Build = @import("Build.zig");
const StringTable = @import("StringTable.zig");
const PathTable = @import("PathTable.zig");
const Variant = @import("Variant.zig");
const Template = @import("Template.zig");
const highlight = @import("highlight.zig");
const main = @import("main.zig");
const Channel = @import("channel.zig").Channel;
const String = StringTable.String;
const Path = PathTable.Path;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const Page = context.Page;
const assert = std.debug.assert;
const gpa = main.gpa;

const log = std.log.scoped(.worker);

// singleton
var ch_buf: [64]Job = undefined;
var ch: Channel(Job) = .init(&ch_buf);
var wg: std.Thread.WaitGroup = .{};
var threads: []std.Thread = &.{};

pub var started = false;
pub threadlocal var cmark: supermd.Ast.CmarkParser = undefined;
pub const extensions: [*]supermd.c.cmark_llist = undefined;

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
        variant_id: u32,
        multilingual: ?Variant.MultilingualScanParams,
        output_path_prefix: []const u8,
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
        build: *Build,
        sites: *const std.StringArrayHashMapUnmanaged(context.Site),
        page: *Page,
        kind: RenderJobKind,
    },

    variant_assets_install: struct {
        progress: std.Progress.Node,
        variant: *const Variant,
        install_dir: std.fs.Dir,
    },

    leave,
};

pub fn start() void {
    assert(!started);
    started = true;

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
            s.variant_id,
            s.multilingual,
            s.output_path_prefix,
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
            pr.sites,
            pr.page,
            pr.kind,
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
    const zone = tracy.trace(@src());
    defer zone.end();

    assert(page._parse.status == .parsed);
    if (builtin.mode == .Debug) {
        const last = page._debug.stage.swap(.analyzed, .monotonic);
        assert(last == .parsed);
    }

    const v = &build.variants[variant_id];
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const page_path = std.fmt.bufPrint(&buf, "{}", .{
        page._scan.file.fmt(
            &v.string_table,
            &v.path_table,
            v.content_dir_path,
        ),
    }) catch unreachable;

    const p = progress.start(page_path, 1);
    defer p.end();

    // We do not set all of analysis because it might contain a missing
    // layout error put there by the main thread.
    // page._analysis = .{};

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    var arena_state = page._parse.arena.promote(gpa);
    defer page._parse.arena = arena_state.state;
    const page_arena = arena_state.allocator();

    try analyzeFrontmatter(page_arena, page);
    try analyzeContent(page_arena, arena, build, variant_id, page);
}

fn analyzeFrontmatter(page_arena: Allocator, p: *Page) error{OutOfMemory}!void {
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

        if (a.len == 0 or !is_ascii) try errors.append(page_arena, .{
            .alias = @intCast(aidx),
        });
    }

    for (p.alternatives, 0..) |alt, aidx| {
        const is_ascii = for (alt.output) |c| {
            if (!std.ascii.isAscii(c)) break false;
        } else true;

        if (alt.output.len == 0 or !is_ascii) try errors.append(page_arena, .{
            .alternative = .{
                .id = @intCast(aidx),
                .kind = .path,
            },
        });

        if (alt.name.len == 0) try errors.append(page_arena, .{
            .alternative = .{
                .id = @intCast(aidx),
                .kind = .name,
            },
        });
    }
}

fn analyzeContent(
    page_arena: Allocator,
    scratch: Allocator,
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
        if (n.nodeType() == .CODE_BLOCK) blk: {
            const fence_info = n.fenceInfo() orelse break :blk;
            var fence_it = std.mem.tokenizeScalar(u8, fence_info, ' ');
            const lang = fence_it.next() orelse break :blk;

            if (!languageExists(lang)) {
                try errors.append(page_arena, .{
                    .node = n,
                    .kind = .{
                        .unknown_language = .{
                            .lang = lang,
                        },
                    },
                });
            }

            continue :outer;
        }

        const directive = n.getDirective() orelse continue;

        switch (directive.kind) {
            .section, .block, .heading, .text => {},
            .code => |code| {
                const path, const base_dir = switch (code.src.?) {
                    else => unreachable,
                    .page_asset => |pa| blk: {
                        assert(std.mem.indexOfScalar(u8, pa.ref, '\\') == null);
                        var buf: std.ArrayListUnmanaged(String) = .empty;

                        try buf.appendSlice(scratch, page._scan.url.slice(
                            &variant.path_table,
                        ));

                        var it = std.mem.tokenizeScalar(u8, pa.ref, '/');
                        while (it.next()) |component_bytes| {
                            const component = variant.string_table.get(
                                component_bytes,
                            ) orelse {
                                try errors.append(page_arena, .{
                                    .node = n,
                                    .kind = .{
                                        .missing_asset = .{
                                            .ref = pa.ref,
                                            .kind = .page,
                                        },
                                    },
                                });
                                continue :outer;
                            };
                            try buf.append(scratch, component);
                        }

                        const path_strings = buf.items[0 .. buf.items.len - 1];
                        const name = buf.items[buf.items.len - 1];
                        if (variant.path_table.get(path_strings)) |path| {
                            const pn: PathName = .{ .path = path, .name = name };
                            if (variant.urls.getPtr(pn)) |hint| {
                                switch (hint.kind) {
                                    .page_asset => {
                                        break :blk .{
                                            try std.fmt.allocPrint(scratch, "{}", .{
                                                pn.fmt(
                                                    &variant.string_table,
                                                    &variant.path_table,
                                                    null,
                                                ),
                                            }),
                                            variant.content_dir,
                                        };
                                    },
                                    else => {},
                                }
                            }
                        }

                        try errors.append(page_arena, .{
                            .node = n,
                            .kind = .{
                                .missing_asset = .{
                                    .ref = pa.ref,
                                    .kind = .page,
                                },
                            },
                        });
                        continue :outer;
                    },
                    .build_asset => |ba| blk: {
                        const asset = b.build_assets.get(ba.ref) orelse {
                            try errors.append(page_arena, .{
                                .node = n,
                                .kind = .{
                                    .missing_asset = .{
                                        .ref = ba.ref,
                                        .kind = .build,
                                    },
                                },
                            });
                            continue :outer;
                        };
                        break :blk .{ asset.input_path, b.site_assets_dir };
                    },
                    .site_asset => |*sa| blk: {
                        if (PathName.get(&b.st, &b.pt, sa.ref)) |pn| {
                            if (b.site_assets.contains(pn)) {
                                break :blk .{
                                    sa.ref,
                                    // dir is not relevant because the path is
                                    // absolute
                                    b.site_assets_dir,
                                };
                            }
                        }

                        try errors.append(page_arena, .{
                            .node = n,
                            .kind = .{
                                .missing_asset = .{
                                    .ref = sa.ref,
                                    .kind = .site,
                                },
                            },
                        });
                        continue :outer;
                    },
                };
                const src = base_dir.readFileAlloc(
                    page_arena,
                    path,
                    std.math.maxInt(u32),
                ) catch |err| fatal.file(path, err);

                if (!languageExists(code.language)) {
                    try errors.append(page_arena, .{
                        .node = n,
                        .kind = .{
                            .unknown_language = .{
                                .lang = code.language.?,
                            },
                        },
                    });
                    continue :outer;
                }

                directive.kind.code.src = .{ .url = src };
            },

            // Link, Image, Video directives
            inline else => |*val| {
                switch (val.src.?) {
                    .url => continue :outer,
                    .self_page => |*resolved_alt| {
                        // This value is only expected for Link directives.
                        if (@TypeOf(val.*) != supermd.context.Link) continue :outer;

                        if (val.alternative) |alt_name| {
                            for (page.alternatives) |alt| {
                                if (std.mem.eql(u8, alt.name, alt_name)) {
                                    resolved_alt.* = alt.output;
                                    break;
                                }
                            } else {
                                try errors.append(page_arena, .{
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
                            if (!val.ref_unsafe and !ast.ids.contains(ref) and ref.len > 0) {
                                try errors.append(page_arena, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_ref = .{
                                            .ref = ref,
                                        },
                                    },
                                });
                                continue :outer;
                            }
                        }
                    },

                    .page => |*p| {
                        // This value is only expected for Link directives.
                        if (@TypeOf(val.*) != supermd.context.Link) continue :outer;

                        const path: Path = switch (p.kind) {
                            .absolute => blk: {
                                log.debug("absolute page link '{s}'", .{p.ref});
                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    &.{},
                                    p.ref,
                                )) |path| break :blk path;
                                log.debug("page link '{s}': path not found", .{p.ref});
                                if (builtin.mode == .Debug) {
                                    var it = std.mem.tokenizeScalar(u8, p.ref, '/');
                                    while (it.next()) |c| {
                                        log.debug("'{s}' -> [{?d}]", .{
                                            c, variant.string_table.get(c),
                                        });
                                    }
                                }

                                try errors.append(page_arena, .{
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
                                // Sibling means that the path is rooted in
                                // the current's section path. All pages have
                                // a section except the root index page.
                                const section_id = page._scan.parent_section_id;
                                if (section_id == 0) {
                                    try errors.append(page_arena, .{
                                        .node = n,
                                        .kind = .no_parent_section,
                                    });
                                    continue :outer;
                                }

                                const section = variant.sections.items[section_id];
                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    section.content_sub_path.slice(
                                        &variant.path_table,
                                    ),
                                    p.ref,
                                )) |path| break :blk path;

                                try errors.append(page_arena, .{
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
                                // Subpage means that the final path is
                                // based on the current page's URL path.
                                // It also is only available on pages that
                                // are sections, which means that the page
                                // is guaranteed to be named `index.smd`.
                                if (page._scan.file.name != index_smd) {
                                    try errors.append(page_arena, .{
                                        .node = n,
                                        .kind = .not_a_section,
                                    });
                                    continue :outer;
                                }

                                var buf: std.ArrayListUnmanaged(String) = .empty;
                                try buf.appendSlice(scratch, page._scan.file.path.slice(
                                    &variant.path_table,
                                ));

                                if (variant.path_table.getPathNoName(
                                    &variant.string_table,
                                    buf.items,
                                    p.ref,
                                )) |path| break :blk path;

                                try errors.append(page_arena, .{
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

                        const pn: PathName = .{ .path = path, .name = index_html };
                        const hint = variant.urls.get(pn) orelse {
                            log.debug("absolute page link '{s}': hint not found", .{
                                p.ref,
                            });
                            try errors.append(page_arena, .{
                                .node = n,
                                .kind = .{
                                    .unknown_page = .{
                                        .ref = p.ref,
                                    },
                                },
                            });
                            continue :outer;
                        };

                        log.debug("absolute page link '{s}' hint: {any}", .{ p.ref, hint });
                        switch (hint.kind) {
                            .page_main => {},
                            else => {
                                log.debug("absolute page link '{s}' wrong kint kind: {any}", .{ p.ref, hint.kind });
                                try errors.append(page_arena, .{
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

                        const other_page = if (p.locale) |loc| {
                            _ = loc;
                            @panic("TODO");
                        } else variant.pages.items[hint.id];

                        p.resolved = .{
                            .page_id = hint.id,
                            .variant_id = other_page._scan.variant_id,
                            .path = @intFromEnum(path),
                        };

                        if (val.alternative) |alt_name| {
                            log.debug("absolute page link '{s}' has alternative: {s}", .{
                                p.ref,
                                alt_name,
                            });
                            for (other_page.alternatives) |alt| {
                                if (std.mem.eql(u8, alt.name, alt_name)) {
                                    p.resolved.alt = alt.output;
                                    break;
                                }
                            } else {
                                try errors.append(page_arena, .{
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
                                try errors.append(page_arena, .{
                                    .node = n,
                                    .kind = .{
                                        .unknown_ref = .{
                                            .ref = ref,
                                        },
                                    },
                                });
                                continue :outer;
                            }
                        }
                    },

                    .page_asset => |*pa| {
                        assert(std.mem.indexOfScalar(u8, pa.ref, '\\') == null);
                        var buf: std.ArrayListUnmanaged(String) = .empty;

                        try buf.appendSlice(
                            scratch,
                            page._scan.url.slice(&variant.path_table),
                        );

                        var it = std.mem.tokenizeScalar(u8, pa.ref, '/');
                        while (it.next()) |component_bytes| {
                            const component = variant.string_table.get(
                                component_bytes,
                            ) orelse {
                                try errors.append(page_arena, .{
                                    .node = n,
                                    .kind = .{
                                        .missing_asset = .{
                                            .ref = pa.ref,
                                            .kind = .site,
                                        },
                                    },
                                });
                                continue :outer;
                            };
                            try buf.append(scratch, component);
                        }

                        const path_strings = buf.items[0 .. buf.items.len - 1];
                        const name = buf.items[buf.items.len - 1];
                        if (variant.path_table.get(path_strings)) |path| {
                            const pn: PathName = .{ .path = path, .name = name };
                            if (variant.urls.getPtr(pn)) |hint| {
                                switch (hint.kind) {
                                    .page_asset => |*rc| {
                                        // TODO: when going from zero to one
                                        //       grab image size info if needed
                                        _ = rc.fetchAdd(1, .acq_rel);
                                        pa.resolved = .{
                                            .path = @intFromEnum(path),
                                            .name = @intFromEnum(name),
                                        };
                                        continue :outer;
                                    },
                                    else => {},
                                }
                            }
                        }

                        try errors.append(page_arena, .{
                            .node = n,
                            .kind = .{
                                .missing_asset = .{
                                    .ref = pa.ref,
                                    .kind = .page,
                                },
                            },
                        });
                        continue :outer;
                    },
                    .site_asset => |*sa| { //ref
                        assert(std.mem.indexOfScalar(u8, sa.ref, '\\') == null);

                        const dirname = std.fs.path.dirnamePosix(sa.ref) orelse "";
                        if (b.pt.getPathNoName(&b.st, &.{}, dirname)) |path| {
                            const basename = std.fs.path.basenamePosix(sa.ref);
                            if (b.st.get(basename)) |name| {
                                const pn: PathName = .{
                                    .path = path,
                                    .name = name,
                                };

                                if (b.site_assets.getPtr(pn)) |rc| {
                                    _ = rc.fetchAdd(1, .acq_rel);
                                    sa.resolved = .{
                                        .path = @intFromEnum(path),
                                        .name = @intFromEnum(name),
                                    };
                                    continue :outer;
                                }
                            }
                        }

                        try errors.append(page_arena, .{
                            .node = n,
                            .kind = .{
                                .missing_asset = .{
                                    .ref = sa.ref,
                                    .kind = .site,
                                },
                            },
                        });
                        continue :outer;
                    },
                    .build_asset => |*ba| {
                        const asset = b.build_assets.getPtr(ba.ref) orelse {
                            try errors.append(page_arena, .{
                                .node = n,
                                .kind = .{
                                    .missing_asset = .{
                                        .ref = ba.ref,
                                        .kind = .build,
                                    },
                                },
                            });
                            continue :outer;
                        };

                        _ = asset.rc.fetchAdd(1, .acq_rel);

                        const install_path = asset.install_path orelse {
                            try errors.append(page_arena, .{
                                .node = n,
                                .kind = .{
                                    .build_asset_missing_install_path = .{
                                        .ref = ba.ref,
                                    },
                                },
                            });
                            continue :outer;
                        };

                        ba.ref = install_path;
                    },

                    // Asset was found successfully.

                    // if (directive.kind == .image) blk: {
                    // const image_handle = std.fs.cwd().openFile(path_bytes.items, .{}) catch break :blk;
                    // defer image_handle.close();
                    // var image_header_buf: [2048]u8 = undefined;
                    // const image_header_len = image_handle.readAll(&image_header_buf) catch break :blk;
                    // const image_header = image_header_buf[0..image_header_len];

                    // const img_size = getImageSize(image_header) catch break :blk;
                    // directive.kind.image.size = .{ .w = img_size.w, .h = img_size.h };
                }
            },
        }
    }
}

pub const RenderJobKind = union(enum) { main, alternative: u32 };
const SuperVM = superhtml.VM(context.Template, context.Value);
fn renderPage(
    arena: Allocator,
    progress: std.Progress.Node,
    build: *Build,
    sites: *const std.StringArrayHashMapUnmanaged(context.Site),
    page: *Page,
    kind: RenderJobKind,
) void {
    const zone = tracy.trace(@src());
    defer zone.end();

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const variant_id = page._scan.variant_id;
    const variant = &build.variants[variant_id];

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const page_path = std.fmt.bufPrint(&buf, "{}", .{
        page._scan.file.fmt(
            &variant.string_table,
            &variant.path_table,
            variant.content_dir_path,
        ),
    }) catch unreachable;

    tracy.messageCopy(page_path);

    const progress_name = switch (kind) {
        .main => page_path,
        .alternative => |idx| blk: {
            const alt_name = page.alternatives[idx].name;
            break :blk try std.fmt.allocPrint(arena, "{s} (alternative '{s}')", .{
                page_path,
                alt_name,
            });
        },
    };

    const p = progress.start(progress_name, 0);
    defer p.end();

    // page._meta = .{
    //     // .is_root = true,
    //     .src = page._parse.full_src[page._parse.fm.offset..],
    //     .ast = page._parse.ast,
    //     .word_count = @intCast(page._parse.full_src[page._parse.fm.offset..].len / 6),
    //     // .index_in_section = 0,
    //     // .parent_section_path = "",
    // };

    var ctx: context.Template = .{
        .site = &sites.entries.items(.value)[variant_id],
        .page = page,
        .i18n = variant.i18n,
        .build = undefined,
        ._meta = .{
            .build = build,
            .sites = sites,
        },
    };

    ctx.build.generated = .initNow();

    const layout_path = switch (kind) {
        .main => page.layout,
        .alternative => |idx| page.alternatives[idx].layout,
    };

    const layout_name_str = build.st.get(layout_path).?;
    const layout = build.templates.get(.fromString(layout_name_str, true)).?;

    var out_buf: std.ArrayListUnmanaged(u8) = .empty;
    var err_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer if (build.mode == .disk) err_buf.deinit(gpa);

    var super_vm = SuperVM.init(
        arena,
        &ctx,
        layout_path,
        build.cfg.getLayoutsDirPath(),
        layout.src,
        layout.html_ast,
        layout.ast,
        std.mem.endsWith(u8, layout_path, ".xml"),
        page_path,
        out_buf.writer(gpa),
        err_buf.writer(gpa),
    );

    while (true) super_vm.run() catch |err| switch (err) {
        error.Done => break,
        error.Fatal => {
            std.debug.print("{s}\n", .{err_buf.items});
            build.any_rendering_error.store(true, .release);
            if (build.mode == .memory) {
                switch (kind) {
                    .main => page._render.errors = err_buf.items,
                    .alternative => |aidx| page._render.alternatives[aidx].errors = err_buf.items,
                }
            }
            return;
        },
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

            const t = build.templates.get(.fromString(
                build.st.get(template_name).?,
                false,
            )).?;

            super_vm.insertTemplate(
                template_path,
                t.src,
                t.html_ast,
                t.ast,
                std.mem.endsWith(u8, template_name, ".xml"),
            );
        },
    };

    switch (build.mode) {
        .memory => switch (kind) {
            .main => {
                page._render.out = out_buf.items;
                page._render.errors = "";
            },
            .alternative => |aidx| {
                page._render.alternatives[aidx].out = out_buf.items;
                page._render.alternatives[aidx].errors = "";
            },
        },
        .disk => |disk| {
            defer out_buf.deinit(gpa);
            const out_raw = switch (kind) {
                .main => blk: {
                    const out_dir_path = switch (build.cfg.*) {
                        .Site => |s| try std.fmt.allocPrint(arena, "{}index.html", .{
                            page._scan.url.fmt(
                                &variant.string_table,
                                &variant.path_table,
                                s.url_path_prefix,
                                true,
                            ),
                        }),
                        .Multilingual => try std.fmt.allocPrint(arena, "{}index.html", .{
                            page._scan.url.fmt(
                                &variant.string_table,
                                &variant.path_table,
                                variant.output_path_prefix,
                                true,
                            ),
                        }),
                    };

                    // note: do not close build.install_dir
                    var out_dir = if (out_dir_path.len == 0) disk.install_dir else disk.install_dir.makeOpenPath(
                        out_dir_path,
                        .{},
                    ) catch |err| fatal.dir(out_dir_path, err);
                    defer if (out_dir_path.len > 0) out_dir.close();

                    break :blk out_dir.createFile(
                        "index.html",
                        .{},
                    ) catch |err| fatal.file("index.html", err);
                },

                .alternative => |idx| blk: {
                    const raw_path = page.alternatives[idx].output;
                    const out_path = if (raw_path[0] == '/') raw_path[1..] else try root.join(
                        arena,
                        &.{ page_path, raw_path },
                        std.fs.path.sep,
                    );

                    if (std.fs.path.dirnamePosix(out_path)) |path| {
                        disk.install_dir.makePath(
                            path,
                        ) catch |err| fatal.dir(path, err);
                    }

                    break :blk disk.install_dir.createFile(
                        out_path,
                        .{},
                    ) catch |err| fatal.file("index.html", err);
                },
            };
            defer out_raw.close();
            out_raw.writeAll(out_buf.items) catch |err| fatal.file(
                page_path,
                err,
            );
        },
    }
}

// Null language evaluates to true for convenience.
pub fn languageExists(language: ?[]const u8) bool {
    const lang = language orelse return true;

    if (std.mem.eql(u8, lang, "=html")) return true;

    if (syntax.FileType.get_by_name(lang) == null) {
        var buf: [1024]u8 = undefined;
        const filename = std.fmt.bufPrint(
            &buf,
            "file.{s}",
            .{lang},
        ) catch "<lang name too long>";
        if (syntax.FileType.guess(filename, "") == null) {
            return false;
        }
    }

    return true;
}
