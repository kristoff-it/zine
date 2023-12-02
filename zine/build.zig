const std = @import("std");
const frontmatter = @import("frontmatter");

pub const AddWebsiteOptions = struct {
    templates_dir_path: []const u8,
    content_dir_path: []const u8,
    zine: *std.Build.Dependency,
};

/// Adds a 'serve' step to the project's build and sets up the zine build pipeline.
pub fn addWebsite(project: *std.Build, opts: AddWebsiteOptions) !void {
    setupDevelopmentServer(project, opts.zine);
    // const templates = try scanTemplates(b, opts.zine, opts.templates_dir_path);
    try scanMarkdown(project, opts);
}

fn setupDevelopmentServer(project: *std.Build, zine_dep: *std.Build.Dependency) void {
    const zine_exe = zine_dep.artifact("zine");
    const run_server = project.addRunArtifact(zine_exe);
    run_server.addArgs(&.{ "serve", "--root", project.install_path });
    if (project.option(u16, "port", "port to listen on for the development server")) |port| {
        run_server.addArgs(&.{ "-p", project.fmt("{d}", .{port}) });
    }

    const run_step = project.step("serve", "Run the local development web server");
    run_step.dependOn(&run_server.step);
    run_server.step.dependOn(project.getInstallStep());
}

fn scanMarkdown(b: *std.Build, opts: AddWebsiteOptions) !void {
    const content_dir = try std.fs.cwd().openDir(
        opts.content_dir_path,
        .{ .iterate = true },
    );

    const Entry = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };

    var dir_stack = std.ArrayList(Entry).init(b.allocator);
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
            const fm = frontmatter.parse(r, b.allocator) catch |err| {
                std.debug.print(
                    "Error while parsing the frontmatter header of `index.md` in /{s}\n",
                    .{dir_entry.path},
                );
                return err;
            };

            if (!fm.draft) addMarkdownRender(
                b,
                opts.zine,
                opts.content_dir_path,
                dir_entry.path,
                "index.md",
            );
        } else |index_md_err| {
            if (index_md_err != error.FileNotFound) {
                std.debug.print(
                    "Unable to access `index.md` in {s}\n",
                    .{opts.content_dir_path},
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
                        const fm = frontmatter.parse(r, b.allocator) catch |err| {
                            std.debug.print(
                                "Error while parsing the frontmatter header of `{s}` in /{s}\n",
                                .{ entry.name, dir_entry.path },
                            );
                            return err;
                        };
                        if (!fm.draft) addMarkdownRender(
                            b,
                            opts.zine,
                            opts.content_dir_path,
                            dir_entry.path,
                            try b.allocator.dupe(u8, entry.name),
                        );
                    },
                    .directory => {
                        try dir_stack.append(.{
                            .dir = try dir_entry.dir.openDir(
                                entry.name,
                                .{ .iterate = true },
                            ),
                            .path = b.pathJoin(&.{ dir_entry.path, entry.name }),
                        });
                    },
                }
            }
        }
    }
}

fn addMarkdownRender(
    b: *std.Build,
    zine: *const std.Build.Dependency,
    content_dir_path: []const u8,
    /// Must be relative to `content_dir_root`
    path: []const u8,
    md_basename: []const u8,
) void {
    const in_path = b.pathJoin(&.{ content_dir_path, path, md_basename });
    const out_basename = md_basename[0 .. md_basename.len - 3];
    const out_path = b.pathJoin(&.{ path, out_basename, "index.html" });

    const render_step = b.addRunArtifact(zine.builder.dependency("markdown-renderer", .{}).artifact("markdown-renderer"));
    render_step.addFileArg(.{ .path = in_path });
    const out = render_step.addOutputFileArg(out_basename);
    const target_output = b.addInstallFile(out, out_path);
    b.getInstallStep().dependOn(&target_output.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("mime", b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    }).module("mime"));

    b.installArtifact(exe);
}
