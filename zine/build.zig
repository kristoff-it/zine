const std = @import("std");

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

pub const AddWebsiteOptions = struct {
    content_dir_path: []const u8,
    zine: *const std.Build.Dependency,
};

pub fn addWebsite(b: *std.Build, opts: AddWebsiteOptions) !void {
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

        if (dir_entry.dir.access("index.md", .{})) |_| {
            // if 'index.md' is present,
            addMarkdownRender(
                b,
                opts.zine,
                opts.content_dir_path,
                dir_entry.path,
                "index.md",
            );
        } else |err| {
            if (err != error.FileNotFound) {
                std.debug.print(
                    "Unable to access `index.md` in {s}\n",
                    .{opts.content_dir_path},
                );
                return err;
            }

            var it = dir_entry.dir.iterate();
            while (try it.next()) |entry| {
                switch (entry.kind) {
                    else => continue,
                    .file => if (std.mem.endsWith(u8, entry.name, ".md")) {
                        addMarkdownRender(
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
