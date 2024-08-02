const std = @import("std");
const ziggy = @import("ziggy");
const templating = @import("templating.zig");
const context = @import("../src/context.zig");
const zine = @import("../build.zig");

const FrontParser = ziggy.frontmatter.Parser(context.Page);
const TranslationIndex = std.StringArrayHashMap(TranslationIndexEntry);
const TranslationIndexEntry = struct {
    index_file: std.Build.LazyPath = undefined,
    page_variants: std.ArrayListUnmanaged(PageVariant) = .{},
};
const PageVariant = struct {
    locale_code: []const u8,
    page: *Section.Page,
    _meta: struct {
        host_url_override: ?[]const u8,
    },
};

const AddWebsiteOptions = union(enum) {
    multilingual: zine.MultilingualSite,
    site: zine.Site,

    pub fn getAssets(web: AddWebsiteOptions) zine.AssetMap {
        return switch (web) {
            inline else => |v| v.buildtime_assets,
        };
    }
};
pub fn addWebsiteImpl(
    b: *std.Build,
    opts: zine.ZineOptions,
    step: *std.Build.Step,
    web: AddWebsiteOptions,
) void {
    const zine_dep = b.dependencyFromBuildZig(zine, .{
        .optimize = opts.optimize,
        .scope = opts.scopes,
    });

    {
        const assets = web.getAssets();
        var it = assets.iterator();
        while (it.next()) |kv| {
            const msg =
                \\build.zig error: buildtime asset '{s}': only LazyPaths from generated files (eg from a RunStep) or dependencies are allowed
                \\
                \\note: set 'assets_dir_path' and use `$assets.file('{s}')` to access it from Scripty
                \\
                \\
                \\
            ;
            switch (kv.value_ptr.*) {
                .src_path => |v| {
                    std.debug.print(msg, .{ kv.key_ptr.*, v.sub_path });
                    std.process.exit(1);
                },
                .cwd_relative => |v| {
                    std.debug.print(msg, .{ kv.key_ptr.*, v });
                    std.process.exit(1);
                },
                .generated, .dependency => {},
            }
        }
    }
    // Install static files
    const static_dir_path = switch (web) {
        .multilingual => |ml| ml.static_dir_path,
        .site => |s| s.static_dir_path,
    };
    const install_static = b.addInstallDirectory(.{
        .source_dir = b.path(static_dir_path),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    step.dependOn(&install_static.step);

    // Scan the content folder
    scan(b, step, opts.optimize == .Debug, zine_dep, web);
}

fn scan(
    project: *std.Build,
    step: *std.Build.Step,
    debug: bool,
    zine_dep: *std.Build.Dependency,
    website: AddWebsiteOptions,
) void {
    const index_dir = project.cache_root.handle.makeOpenPath(
        "zine",
        .{},
    ) catch unreachable;

    const renderer = zine_dep.artifact("markdown-renderer");
    const layout = zine_dep.artifact("layout");
    switch (website) {
        .multilingual => |ml| {
            ensureDir(ml.layouts_dir_path);
            ensureDir(ml.static_dir_path);
            ensureDir(ml.i18n_dir_path);

            var ti = TranslationIndex.init(project.allocator);
            const scanned_variants = project.allocator.alloc(
                ScannedVariant,
                ml.variants.len,
            ) catch unreachable;

            for (ml.variants, scanned_variants) |v, *sv| {
                const output_path_prefix = v.output_prefix_override orelse
                    v.locale_code;
                const url_path_prefix = v.output_prefix_override orelse
                    if (v.host_url_override != null) "" else v.locale_code;

                const i18n_file_path = project.pathJoin(&.{
                    ml.i18n_dir_path,
                    project.fmt("{s}.ziggy", .{v.locale_code}),
                });

                sv.* = scanVariant(
                    project,
                    index_dir,
                    debug,
                    v.content_dir_path,
                    url_path_prefix,
                );
                sv.output_path_prefix = output_path_prefix;
                sv.url_path_prefix = url_path_prefix;
                sv.i18n_file_path = i18n_file_path;

                if (sv.root_index) |*idx| indexTranslation(
                    project,
                    &ti,
                    v.host_url_override,
                    v.locale_code,
                    idx,
                );
                var it = sv.sections.constIterator(0);
                while (it.next()) |s| {
                    for (s.pages.items) |*p| {
                        indexTranslation(
                            project,
                            &ti,
                            v.host_url_override,
                            v.locale_code,
                            p,
                        );
                    }
                }
            }

            writeTranslationIndex(project, &ti);

            for (ml.variants, scanned_variants) |v, sv| {
                addAllSteps(
                    project,
                    step,
                    renderer,
                    layout,
                    v.title,
                    v.host_url_override orelse ml.host_url,
                    ml.layouts_dir_path,
                    v.content_dir_path,
                    sv.output_path_prefix,
                    sv.i18n_file_path,
                    sv.root_index,
                    sv.sections,
                    &ti,
                );
            }
        },
        .site => |s| {
            ensureDir(s.layouts_dir_path);
            ensureDir(s.static_dir_path);

            const prefix = s.output_prefix;
            const sv = scanVariant(
                project,
                index_dir,
                debug,
                s.content_dir_path,
                prefix,
            );
            addAllSteps(
                project,
                step,
                renderer,
                layout,
                s.title,
                s.host_url,
                s.layouts_dir_path,
                s.content_dir_path,
                prefix,
                null,
                sv.root_index,
                sv.sections,
                null,
            );
        },
    }
}

fn indexTranslation(
    project: *std.Build,
    translation_index: *TranslationIndex,
    host_url_override: ?[]const u8,
    locale_code: []const u8,
    p: *Section.Page,
) void {
    const fm = p.fm.translation_key;
    const key = if (fm.len != 0) fm else project.pathJoin(&.{ p.content_sub_path, p.md_name });

    const gop = translation_index.getOrPut(key) catch unreachable;

    if (!gop.found_existing) {
        gop.value_ptr.* = .{};
    }

    gop.value_ptr.page_variants.append(project.allocator, .{
        .locale_code = locale_code,
        .page = p,
        ._meta = .{
            .host_url_override = host_url_override,
        },
    }) catch unreachable;
}

fn writeTranslationIndex(project: *std.Build, ti: *TranslationIndex) void {
    const write_file_step = project.addWriteFiles();
    for (ti.keys(), ti.values()) |k, *t| {
        var buf = std.ArrayList(u8).init(project.allocator);
        ziggy.stringify(t.page_variants.items, .{}, buf.writer()) catch unreachable;

        t.index_file = write_file_step.add(k, buf.items);
    }
}

const SectionList = std.SegmentedList(Section, 0);
const ScannedVariant = struct {
    root_index: ?Section.Page,
    sections: SectionList,
    output_path_prefix: []const u8 = undefined,
    url_path_prefix: []const u8 = undefined,
    i18n_file_path: []const u8 = undefined,
};

pub fn scanVariant(
    project: *std.Build,
    index_dir: std.fs.Dir,
    debug: bool,
    content_dir_path: []const u8,
    url_path_prefix: []const u8,
) ScannedVariant {
    var t = std.time.Timer.start() catch unreachable;
    defer if (debug) std.debug.print(
        "Content scan took {}ms\n",
        .{t.read() / std.time.ns_per_ms},
    );

    const content_dir = std.fs.cwd().makeOpenPath(
        content_dir_path,
        .{ .iterate = true },
    ) catch |err| {
        std.debug.print("Unable to open the content directory: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const Entry = struct {
        dir: std.fs.Dir,
        path: []const u8,
        parent_section: ?*Section,
    };

    var dir_stack = std.ArrayList(Entry).init(project.allocator);
    dir_stack.append(.{
        .dir = content_dir,
        .path = "",
        .parent_section = null,
    }) catch unreachable;

    var sections: SectionList = .{};
    const root_section = sections.addOne(project.allocator) catch unreachable;
    root_section.* = .{};

    var root_index: ?Section.Page = null;
    var current_section = root_section;
    while (dir_stack.popOrNull()) |dir_entry| {
        defer {
            var d = dir_entry.dir;
            d.close();
            if (dir_entry.parent_section) |p| {
                current_section = p;
            }
        }

        if (dir_entry.dir.openFile("index.md", .{})) |file| blk: {
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            const r = buf_reader.reader();
            const result = FrontParser.parse(project.allocator, r, "index.md") catch @panic("TODO: report frontmatter parser error");

            const permalink = project.pathJoin(&.{ "/", url_path_prefix, dir_entry.path, "/" });

            const fm = switch (result) {
                .success => |s| fm: {
                    var h = s.header;
                    h._meta.permalink = permalink;
                    var letters: usize = 0;
                    while (true) {
                        const c = r.readByte() catch break;
                        switch (c) {
                            'a'...'z', 'A'...'Z' => letters += 1,
                            else => {},
                        }
                    }

                    h._meta.word_count = @intCast(letters / 5);
                    break :fm h;
                },
                .empty => {
                    std.debug.print("WARNING: ignoring empty file '{s}{s}'\n", .{
                        permalink, "index.md",
                    });
                    break :blk;
                },
                .framing_error => |line| {
                    std.debug.print("ERROR: bad frontmatter framing in '{s}{s}' (line {})\n", .{
                        permalink, "index.md", line,
                    });
                    std.process.exit(1);
                },
                .ziggy_error => |diag| {
                    std.debug.print("{s}{}", .{ permalink, diag });
                    std.process.exit(1);
                },
            };

            if (fm.draft) break :blk;

            // This is going to be null only for 'contents/index.md'
            if (dir_entry.parent_section) |parent_section| {
                const content_sub_path = project.dupe(dir_entry.path);
                current_section = sections.addOne(project.allocator) catch unreachable;
                current_section.* = .{};
                parent_section.pages.append(project.allocator, .{
                    .content_sub_path = content_sub_path,
                    .md_name = "index.md",
                    .fm = fm,
                    .subpages = current_section,
                }) catch unreachable;
            } else {
                root_index = .{
                    .content_sub_path = project.dupe(dir_entry.path),
                    .md_name = "index.md",
                    .fm = fm,

                    .subpages = root_section,
                };
            }

            if (fm.skip_subdirs) continue;
        } else |index_md_err| {
            if (index_md_err != error.FileNotFound) {
                std.debug.print(
                    "Unable to access `index.md` in {s}\n",
                    .{content_dir_path},
                );
                std.process.exit(1);
            }
        }

        var it = dir_entry.dir.iterate();
        while (it.next() catch unreachable) |entry| {
            switch (entry.kind) {
                else => continue,
                .file => if (std.mem.endsWith(u8, entry.name, ".md")) {
                    if (std.mem.eql(u8, entry.name, "index.md")) continue;
                    const file = dir_entry.dir.openFile(entry.name, .{}) catch {
                        std.debug.print(
                            "Error while reading {s} in /{s}\n",
                            .{ entry.name, dir_entry.path },
                        );
                        std.process.exit(1);
                    };
                    defer file.close();

                    var buf_reader = std.io.bufferedReader(file.reader());
                    const r = buf_reader.reader();

                    const permalink = project.pathJoin(&.{
                        "/",
                        url_path_prefix,
                        dir_entry.path,
                        entry.name[0 .. entry.name.len - 3],
                    });

                    const result = FrontParser.parse(project.allocator, r, entry.name) catch @panic("TODO: report frontmatter parse error");
                    const fm = switch (result) {
                        .success => |s| fm: {
                            var h = s.header;
                            h._meta.permalink = project.pathJoin(&.{ permalink, "/" });
                            var letters: usize = 0;
                            while (true) {
                                const c = r.readByte() catch break;
                                switch (c) {
                                    'a'...'z', 'A'...'Z' => letters += 1,
                                    else => {},
                                }
                            }

                            h._meta.word_count = @intCast(letters / 5);
                            break :fm h;
                        },
                        .empty => {
                            std.debug.print("WARNING: ignoring empty file '{s}.md'\n", .{
                                permalink,
                            });
                            continue;
                        },
                        .framing_error => |line| {
                            std.debug.print("ERROR: bad frontmatter framing in '{s}.md' (line {})\n", .{
                                permalink, line,
                            });
                            std.process.exit(1);
                        },
                        .ziggy_error => |diag| {
                            std.debug.print("{}", .{diag});
                            std.process.exit(1);
                        },
                    };

                    if (fm.draft) continue;

                    current_section.pages.append(project.allocator, .{
                        .content_sub_path = project.dupe(dir_entry.path),
                        .md_name = project.dupe(entry.name),
                        .fm = fm,
                    }) catch unreachable;
                },
                .directory => {
                    dir_stack.append(.{
                        .dir = dir_entry.dir.openDir(
                            entry.name,
                            .{ .iterate = true },
                        ) catch unreachable,
                        .path = project.pathJoin(&.{ dir_entry.path, entry.name }),
                        .parent_section = current_section,
                    }) catch unreachable;
                },
            }
        }
    }

    var section_it = sections.iterator(0);
    while (section_it.next()) |s| {
        s.writeIndex(project, index_dir);
        for (s.pages.items) |*p| {
            p.writeMeta(project);
        }
    }

    return .{
        .sections = sections,
        .root_index = root_index,
    };
}

pub fn addAllSteps(
    project: *std.Build,
    step: *std.Build.Step,
    renderer: *std.Build.Step.Compile,
    layout: *std.Build.Step.Compile,
    site_title: []const u8,
    host_url: []const u8,
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    output_path_prefix: []const u8,
    i18n_file_path: ?[]const u8,
    root_index: ?Section.Page,
    sections: SectionList,
    translation_index: ?*TranslationIndex,
) void {
    if (root_index) |idx| {
        const page_variants_index = if (translation_index) |ti| blk: {
            const fm = idx.fm.translation_key;
            const key = if (fm.len != 0) fm else "index.md";

            const entry = ti.get(key).?;
            break :blk entry.index_file;
        } else null;
        const rendered = addMarkdownRenderStep(
            project,
            step,
            renderer,
            content_dir_path,
            "",
            "index.md",
            output_path_prefix,
            idx.fm._meta.permalink,
        );
        addLayoutStep(
            project,
            step,
            layout,
            site_title,
            host_url,
            content_dir_path,
            layouts_dir_path,
            "",
            "index.md",
            "index.html",
            rendered.content,
            rendered.meta,
            idx.fm.layout,
            idx.fm.aliases,
            // null,
            // null,
            // idx.subpages.?.index,
            output_path_prefix,
            i18n_file_path,
            page_variants_index,
        );
        for (idx.fm.alternatives) |alt| {
            addLayoutStep(
                project,
                step,
                layout,
                site_title,
                host_url,
                content_dir_path,
                layouts_dir_path,
                idx.content_sub_path,
                idx.md_name,
                alt.output,
                rendered.content,
                rendered.meta,
                alt.layout,
                &.{},
                // null,
                // null,
                // idx.subpages.?.index,
                output_path_prefix,
                i18n_file_path,
                page_variants_index,
            );
        }
    }

    var section_it = sections.constIterator(0);
    while (section_it.next()) |s| {
        for (s.pages.items, 0..) |p, idx| {
            const page_variants_index = if (translation_index) |ti| blk: {
                const fm = p.fm.translation_key;
                const key = if (fm.len != 0) fm else project.pathJoin(&.{ p.content_sub_path, p.md_name });
                const entry = ti.get(key).?;
                const result = entry.index_file;
                break :blk result;
            } else null;

            const next = if (idx == 0) null else s.pages.items[idx - 1].meta;
            const prev = if (idx == s.pages.items.len - 1) null else s.pages.items[idx + 1].meta;
            const rendered = addMarkdownRenderStep(
                project,
                step,
                renderer,
                content_dir_path,
                p.content_sub_path,
                p.md_name,
                output_path_prefix,
                p.fm._meta.permalink,
            );
            const sub_index = if (p.subpages) |subsection| subsection.index else null;

            const out_basename = p.md_name[0 .. p.md_name.len - 3];
            const out_path = if (std.mem.eql(u8, out_basename, "index"))
                project.pathJoin(&.{ p.content_sub_path, "index.html" })
            else
                project.pathJoin(&.{ p.content_sub_path, out_basename, "index.html" });

            addLayoutStep(
                project,
                step,
                layout,
                site_title,
                host_url,
                content_dir_path,
                layouts_dir_path,
                p.content_sub_path,
                p.md_name,
                out_path,
                rendered.content,
                rendered.meta,
                p.fm.layout,
                p.fm.aliases,
                // prev,
                // next,
                // sub_index,
                output_path_prefix,
                i18n_file_path,
                page_variants_index,
            );
            for (p.fm.alternatives) |alt| {
                addLayoutStep(
                    project,
                    step,
                    layout,
                    site_title,
                    host_url,
                    content_dir_path,
                    layouts_dir_path,
                    p.content_sub_path,
                    p.md_name,
                    alt.output,
                    rendered.content,
                    rendered.meta,
                    alt.layout,
                    &.{},
                    // prev,
                    // next,
                    // sub_index,
                    output_path_prefix,
                    i18n_file_path,
                    page_variants_index,
                );
            }
        }
    }
}

const RenderResult = struct {
    content: std.Build.LazyPath,
    meta: std.Build.LazyPath,
};

fn addMarkdownRenderStep(
    project: *std.Build,
    step: *std.Build.Step,
    renderer: *std.Build.Step.Compile,
    content_dir_path: []const u8,
    content_sub_path: []const u8,
    md_basename: []const u8,
    output_path_prefix: []const u8,
    permalink: []const u8,
) RenderResult {
    const in_path = project.pathJoin(&.{ content_dir_path, content_sub_path, md_basename });
    const out_basename = md_basename[0 .. md_basename.len - 3];

    const render_step = project.addRunArtifact(renderer);
    // assets_in_dir_path
    render_step.addDirectoryArg(project.path(project.pathJoin(&.{ content_dir_path, content_sub_path })));
    // assets_dep_path
    _ = render_step.addDepFileOutputArg("_zine_assets.d");
    // assets_out_dir_path
    const assets_dir = render_step.addOutputFileArg(".");
    // md_in_path
    render_step.addFileArg(project.path(in_path));
    // html_out_path
    const rendered_md = render_step.addOutputFileArg("_zine_rendered.html");
    // frontmatter + computed metadata
    const page_metadata = render_step.addOutputFileArg("_zine_meta.ziggy");
    // permalink
    render_step.addArg(permalink);

    const install_subpath = if (std.mem.eql(u8, out_basename, "index"))
        content_sub_path
    else
        project.pathJoin(&.{ content_sub_path, out_basename });

    // install all referenced files as assets (only images are detected for now)
    const install_assets = project.addInstallDirectory(.{
        .source_dir = assets_dir,
        .install_dir = .prefix,
        .install_subdir = project.pathJoin(&.{ output_path_prefix, install_subpath }),
        .exclude_extensions = &.{ "_zine_assets.d", "_zine_meta.ziggy", "_zine_rendered.html" },
    });

    step.dependOn(&install_assets.step);

    return .{
        .content = rendered_md,
        .meta = page_metadata,
    };
}

fn addLayoutStep(
    project: *std.Build,
    step: *std.Build.Step,
    layout: *std.Build.Step.Compile,
    title: []const u8,
    host_url: []const u8,
    content_dir_path: []const u8,
    layouts_dir_path: []const u8,
    content_sub_path: []const u8,
    md_basename: []const u8,
    out_path: []const u8,
    rendered_md: std.Build.LazyPath,
    meta: std.Build.LazyPath,
    layout_name: []const u8,
    aliases: []const []const u8,
    // prev: ?std.Build.LazyPath,
    // next: ?std.Build.LazyPath,
    // subpages: ?std.Build.LazyPath,
    output_path_prefix: []const u8,
    i18n_file_path: ?[]const u8,
    page_variants_index: ?std.Build.LazyPath,
) void {
    const layout_path = project.pathJoin(&.{ layouts_dir_path, layout_name });
    std.fs.cwd().access(layout_path, .{}) catch |err| {
        std.debug.print("Unable to find the layout '{s}' used by '{s}/{s}/{s}'\n. Please create it before running `zig build` again.\nError: {s}\n,", .{
            layout_path,
            content_dir_path,
            content_sub_path,
            md_basename,
            @errorName(err),
        });
        std.process.exit(1);
    };

    const layout_step = project.addRunArtifact(layout);
    // output file
    const final_html = layout_step.addOutputFileArg("output.html");
    // rendered_md_path
    layout_step.addFileArg(rendered_md);
    // meta (frontmatter + extra info)
    layout_step.addFileArg(meta);
    // md_name
    layout_step.addArg(project.pathJoin(&.{ content_sub_path, md_basename }));
    // layout_path
    layout_step.addFileArg(project.path(layout_path));
    // layout_name
    layout_step.addArg(layout_name);
    // templates_dir_path
    layout_step.addArg(project.pathJoin(&.{ layouts_dir_path, "templates" }));
    // dep file
    _ = layout_step.addDepFileOutputArg("templates.d");
    // site base url
    layout_step.addArg(host_url);
    // site title
    layout_step.addArg(title);

    if (prev) |p| layout_step.addFileArg(p) else layout_step.addArg("null");
    if (next) |n| layout_step.addFileArg(n) else layout_step.addArg("null");
    if (subpages) |s| layout_step.addFileArg(s) else layout_step.addArg("null");
    if (i18n_file_path) |i| layout_step.addFileArg(project.path(i)) else layout_step.addArg("null");
    if (page_variants_index) |i| layout_step.addFileArg(i) else layout_step.addArg("null");

    const target_output = project.addInstallFile(
        final_html,
        project.pathJoin(&.{ output_path_prefix, out_path }),
    );
    step.dependOn(&target_output.step);

    for (aliases) |a| {
        const alias = project.addInstallFile(
            final_html,
            project.pathJoin(&.{ output_path_prefix, a }),
        );
        step.dependOn(&alias.step);
    }
}

///    ----------  PAGE METADATA  ----------
///
///
///
///
///
///
///    ----------  SECTION INDEX  ----------
/// One file per section, organized on the filesystem
/// as a mirror of the content folder.
///     /posts/index.md  ->  /posts/section_index
///
/// The index contains:
/// - hash of the file
/// - mapping from file name to
///
///
///
///
///
///
const Section = struct {
    pages: std.ArrayListUnmanaged(Page) = .{},

    // NOTE: toggled off to try the index_dir strat
    // Not used while iterating directories
    // index: std.Build.LazyPath = undefined,

    const Page = struct {
        content_sub_path: []const u8,
        md_name: []const u8,
        fm: context.Page,

        // Present if this page is an 'index.md' and set
        // to the section defined by this page.
        subpages: ?*Section = null,

        // NOTE: toggled off to try the index_dir strat
        // Not used while iterating directories
        // meta: std.Build.LazyPath = undefined,

        pub const ziggy_options = struct {
            pub fn stringify(
                value: Page,
                opts: ziggy.serializer.StringifyOptions,
                indent_level: usize,
                depth: usize,
                writer: anytype,
            ) !void {
                return ziggy.serializer.stringifyInner(value.fm, opts, indent_level, depth, writer);
            }
        };

        pub fn lessThan(_: void, lhs: Page, rhs: Page) bool {
            return rhs.fm.date.lessThan(lhs.fm.date);
        }

        pub fn writeMeta(
            p: *Page,
            index_dir: std.fs.Dir,
            project: *std.Build,
        ) void {
            var buf = std.ArrayList(u8).init(project.allocator);
            ziggy.stringify(p.fm, .{}, buf.writer()) catch unreachable;
            // if this trips, we need to replicate the logic from
            // writeindex
            std.debug.assert(p.content_sub_path.len != 0);
            const page_dir = index_dir.makeOpenPath(
                p.content_sub_path,
                .{},
            ) catch unreachable;
            const page_file = page_dir.createFile("page_meta.ziggy", .{}) catch unreachable;
            defer page_file.close();
            page_file.writeAll(buf.items) catch unreachable;
            // const write_file_step = project.addWriteFiles();
            // p.meta = write_file_step.add("page_meta.ziggy", buf.items);
            // step.dependOn(p.meta.generated.file.step);
        }
    };

    pub fn writeIndex(
        s: *Section,
        index_dir: std.fs.Dir,
        project: *std.Build,
    ) void {
        std.mem.sort(Page, s.pages.items, {}, Page.lessThan);
        var buf = std.ArrayList(u8).init(project.allocator);
        ziggy.stringify(s.pages.items, .{}, buf.writer()) catch unreachable;
        const section_dir = if (s.content_sub_path.len == 0)
            index_dir
        else
            index_dir.makeOpenPath(s.content_sub_path, .{}) catch unreachable;
        const section_file = section_dir.createFile("section.ziggy", .{}) catch unreachable;
        defer section_file.close();
        section_file.writeAll(buf.items) catch unreachable;

        // step.dependOn(s.index.generated.file.step);
        // const write_file_step = project.addWriteFiles();
        // s.index = write_file_step.add("section.ziggy", buf.items);
    }
};

pub fn ensureDir(path: []const u8) void {
    std.fs.cwd().makePath(path) catch |err| {
        std.debug.print("Error while creating '{s}': {s}\n", .{
            path, @errorName(err),
        });
        std.process.exit(1);
    };
}
