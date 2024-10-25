const std = @import("std");
const ziggy = @import("ziggy");
const templating = @import("templating.zig");
const context = @import("../src/context.zig");
const zine = @import("../build.zig");

const join = @import("../src/root.zig").join;

const log = struct {
    const l = std.log.scoped(.scan);

    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        if (false) l.debug(fmt, args);
    }
};

const FrontParser = ziggy.frontmatter.Parser(context.Page);
const TranslationKeyIndex = std.StringArrayHashMap(TKEntry);
const TKEntry = std.ArrayListUnmanaged(Key);
const Key = struct {
    code: []const u8,
    md_rel_path: []const u8,
};

const AddWebsiteOptions = union(enum) {
    multilingual: zine.MultilingualSite,
    site: zine.Site,
};
pub fn addWebsiteImpl(
    project: *std.Build,
    opts: zine.ZineOptions,
    step: *std.Build.Step,
    web: AddWebsiteOptions,
    include_drafts: bool,
) void {
    const zine_dep = project.dependencyFromBuildZig(zine, .{
        .optimize = opts.optimize,
        .scope = opts.scopes,
    });

    // Scan the content folder
    scan(project, step, opts.optimize == .Debug, zine_dep, web, include_drafts);
}

fn scan(
    project: *std.Build,
    step: *std.Build.Step,
    debug: bool,
    zine_dep: *std.Build.Dependency,
    website: AddWebsiteOptions,
    include_drafts: bool,
) void {
    const index_dir_path = join(project.allocator, &.{
        project.cache_root.path orelse ".",
        "zine",
    }) catch unreachable;
    const index_dir = project.cache_root.handle.makeOpenPath(
        "zine",
        .{},
    ) catch unreachable;

    // buldtime assets
    index_dir.makePath("a") catch unreachable;
    // subpages index
    const subpages_index_dir = index_dir.makeOpenPath("s", .{}) catch unreachable;
    // translation key index
    const tk_index_dir = index_dir.makeOpenPath("tk", .{}) catch unreachable;
    // parent section index
    const ps_index_dir = index_dir.makeOpenPath("ps", .{}) catch unreachable;

    collectGitInfo(project, index_dir, project.build_root.path.?);

    const assets_updater = zine_dep.artifact("update-assets");
    const update_assets = project.addRunArtifact(assets_updater);
    update_assets.addArg(project.install_path);
    step.dependOn(&update_assets.step);

    // const renderer = zine_dep.artifact("markdown-renderer");
    const layout = zine_dep.artifact("layout");
    switch (website) {
        .multilingual => |ml| {
            ensureDir(project, ml.layouts_dir_path);
            ensureDir(project, ml.assets_dir_path);
            ensureDir(project, ml.i18n_dir_path);

            const index_step = writeAssetIndex(
                project,
                zine_dep,
                index_dir_path,
                ml.build_assets,
            );

            const lv = writeLocales(project, ml);

            var ti = TranslationKeyIndex.init(project.allocator);
            const scanned_variants = project.allocator.alloc(
                ScannedVariant,
                ml.locales.len,
            ) catch unreachable;

            for (ml.locales, scanned_variants) |v, *sv| {
                const output_path_prefix = v.output_prefix_override orelse
                    v.code;
                const url_path_prefix = v.output_prefix_override orelse
                    if (v.host_url_override != null) "" else v.code;

                const i18n_file_path = join(project.allocator, &.{
                    ml.i18n_dir_path,
                    project.fmt("{s}.ziggy", .{v.code}),
                }) catch unreachable;

                installStaticAssets(
                    project,
                    step,
                    ml.assets_dir_path,
                    ml.static_assets,
                    ml.build_assets,
                    output_path_prefix,
                );

                sv.* = scanVariant(
                    project,
                    subpages_index_dir,
                    ps_index_dir,
                    v.code,
                    debug,
                    v.content_dir_path,
                    url_path_prefix,
                    include_drafts,
                );
                sv.output_path_prefix = output_path_prefix;
                sv.url_path_prefix = url_path_prefix;
                sv.i18n_file_path = i18n_file_path;

                if (sv.root_index) |*idx| indexTranslation(
                    project,
                    &ti,
                    v.code,
                    idx,
                );
                var it = sv.sections.constIterator(0);
                while (it.next()) |s| {
                    for (s.pages.items) |*p| {
                        indexTranslation(
                            project,
                            &ti,
                            v.code,
                            p,
                        );
                    }
                }
            }

            writeTranslationIndex(project, ti, tk_index_dir);

            for (ml.locales, scanned_variants) |v, sv| {
                const url_path_prefix = v.output_prefix_override orelse
                    if (v.host_url_override != null) "" else v.code;
                addAllSteps(
                    project,
                    step,
                    index_step,
                    // renderer,
                    layout,
                    v.site_title,
                    v.host_url_override orelse ml.host_url,
                    ml.layouts_dir_path,
                    ml.assets_dir_path,
                    v.content_dir_path,
                    sv.output_path_prefix,
                    sv.i18n_file_path,
                    sv.root_index,
                    sv.sections,
                    index_dir_path,
                    url_path_prefix,
                    update_assets,
                    v.name,
                    lv,
                );
            }
        },
        .site => |s| {
            ensureDir(project, s.layouts_dir_path);
            ensureDir(project, s.assets_dir_path);

            const index_step = writeAssetIndex(
                project,
                zine_dep,
                index_dir_path,
                s.build_assets,
            );

            installStaticAssets(
                project,
                step,
                s.assets_dir_path,
                s.static_assets,
                s.build_assets,
                s.output_path_prefix,
            );

            const sv = scanVariant(
                project,
                subpages_index_dir,
                ps_index_dir,
                null,
                debug,
                s.content_dir_path,
                s.output_path_prefix,
                include_drafts,
            );

            addAllSteps(
                project,
                step,
                index_step,
                // renderer,
                layout,
                s.title,
                s.host_url,
                s.layouts_dir_path,
                s.assets_dir_path,
                s.content_dir_path,
                s.output_path_prefix,
                null,
                sv.root_index,
                sv.sections,
                index_dir_path,
                s.url_path_prefix,
                update_assets,
                null,
                null,
            );
        },
    }
}

