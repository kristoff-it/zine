const std = @import("std");
const ziggy = @import("ziggy");
const templating = @import("templating.zig");
const contexts = @import("src/contexts.zig");
const zine = @import("../build.zig");

const FrontParser = ziggy.frontmatter.Parser(contexts.Page);

pub fn scan(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    opts: zine.AddWebsiteOptions,
) !void {
    // var t = std.time.Timer.start() catch unreachable;
    // defer {
    //     std.debug.print("Scan took {}ms\n", .{t.read() / std.time.ns_per_ms});
    // }
    const content_dir = std.fs.cwd().openDir(
        opts.content_dir_path,
        .{ .iterate = true },
    ) catch |err| {
        std.debug.print("Unable to open the content directory, please create it before running `zig build`.\nError: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const Entry = struct {
        dir: std.fs.Dir,
        path: []const u8,
        parent_section: ?*Section,
    };

    var dir_stack = std.ArrayList(Entry).init(project.allocator);
    try dir_stack.append(.{
        .dir = content_dir,
        .path = "",
        .parent_section = null,
    });

    var sections: std.SegmentedList(Section, 1) = .{};
    const root_section = try sections.addOne(project.allocator);
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
            const result = try FrontParser.parse(project.allocator, r, "index.md");

            const permalink = project.pathJoin(&.{ "/", dir_entry.path, "/" });
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
                current_section = try sections.addOne(project.allocator);
                current_section.* = .{};
                try parent_section.pages.append(project.allocator, .{
                    .content_sub_path = content_sub_path,
                    .md_name = "index.md",
                    .fm = fm,
                    .subpages = current_section,
                });
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
                    .{opts.content_dir_path},
                );
                return index_md_err;
            }
        }

        var it = dir_entry.dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                else => continue,
                .file => if (std.mem.endsWith(u8, entry.name, ".md")) {
                    if (std.mem.eql(u8, entry.name, "index.md")) continue;
                    const file = dir_entry.dir.openFile(entry.name, .{}) catch |err| {
                        std.debug.print(
                            "Error while reading {s} in /{s}\n",
                            .{ entry.name, dir_entry.path },
                        );
                        return err;
                    };
                    defer file.close();

                    var buf_reader = std.io.bufferedReader(file.reader());
                    const r = buf_reader.reader();

                    const permalink = project.pathJoin(&.{ "/", dir_entry.path, entry.name[0 .. entry.name.len - 3] });
                    const result = try FrontParser.parse(project.allocator, r, entry.name);
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

                    try current_section.pages.append(project.allocator, .{
                        .content_sub_path = project.dupe(dir_entry.path),
                        .md_name = try project.allocator.dupe(u8, entry.name),
                        .fm = fm,
                    });
                },
                .directory => {
                    try dir_stack.append(.{
                        .dir = try dir_entry.dir.openDir(
                            entry.name,
                            .{ .iterate = true },
                        ),
                        .path = project.pathJoin(&.{ dir_entry.path, entry.name }),
                        .parent_section = current_section,
                    });
                },
            }
        }
    }

    var section_it = sections.iterator(0);
    while (section_it.next()) |s| {
        s.writeIndex(project);
        for (s.pages.items) |*p| {
            p.writeMeta(project);
        }
    }

    const renderer = zine_dep.artifact("markdown-renderer");
    const layout = zine_dep.artifact("layout");

    if (root_index) |idx| {
        const rendered = addMarkdownRenderStep(project, renderer, opts, "", "index.md");
        addLayoutStep(
            project,
            layout,
            opts,
            "",
            "index.md",
            "index.html",
            rendered.content,
            rendered.meta,
            idx.fm.layout,
            idx.fm.aliases,
            null,
            null,
            idx.subpages.?.index,
        );
        for (idx.fm.alternatives) |alt| {
            addLayoutStep(
                project,
                layout,
                opts,
                idx.content_sub_path,
                idx.md_name,
                alt.output,
                rendered.content,
                rendered.meta,
                alt.layout,
                &.{},
                null,
                null,
                idx.subpages.?.index,
            );
        }
    }

    section_it = sections.iterator(0);
    while (section_it.next()) |s| {
        for (s.pages.items, 0..) |p, idx| {
            const next = if (idx == 0) null else s.pages.items[idx - 1].meta;
            const prev = if (idx == s.pages.items.len - 1) null else s.pages.items[idx + 1].meta;
            const rendered = addMarkdownRenderStep(project, renderer, opts, p.content_sub_path, p.md_name);
            const sub_index = if (p.subpages) |subsection| subsection.index else null;

            const out_basename = p.md_name[0 .. p.md_name.len - 3];
            const out_path = if (std.mem.eql(u8, out_basename, "index"))
                project.pathJoin(&.{ p.content_sub_path, "index.html" })
            else
                project.pathJoin(&.{ p.content_sub_path, out_basename, "index.html" });

            addLayoutStep(
                project,
                layout,
                opts,
                p.content_sub_path,
                p.md_name,
                out_path,
                rendered.content,
                rendered.meta,
                p.fm.layout,
                p.fm.aliases,
                prev,
                next,
                sub_index,
            );
            for (p.fm.alternatives) |alt| {
                addLayoutStep(
                    project,
                    layout,
                    opts,
                    p.content_sub_path,
                    p.md_name,
                    alt.output,
                    rendered.content,
                    rendered.meta,
                    alt.layout,
                    &.{},
                    prev,
                    next,
                    sub_index,
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
    renderer: *std.Build.Step.Compile,
    opts: zine.AddWebsiteOptions,
    content_sub_path: []const u8,
    md_basename: []const u8,
) RenderResult {
    const in_path = project.pathJoin(&.{ opts.content_dir_path, content_sub_path, md_basename });
    const out_basename = md_basename[0 .. md_basename.len - 3];

    const render_step = project.addRunArtifact(renderer);
    // assets_in_dir_path
    render_step.addDirectoryArg(.{ .path = project.pathJoin(&.{ opts.content_dir_path, content_sub_path }) });
    // assets_dep_path
    _ = render_step.addDepFileOutputArg("_zine_assets.d");
    // assets_out_dir_path
    const assets_dir = render_step.addOutputFileArg("");
    // md_in_path
    render_step.addFileArg(.{ .path = in_path });
    // html_out_path
    const rendered_md = render_step.addOutputFileArg("_zine_rendered.html");
    // frontmatter + computed metadata
    const page_metadata = render_step.addOutputFileArg("_zine_meta.ziggy");

    const install_subpath = if (std.mem.eql(u8, out_basename, "index"))
        content_sub_path
    else
        project.pathJoin(&.{ content_sub_path, out_basename });

    // install all referenced files as assets (only images are detected for now)
    const install_assets = project.addInstallDirectory(.{
        .source_dir = assets_dir,
        .install_dir = .prefix,
        .install_subdir = install_subpath,
        .exclude_extensions = &.{ "_zine_assets.d", "_zine_meta.ziggy", "_zine_rendered.html" },
    });

    project.getInstallStep().dependOn(&install_assets.step);

    return .{
        .content = rendered_md,
        .meta = page_metadata,
    };
}

fn addLayoutStep(
    project: *std.Build,
    layout: *std.Build.Step.Compile,
    opts: zine.AddWebsiteOptions,
    content_sub_path: []const u8,
    md_basename: []const u8,
    out_path: []const u8,
    rendered_md: std.Build.LazyPath,
    meta: std.Build.LazyPath,
    layout_name: []const u8,
    aliases: []const []const u8,
    prev: ?std.Build.LazyPath,
    next: ?std.Build.LazyPath,
    subpages: ?std.Build.LazyPath,
) void {
    const layout_path = project.pathJoin(&.{ opts.layouts_dir_path, layout_name });
    std.fs.cwd().access(layout_path, .{}) catch |err| {
        std.debug.print("Unable to find the layout '{s}' used by '{s}/{s}/{s}'\n. Please create it before running `zig build` again.\nError: {s}\n,", .{
            layout_path,
            opts.content_dir_path,
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
    layout_step.addFileArg(.{ .path = layout_path });
    // layout_name
    layout_step.addArg(layout_name);
    // templates_dir_path
    layout_step.addArg(project.pathJoin(&.{ opts.layouts_dir_path, "templates" }));
    // dep file
    _ = layout_step.addDepFileOutputArg("templates.d");
    // site base url
    layout_step.addArg(opts.site.base_url);
    // site title
    layout_step.addArg(opts.site.title);

    if (prev) |p| layout_step.addFileArg(p) else layout_step.addArg("null");
    if (next) |n| layout_step.addFileArg(n) else layout_step.addArg("null");
    if (subpages) |s| layout_step.addFileArg(s) else layout_step.addArg("null");

    const target_output = project.addInstallFile(final_html, out_path);
    project.getInstallStep().dependOn(&target_output.step);

    for (aliases) |a| {
        const alias = project.addInstallFile(final_html, a);
        project.getInstallStep().dependOn(&alias.step);
    }
}

const Section = struct {
    pages: std.ArrayListUnmanaged(Page) = .{},

    // Not used while iterating directories
    index: std.Build.LazyPath = undefined,

    const Page = struct {
        content_sub_path: []const u8,
        md_name: []const u8,
        fm: contexts.Page,

        // Present if this page is an 'index.md' and set
        // to the section defined by this page.
        subpages: ?*Section = null,

        // Not used while iterating directories
        meta: std.Build.LazyPath = undefined,

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

        pub fn writeMeta(p: *Page, project: *std.Build) void {
            var buf = std.ArrayList(u8).init(project.allocator);
            ziggy.stringify(p.fm, .{}, buf.writer()) catch unreachable;
            const write_file_step = project.addWriteFiles();
            p.meta = write_file_step.add("page_meta.ziggy", buf.items);
        }
    };

    pub fn writeIndex(s: *Section, project: *std.Build) void {
        std.mem.sort(Page, s.pages.items, {}, Page.lessThan);
        var buf = std.ArrayList(u8).init(project.allocator);
        ziggy.stringify(s.pages.items, .{}, buf.writer()) catch unreachable;
        const write_file_step = project.addWriteFiles();
        s.index = write_file_step.add("section.ziggy", buf.items);
    }
};
