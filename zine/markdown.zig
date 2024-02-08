const std = @import("std");
const frontmatter = @import("frontmatter");
const templating = @import("templating.zig");
const contexts = @import("src/contexts.zig");
const zine = @import("../build.zig");

const MdIndexEntry = struct {
    content_sub_path: []const u8,
    md_name: []const u8,
    fm: contexts.Page,

    pub fn lessThan(_: void, lhs: MdIndexEntry, rhs: MdIndexEntry) bool {
        return lhs.fm.date.lessThan(rhs.fm.date);
    }
};

pub fn scan(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    opts: zine.AddWebsiteOptions,
) !void {
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
    };

    var dir_stack = std.ArrayList(Entry).init(project.allocator);
    try dir_stack.append(.{
        .dir = content_dir,
        .path = "",
    });

    var md_index = std.ArrayList(MdIndexEntry).init(project.allocator);
    while (dir_stack.popOrNull()) |dir_entry| {
        defer {
            var d = dir_entry.dir;
            d.close();
        }

        if (dir_entry.dir.openFile("index.md", .{})) |file| {
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            const r = buf_reader.reader();
            const fm = frontmatter.parse(contexts.Page, r, project.allocator) catch |err| {
                std.debug.print(
                    "Error while parsing the frontmatter header of '{s}/{s}/index.md'\n",
                    .{ opts.content_dir_path, dir_entry.path },
                );
                return err;
            };

            if (!fm.draft) {
                try md_index.append(.{
                    .content_sub_path = project.dupe(dir_entry.path),
                    .md_name = "index.md",
                    .fm = fm,
                });

                if (fm.skip_subdirs) continue;
            }
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
                    const fm = frontmatter.parse(contexts.Page, r, project.allocator) catch |err| {
                        std.debug.print(
                            "Error while parsing the frontmatter header of `{s}` in /{s}\n",
                            .{ entry.name, dir_entry.path },
                        );
                        return err;
                    };
                    if (!fm.draft) {
                        try md_index.append(.{
                            .content_sub_path = project.dupe(dir_entry.path),
                            .md_name = try project.allocator.dupe(u8, entry.name),
                            .fm = fm,
                        });
                    }
                },
                .directory => {
                    try dir_stack.append(.{
                        .dir = try dir_entry.dir.openDir(
                            entry.name,
                            .{ .iterate = true },
                        ),
                        .path = project.pathJoin(&.{ dir_entry.path, entry.name }),
                    });
                },
            }
        }
    }

    const sections = project.addWriteFiles();
    std.mem.sort(MdIndexEntry, md_index.items, {}, MdIndexEntry.lessThan);
    const index = sections.add("__zine-index__.json", formatIndex(
        project,
        md_index.items,
    ));
    for (md_index.items) |md| try addMarkdownRender(
        project,
        zine_dep,
        sections,
        opts.site.base_url,
        opts.site.title,
        opts.layouts_dir_path,
        md.fm.layout,
        opts.content_dir_path,
        md.fm.aliases,
        md.content_sub_path,
        md.md_name,
        index,
    );
}