fn indexTranslation(
    project: *std.Build,
    tk_index: *TranslationKeyIndex,
    code: []const u8,
    p: *Section.Page,
) void {
    const tk = p.fm.translation_key orelse return;
    const gop = tk_index.getOrPut(tk) catch unreachable;

    if (!gop.found_existing) {
        gop.value_ptr.* = .{};
    }

    gop.value_ptr.append(project.allocator, .{
        .code = code,
        .md_rel_path = join(project.allocator, &.{
            p.content_sub_path,
            p.md_name,
        }) catch unreachable,
    }) catch unreachable;
}

/// Assets are indexed as a directory containing
/// one file per asset, where the filename matches
/// the asset name, and the contents contain the
/// final lazypath value.
/// Since we don't know LazyPath vales for generated
/// content at config time, we create a RunStep to do
/// that for us.
///
/// Since we're doing indexing work, this function will
/// create an index_step that markdown parsing steps can
/// syncronize over in order to wait running layouts until
/// all markdown files are done parsing.
///
/// This function is also in charge of installing static
/// assets (ie assets that get installed unconditionally).
fn writeAssetIndex(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    index_dir_path: []const u8,
    build_assets: []const zine.BuildAsset,
) *std.Build.Step {
    const name = "Zine Index Content";
    const index_step = project.step(name, "");
    _ = project.top_level_steps.orderedRemove(name);

    // do nothing if there are no assets to index
    if (build_assets.len == 0) return index_step;

    const indexer = zine_dep.artifact("index-assets");
    const run = project.addRunArtifact(indexer);

    run.addArg(join(project.allocator, &.{ index_dir_path, "a" }) catch unreachable);
    for (build_assets) |asset| {
        const msg =
            \\build.zig error: build asset '{s}': only LazyPaths from generated files (eg from a Run step) or from dependencies are allowed
            \\
            \\NOTE: see the official documentation about Zine's asset system
            \\      to learn how to use assets located in your file system.
            \\
            \\
        ;

        _ = msg;
        // switch (asset.lp) {
        //     .src_path, .cwd_relative => {
        //         std.debug.print(msg, .{asset.name});
        //         std.process.exit(1);
        //     },
        //     .generated, .dependency => {
        //         run.addArg(asset.name);
        //         run.addFileArg(asset.lp);
        //         run.addArg(asset.install_path orelse "null");
        //     },
        // }
        run.addArg(asset.name);
        run.addFileArg(asset.lp);
        run.addArg(asset.install_path orelse "null");
    }

    index_step.dependOn(&run.step);
    return index_step;
}

