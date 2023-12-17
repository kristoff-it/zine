const std = @import("std");
const frontmatter = @import("frontmatter");
const templating = @import("templating.zig");
const contexts = @import("contexts.zig");

pub fn scan(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    layout_dir_path: []const u8,
    content_dir_path: []const u8,
) !void {
    const content_dir = try std.fs.cwd().openDir(
        content_dir_path,
        .{ .iterate = true },
    );

    const Entry = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };

    var dir_stack = std.ArrayList(Entry).init(project.allocator);
    try dir_stack.append(.{
        .dir = content_dir,
        .path = "",
    });

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
                    "Error while parsing the frontmatter header of `index.md` in /{s}\n",
                    .{dir_entry.path},
                );
                return err;
            };

            if (!fm.draft) try addMarkdownRender(
                project,
                zine_dep,
                layout_dir_path,
                fm,
                content_dir_path,
                dir_entry.path,
                "index.md",
            );
        } else |index_md_err| {
            if (index_md_err != error.FileNotFound) {
                std.debug.print(
                    "Unable to access `index.md` in {s}\n",
                    .{content_dir_path},
                );
                return index_md_err;
            }

            var it = dir_entry.dir.iterate();
            while (try it.next()) |entry| {
                switch (entry.kind) {
                    else => continue,
                    .file => if (std.mem.endsWith(u8, entry.name, ".md")) {
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
                        if (!fm.draft) try addMarkdownRender(
                            project,
                            zine_dep,
                            layout_dir_path,
                            fm,
                            content_dir_path,
                            dir_entry.path,
                            try project.allocator.dupe(u8, entry.name),
                        );
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
    }
}

fn addMarkdownRender(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    layouts_dir_path: []const u8,
    fm: contexts.Page,
    content_dir_path: []const u8,
    /// Must be relative to `content_dir_path`
    path: []const u8,
    md_basename: []const u8,
) !void {
    const in_path = project.pathJoin(&.{ content_dir_path, path, md_basename });
    const layout_path = project.pathJoin(&.{ layouts_dir_path, fm.layout });
    const out_basename = md_basename[0 .. md_basename.len - 3];
    const out_path = if (std.mem.eql(u8, out_basename, "index"))
        project.pathJoin(&.{ path, "index.html" })
    else
        project.pathJoin(&.{ path, out_basename, "index.html" });

    const renderer = zine_dep.builder.dependency(
        "markdown-renderer",
        .{},
    ).artifact("markdown-renderer");

    const assets = project.addWriteFiles();

    const render_step = project.addRunArtifact(renderer);
    // assets_in_dir_path
    render_step.addDirectoryArg(.{ .path = project.pathJoin(&.{ content_dir_path, path }) });
    // assets_dep_path
    _ = render_step.addDepFileOutputArg("assets.d");
    // assets_out_dir_path
    render_step.addDirectoryArg(assets.getDirectory());
    // md_in_path
    render_step.addFileArg(.{ .path = in_path });
    // html_out_path
    const rendered_md = render_step.addOutputFileArg(out_basename);

    // install all non-markdown files as assets
    // const install_assets = project.addInstallDirectory(.{
    //     .source_dir = assets.getDirectory(),
    //     .install_dir = .prefix,
    //     .install_subdir = project.pathJoin(&.{ path, out_basename }),
    // });

    // project.getInstallStep().dependOn(&install_assets.step);

    const super_exe = zine_dep.artifact("super_exe");
    const layout_step = project.addRunArtifact(super_exe);
    const final_html = layout_step.addOutputFileArg(out_basename);
    layout_step.addArg(content_dir_path);
    layout_step.addFileArg(rendered_md);
    layout_step.addArg(project.pathJoin(&.{ path, md_basename }));
    layout_step.addFileArg(.{ .path = layout_path });
    layout_step.addArg(fm.layout);
    layout_step.addArg(project.pathJoin(&.{ layouts_dir_path, "templates" }));
    _ = layout_step.addDepFileOutputArg("templates.d");

    const target_output = project.addInstallFile(final_html, out_path);
    project.getInstallStep().dependOn(&target_output.step);
}