fn addMarkdownRender(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    sections: *std.Build.Step.WriteFile,
    site_base_url: []const u8,
    site_title: []const u8,
    layouts_dir_path: []const u8,
    layout_name: []const u8,
    content_dir_path: []const u8,
    aliases: []const []const u8,
    /// Must be relative to `content_dir_path`
    path: []const u8,
    md_basename: []const u8,
    index: std.Build.LazyPath,
) !void {
    const in_path = project.pathJoin(&.{ content_dir_path, path, md_basename });
    const layout_path = project.pathJoin(&.{ layouts_dir_path, layout_name });
    const out_basename = md_basename[0 .. md_basename.len - 3];
    const out_name = if (std.mem.endsWith(u8, layout_name, ".xml")) "index.xml" else "index.html";
    const out_path = if (std.mem.eql(u8, out_basename, "index"))
        project.pathJoin(&.{ path, out_name })
    else
        project.pathJoin(&.{ path, out_basename, out_name });

    const renderer = zine_dep.artifact("markdown-renderer");
    const render_step = project.addRunArtifact(renderer);
    // assets_in_dir_path
    render_step.addDirectoryArg(.{ .path = project.pathJoin(&.{ content_dir_path, path }) });
    // assets_dep_path
    _ = render_step.addDepFileOutputArg("_zine_assets.d");
    // assets_out_dir_path
    const assets_dir = render_step.addOutputFileArg("");
    // md_in_path
    render_step.addFileArg(.{ .path = in_path });
    // html_out_path
    const rendered_md = render_step.addOutputFileArg(out_basename);
    // frontmatter + computed metadata
    const page_metadata = render_step.addOutputFileArg("_zine_page.json");

    const install_subpath = if (std.mem.eql(u8, out_basename, "index"))
        path
    else
        project.pathJoin(&.{ path, out_basename });

    // collectd metadata
    _ = sections.addCopyFile(page_metadata, project.pathJoin(
        &.{ install_subpath, "_zine_page.json" },
    ));

    // install all referenced files as assets (only images are detected for now)
    const install_assets = project.addInstallDirectory(.{
        .source_dir = assets_dir,
        .install_dir = .prefix,
        .install_subdir = install_subpath,
        .exclude_extensions = &.{ "_zine_assets.d", "_zine_index.html", "_zine_page.json", "index" },
    });
    project.getInstallStep().dependOn(&install_assets.step);

    std.fs.cwd().access(layout_path, .{}) catch |err| {
        std.debug.print("Unable to find the layout '{s}' used by '{s}/{s}/{s}'\n. Please create it before running `zig build` again.\nError: {s}\n,", .{
            layout_path,
            content_dir_path,
            path,
            md_basename,
            @errorName(err),
        });
        std.process.exit(1);
    };

    const super_exe = zine_dep.artifact("super_exe");
    const layout_step = project.addRunArtifact(super_exe);
    // output file
    const final_html = layout_step.addOutputFileArg(out_basename);
    // install subpath (used also to navigate sections_meta)
    layout_step.addArg(install_subpath);
    // rendered_md_path
    layout_step.addFileArg(rendered_md);
    // md_name
    layout_step.addArg(project.pathJoin(&.{ path, md_basename }));
    // location where the sections metadata lives
    layout_step.addDirectoryArg(sections.getDirectory());
    // layout_path
    layout_step.addFileArg(.{ .path = layout_path });
    // layout_name
    layout_step.addArg(layout_name);
    // templates_dir_path
    layout_step.addArg(project.pathJoin(&.{ layouts_dir_path, "templates" }));
    // dep file
    _ = layout_step.addDepFileOutputArg("templates.d");
    // post index
    layout_step.addFileArg(index);
    // site base url
    layout_step.addArg(site_base_url);
    // site title
    layout_step.addArg(site_title);

    const target_output = project.addInstallFile(final_html, out_path);
    project.getInstallStep().dependOn(&target_output.step);

    for (aliases) |a| {
        const alias = project.addInstallFile(final_html, a);
        project.getInstallStep().dependOn(&alias.step);
    }
}

fn formatIndex(project: *std.Build, md_index: []const MdIndexEntry) []const u8 {
    var out = std.ArrayList(u8).init(project.allocator);
    const w = out.writer();
    for (md_index) |md| {
        if (std.mem.eql(u8, md.md_name, "index.md")) {
            w.print("{s}\n", .{md.content_sub_path}) catch unreachable;
        } else {
            w.print("{s}{s}\n", .{
                md.content_sub_path,
                md.md_name[md.md_name.len - 4 ..],
            }) catch unreachable;
        }
    }
    return out.toOwnedSlice() catch unreachable;
}