fn installStaticAssets(
    project: *std.Build,
    step: *std.Build.Step,
    assets_dir_path: []const u8,
    static_assets: []const []const u8,
    build_assets: []const zine.BuildAsset,
    output_path_prefix: []const u8,
) void {
    for (static_assets) |sa| {
        const install_path = if (output_path_prefix.len == 0)
            sa
        else
            join(project.allocator, &.{ output_path_prefix, sa }) catch unreachable;

        const install = project.addInstallFile(
            project.path(join(project.allocator, &.{ assets_dir_path, sa }) catch unreachable),
            install_path,
        );
        step.dependOn(&install.step);
    }

    for (build_assets) |asset| {
        if (!asset.install_always) continue;

        const rel_install_path = asset.install_path orelse {
            std.debug.print("build asset '{s}' is marked as `install_always` but it doesn't define an `install_path` in `build.zig`", .{
                asset.name,
            });
            std.process.exit(1);
        };
        const install_path = if (output_path_prefix.len == 0)
            rel_install_path
        else
            join(project.allocator, &.{ output_path_prefix, rel_install_path }) catch unreachable;

        const install = project.addInstallFile(asset.lp, install_path);
        step.dependOn(&install.step);
    }
}

fn writeLocales(
    project: *std.Build,
    website: zine.MultilingualSite,
) std.Build.LazyPath {
    var buf = std.ArrayList(u8).init(project.allocator);
    ziggy.stringify(website.locales, .{}, buf.writer()) catch unreachable;
    const write_file_step = project.addWriteFiles();
    return write_file_step.add("locales.ziggy", buf.items);
}

fn writeTranslationIndex(
    project: *std.Build,
    ti: TranslationKeyIndex,
    tk_index_dir: std.fs.Dir,
) void {
    var buf = std.ArrayList(u8).init(project.allocator);
    const w = buf.writer();
    for (ti.keys(), ti.values()) |k, entries| {
        const f = tk_index_dir.createFile(k, .{
            .exclusive = true,
        }) catch unreachable;
        defer f.close();

        for (entries.items) |cp| w.print("{s}\n{s}\n", .{
            cp.code,
            cp.md_rel_path,
        }) catch unreachable;

        f.writeAll(buf.items) catch unreachable;
        buf.clearRetainingCapacity();
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
    site_index_dir: std.fs.Dir,
    ps_index_dir: std.fs.Dir,
    locale_code: ?[]const u8,
    debug: bool,
    content_dir_path: []const u8,
    url_path_prefix: []const u8,
    include_drafts: bool,
) ScannedVariant {
    var t = std.time.Timer.start() catch unreachable;
    defer if (debug) std.debug.print(
        "Content scan took {}ms\n",
        .{t.read() / std.time.ns_per_ms},
    );

    const content_dir = project.build_root.handle.makeOpenPath(
        content_dir_path,
        .{ .iterate = true },
    ) catch |err| {
        std.debug.print("Unable to open the content directory: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const Entry = struct {
        dir: std.fs.Dir,
        path: []const u8,
        parent_section: *Section,
    };

    var sections: SectionList = .{};
    const root_section = sections.addOne(project.allocator) catch unreachable;
    root_section.* = .{ .content_sub_path = "" };

    log.debug("root section = {*}", .{root_section});

    var dir_stack = std.ArrayList(Entry).init(project.allocator);
    dir_stack.append(.{
        .dir = content_dir,
        .path = "",
        .parent_section = root_section,
    }) catch unreachable;

    var root_index: ?Section.Page = null;
    while (dir_stack.popOrNull()) |de| {
        var dir_entry = de;
        log.debug("scanning dir '{s}'", .{dir_entry.path});
        defer {
            var d = dir_entry.dir;
            d.close();
            log.debug("pop dir '{s}'", .{dir_entry.path});
        }

        if (dir_entry.dir.openFile("index.smd", .{})) |file| blk: {
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            const r = buf_reader.reader();
            const result = FrontParser.parse(project.allocator, r, "index.smd") catch @panic("TODO: report frontmatter parser error");

            const permalink = join(project.allocator, &.{ "/", url_path_prefix, dir_entry.path, "/" }) catch unreachable;

            const fm = switch (result) {
                .success => |s| s.header,
                .empty => {
                    std.debug.print("WARNING: ignoring empty file '{s}{s}'\n", .{
                        permalink, "index.smd",
                    });
                    break :blk;
                },
                .framing_error => |line| {
                    std.debug.print("ERROR: bad frontmatter framing in '{s}{s}' (line {})\n", .{
                        permalink, "index.smd", line,
                    });
                    std.process.exit(1);
                },
                .ziggy_error => |diag| {
                    std.debug.print("{s}{}", .{ permalink, diag });
                    std.process.exit(1);
                },
            };

            if (!include_drafts and fm.draft) break :blk;

            // This is false only for `/index.smd`.
            if (dir_entry.path.len > 0) {
                const content_sub_path = project.dupe(dir_entry.path);
                const new_section = sections.addOne(project.allocator) catch unreachable;
                new_section.* = .{ .content_sub_path = content_sub_path };
                dir_entry.parent_section.pages.append(project.allocator, .{
                    .content_sub_path = content_sub_path,
                    .md_name = "index.smd",
                    .fm = fm,
                    .subpages = new_section,
                }) catch unreachable;

                log.debug("file: index.md ({s}) old parent_section = {*} new subsection = {*}", .{
                    dir_entry.path,
                    dir_entry.parent_section,
                    new_section,
                });

                dir_entry.parent_section = new_section;
            } else {
                std.debug.assert(dir_entry.parent_section == root_section);
                root_index = .{
                    .content_sub_path = project.dupe(dir_entry.path),
                    .md_name = "index.smd",
                    .fm = fm,

                    .subpages = dir_entry.parent_section,
                };
                log.debug("root index file: parent_section = {*}", .{
                    root_section,
                });
            }

            if (fm.skip_subdirs) continue;
        } else |index_md_err| {
            if (index_md_err != error.FileNotFound) {
                std.debug.print(
                    "Unable to access `index.smd` in {s}\n",
                    .{content_dir_path},
                );
                std.process.exit(1);
            }
        }

        var it = dir_entry.dir.iterate();
        while (it.next() catch unreachable) |entry| {
            switch (entry.kind) {
                else => continue,
                .file, .sym_link => if (std.mem.endsWith(u8, entry.name, ".smd")) {
                    if (std.mem.eql(u8, entry.name, "index.smd")) continue;
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

                    const permalink = join(project.allocator, &.{
                        "/",
                        url_path_prefix,
                        dir_entry.path,
                        entry.name[0 .. entry.name.len - ".smd".len],
                    }) catch unreachable;

                    const result = FrontParser.parse(project.allocator, r, entry.name) catch @panic("TODO: report frontmatter parse error");
                    const fm = switch (result) {
                        .success => |s| s.header,
                        .empty => {
                            std.debug.print("WARNING: ignoring empty file '{s}.smd'\n", .{
                                permalink,
                            });
                            continue;
                        },
                        .framing_error => |line| {
                            std.debug.print("ERROR: bad frontmatter framing in '{s}.smd' (line {})\n", .{
                                permalink, line,
                            });
                            std.process.exit(1);
                        },
                        .ziggy_error => |diag| {
                            std.debug.print("{}", .{diag});
                            std.process.exit(1);
                        },
                    };

                    if (!include_drafts and fm.draft) continue;

                    dir_entry.parent_section.pages.append(project.allocator, .{
                        .content_sub_path = project.dupe(dir_entry.path),
                        .md_name = project.dupe(entry.name),
                        .fm = fm,
                    }) catch unreachable;

                    log.debug("file: '{s}' ({s}) parent_section = {*}", .{
                        entry.name, dir_entry.path, dir_entry.parent_section,
                    });
                },
                .directory => {
                    dir_stack.append(.{
                        .dir = dir_entry.dir.openDir(
                            entry.name,
                            .{ .iterate = true },
                        ) catch unreachable,
                        .path = join(project.allocator, &.{ dir_entry.path, entry.name }) catch unreachable,
                        .parent_section = dir_entry.parent_section,
                    }) catch unreachable;
                    log.debug("push dir '{s}' ({s}), section: {*}", .{
                        entry.name,
                        dir_entry.path,
                        dir_entry.parent_section,
                    });
                },
            }
        }
    }

    const subpages_variant_index_dir = if (locale_code) |lc|
        site_index_dir.makeOpenPath(
            lc,
            .{},
        ) catch unreachable
    else
        site_index_dir;
    var section_it = sections.iterator(0);
    while (section_it.next()) |s| {
        s.writeIndex(
            project,
            subpages_variant_index_dir,
            ps_index_dir,
            locale_code,
        );
        // for (s.pages.items) |*p| {
        //     p.writeMeta(project, index_dir);
        // }
    }

    return .{
        .sections = sections,
        .root_index = root_index,
    };
}

pub fn addAllSteps(
    project: *std.Build,
    step: *std.Build.Step,
    index_step: *std.Build.Step,
    // renderer: *std.Build.Step.Compile,
    layout: *std.Build.Step.Compile,
    site_title: []const u8,
    host_url: []const u8,
    layouts_dir_path: []const u8,
    assets_dir_path: []const u8,
    content_dir_path: []const u8,
    output_path_prefix: []const u8,
    i18n_file_path: ?[]const u8,
    root_index: ?Section.Page,
    sections: SectionList,
    index_dir_path: []const u8,
    url_path_prefix: []const u8,
    update_assets: *std.Build.Step.Run,
    name: ?[]const u8,
    locales: ?std.Build.LazyPath,
) void {
    if (root_index) |idx| {
        // const rendered = addMarkdownRenderStep(
        //     project,
        //     index_step,
        //     renderer,
        //     content_dir_path,
        //     "",
        //     "index.md",
        //     output_path_prefix,
        //     idx.fm._meta.permalink,
        // );
        addLayoutStep(
            project,
            step,
            index_step,
            layout,
            site_title,
            host_url,
            content_dir_path,
            layouts_dir_path,
            assets_dir_path,
            "",
            "index.smd",
            "index.html",
            idx.fm.layout,
            idx.fm.aliases,
            output_path_prefix,
            i18n_file_path,
            index_dir_path,
            url_path_prefix,
            null,
            null,
            update_assets,
            name,
            locales,
        );
        for (idx.fm.alternatives) |alt| {
            addLayoutStep(
                project,
                step,
                index_step,
                layout,
                site_title,
                host_url,
                content_dir_path,
                layouts_dir_path,
                assets_dir_path,
                idx.content_sub_path,
                idx.md_name,
                alt.output,
                alt.layout,
                &.{},
                output_path_prefix,
                i18n_file_path,
                index_dir_path,
                url_path_prefix,
                null,
                null,
                update_assets,
                name,
                locales,
            );
        }
    }

    var section_it = sections.constIterator(0);
    while (section_it.next()) |s| {
        for (s.pages.items, 0..) |p, idx| {
            const out_basename = p.md_name[0 .. p.md_name.len - ".smd".len];
            const out_path = if (std.mem.eql(u8, out_basename, "index"))
                join(project.allocator, &.{ p.content_sub_path, "index.html" }) catch unreachable
            else
                join(project.allocator, &.{ p.content_sub_path, out_basename, "index.html" }) catch unreachable;

            addLayoutStep(
                project,
                step,
                index_step,
                layout,
                site_title,
                host_url,
                content_dir_path,
                layouts_dir_path,
                assets_dir_path,
                p.content_sub_path,
                p.md_name,
                out_path,
                p.fm.layout,
                p.fm.aliases,
                output_path_prefix,
                i18n_file_path,
                index_dir_path,
                url_path_prefix,
                idx,
                s.content_sub_path,
                update_assets,
                name,
                locales,
            );
            for (p.fm.alternatives) |alt| {
                addLayoutStep(
                    project,
                    step,
                    index_step,
                    layout,
                    site_title,
                    host_url,
                    content_dir_path,
                    layouts_dir_path,
                    assets_dir_path,
                    p.content_sub_path,
                    p.md_name,
                    alt.output,
                    alt.layout,
                    &.{},
                    output_path_prefix,
                    i18n_file_path,
                    index_dir_path,
                    url_path_prefix,
                    idx,
                    s.content_sub_path,
                    update_assets,
                    name,
                    locales,
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
    index_step: *std.Build.Step,
    renderer: *std.Build.Step.Compile,
    content_dir_path: []const u8,
    content_sub_path: []const u8,
    md_basename: []const u8,
    output_path_prefix: []const u8,
    permalink: []const u8,
) RenderResult {
    const in_path = join(project.allocator & .{ content_dir_path, content_sub_path, md_basename }) catch unreachable;
    const out_basename = md_basename[0 .. md_basename.len - ".smd".len];

    const render_step = project.addRunArtifact(renderer);
    // assets_in_dir_path
    render_step.addDirectoryArg(project.path(join(project.allocator & .{ content_dir_path, content_sub_path }) catch unreachable));
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
        join(project.allocator, &.{ content_sub_path, out_basename }) catch unreachable;

    // install all referenced files as assets (only images are detected for now)
    const install_assets = project.addInstallDirectory(.{
        .source_dir = assets_dir,
        .install_dir = .prefix,
        .install_subdir = join(project.allocator, &.{ output_path_prefix, install_subpath }) catch unreachable,
        .exclude_extensions = &.{ "_zine_assets.d", "_zine_meta.ziggy", "_zine_rendered.html" },
    });

    index_step.dependOn(&install_assets.step);

    return .{
        .content = rendered_md,
        .meta = page_metadata,
    };
}

fn addLayoutStep(
    project: *std.Build,
    step: *std.Build.Step,
    index_step: *std.Build.Step,
    layout: *std.Build.Step.Compile,
    title: []const u8,
    host_url: []const u8,
    content_dir_path: []const u8,
    layouts_dir_path: []const u8,
    assets_dir_path: []const u8,
    content_sub_path: []const u8,
    md_basename: []const u8,
    out_path: []const u8,
    layout_name: []const u8,
    aliases: []const []const u8,
    output_path_prefix: []const u8,
    i18n_file_path: ?[]const u8,
    index_dir_path: []const u8,
    url_path_prefix: []const u8,
    index_in_section: ?usize,
    parent_section_path: ?[]const u8,
    update_assets: *std.Build.Step.Run,
    name: ?[]const u8,
    locales: ?std.Build.LazyPath,
) void {
    const layout_path = join(project.allocator, &.{ layouts_dir_path, layout_name }) catch unreachable;
    project.build_root.handle.access(layout_path, .{}) catch |err| {
        std.debug.print("Unable to find the layout '{s}' used by '{s}/{s}/{s}'\n. Please create it before running `zig build` again.\nError: {s}\n,", .{
            layout_path,
            content_dir_path,
            content_sub_path,
            md_basename,
            @errorName(err),
        });
        std.process.exit(1);
    };

    const md_name = if (content_sub_path.len == 0)
        md_basename
    else
        join(project.allocator, &.{ content_sub_path, md_basename }) catch unreachable;

    const layout_step = project.addRunArtifact(layout);
    // layouts start running after all content has been processed
    layout_step.step.dependOn(index_step);

    // #1
    const final_html = layout_step.addOutputFileArg(md_name);

    // #2
    layout_step.addArg(project.build_root.path orelse ".");

    // #3
    layout_step.addArg(url_path_prefix);

    // #4
    layout_step.addArg(md_name);

    // #5
    layout_step.addFileArg(project.path(layout_path));

    // #6
    layout_step.addArg(layout_name);

    // #7
    layout_step.addArg(join(project.allocator, &.{ layouts_dir_path, "templates" }) catch unreachable);

    // #8
    _ = layout_step.addDepFileOutputArg("templates.d");

    // #9
    layout_step.addArg(host_url);

    // #10
    layout_step.addArg(title);
    // // page assets dir path
    // layout_step.addDirectoryArg(project.path(project.pathJoin(&.{ content_dir_path, content_sub_path })));

    // if (prev) |p| layout_step.addFileArg(p) else layout_step.addArg("null");
    // if (next) |n| layout_step.addFileArg(n) else layout_step.addArg("null");
    // if (subpages) |s| layout_step.addFileArg(s) else layout_step.addArg("null");
    // #11
    if (i18n_file_path) |i|
        layout_step.addFileArg(project.path(i))
    else
        layout_step.addArg("null");

    // #12
    // TODO: remove me
    layout_step.addArg("null");

    // #13
    layout_step.addArg(index_dir_path);

    // #14
    layout_step.addArg(assets_dir_path);

    // #15
    layout_step.addArg(content_dir_path);

    // #16
    const md_path = join(project.allocator, &.{ content_dir_path, content_sub_path, md_basename }) catch unreachable;
    layout_step.addFileArg(project.path(md_path));

    // #1
    if (index_in_section) |idx|
        layout_step.addArg(project.fmt("{d}", .{idx}))
    else
        layout_step.addArg("null");

    // #18
    if (parent_section_path) |pp|
        layout_step.addArg(pp)
    else
        layout_step.addArg("null");

    const collected_assets = layout_step.addOutputFileArg("assets");
    update_assets.addFileArg(collected_assets);

    layout_step.addArg(output_path_prefix);
    layout_step.addArg(name orelse "null");

    if (locales) |v|
        layout_step.addFileArg(v)
    else
        layout_step.addArg("null");

    // ------------
    const target_output = project.addInstallFile(
        final_html,
        join(project.allocator, &.{ output_path_prefix, out_path }) catch unreachable,
    );
    step.dependOn(&target_output.step);

    for (aliases) |a| {
        const alias = project.addInstallFile(
            final_html,
            join(project.allocator, &.{ output_path_prefix, a }) catch unreachable,
        );
        step.dependOn(&alias.step);
    }
}

const Section = struct {
    content_sub_path: []const u8,
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

        pub fn lessThan(_: void, lhs: Page, rhs: Page) bool {
            return rhs.fm.date.lessThan(lhs.fm.date);
        }
    };

    pub fn writeIndex(
        s: *Section,
        project: *std.Build,
        site_index_dir: std.fs.Dir,
        ps_index_dir: std.fs.Dir,
        locale_code: ?[]const u8,
    ) void {
        std.mem.sort(Page, s.pages.items, {}, Page.lessThan);
        const in_subdir = s.content_sub_path.len != 0;
        var section_dir = if (in_subdir)
            site_index_dir.makeOpenPath(
                s.content_sub_path,
                .{},
            ) catch unreachable
        else
            site_index_dir;
        defer if (in_subdir) section_dir.close();

        // Section lists all the original markdown files
        // in the content dir. Sorting order is by date.
        var buf = std.ArrayList(u8).init(project.allocator);
        const w = buf.writer();
        defer buf.deinit();
        {
            defer buf.clearRetainingCapacity();
            const section_file = section_dir.createFile(
                "s",
                .{},
            ) catch unreachable;
            defer section_file.close();

            for (s.pages.items) |p| {
                w.print("{s}\n", .{
                    join(project.allocator, &.{ p.content_sub_path, p.md_name }) catch unreachable,
                }) catch unreachable;
            }
            section_file.writeAll(buf.items) catch unreachable;
        }

        // prev-next index
        {
            std.mem.reverse(Page, s.pages.items);
            for (s.pages.items, 0..) |p, idx| {
                defer buf.clearRetainingCapacity();

                const next = if (idx < s.pages.items.len - 1) join(project.allocator, &.{
                    s.pages.items[idx + 1].content_sub_path,
                    s.pages.items[idx + 1].md_name,
                }) catch unreachable else "";

                const current = join(project.allocator, &.{
                    p.content_sub_path,
                    p.md_name,
                }) catch unreachable;
                w.print("{s}\n{s}\n", .{ current, next }) catch unreachable;

                const page_file = section_dir.createFile(
                    project.fmt("{d}_{d}", .{ idx, idx + 1 }),
                    .{},
                ) catch unreachable;
                defer page_file.close();

                page_file.writeAll(buf.items) catch unreachable;
            }
        }

        // parent section index
        {
            var seen_paths = std.StringHashMap(void).init(project.allocator);
            for (s.pages.items) |p| {
                const gop = seen_paths.getOrPut(
                    p.content_sub_path,
                ) catch unreachable;
                if (!gop.found_existing) {
                    var hash = std.hash.Wyhash.init(1990);
                    if (locale_code) |lc| hash.update(lc);
                    if (std.mem.eql(u8, p.md_name, "index.smd")) {
                        hash.update(std.fs.path.dirname(p.content_sub_path) orelse "");
                    } else {
                        hash.update(p.content_sub_path);
                    }
                    const f = ps_index_dir.createFile(
                        project.fmt("{x}", .{hash.final()}),
                        .{},
                    ) catch unreachable;
                    f.writeAll(join(project.allocator, &.{
                        s.content_sub_path,
                        "s",
                    }) catch unreachable) catch unreachable;
                }
            }
        }
    }
};

pub fn ensureDir(project: *std.Build, path: []const u8) void {
    project.build_root.handle.makePath(path) catch |err| {
        std.debug.print("Error while creating '{s}': {s}\n", .{
            path, @errorName(err),
        });
        std.process.exit(1);
    };
}

const Git = @import("Git.zig");
fn collectGitInfo(project: *std.Build, dir: std.fs.Dir, path: []const u8) void {
    const g = Git.init(project.allocator, path) catch |err| {
        std.debug.print("error while collecting git info: {s}", .{
            @errorName(err),
        });
        std.process.exit(1);
    };

    const f = dir.createFile("git.ziggy", .{}) catch |err| {
        std.debug.print("error while creating .zig-cache/zine/git.ziggy: {s}", .{
            @errorName(err),
        });
        std.process.exit(1);
    };
    defer f.close();

    var buf = std.ArrayList(u8).init(project.allocator);
    ziggy.stringify(g, .{}, buf.writer()) catch unreachable;

    f.writeAll(buf.items) catch unreachable;
}
