const std = @import("std");
const templating = @import("templating.zig");
const markdown = @import("markdown.zig");

pub const AddWebsiteOptions = struct {
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    static_dir_path: []const u8,
};

/// Adds a 'serve' step to the project's build and sets up the zine build pipeline.
pub fn addWebsite(project: *std.Build, opts: AddWebsiteOptions) !void {
    const zine_dep = project.dependency("zine", .{});
    setupDevelopmentServer(project, zine_dep);
    // const layouts = try templating.scan(project, zine_dep, opts.layouts_dir_path);

    try markdown.scan(
        project,
        zine_dep,
        opts.layouts_dir_path,
        opts.content_dir_path,
    );

    // Install static files
    const install_static = project.addInstallDirectory(.{
        .source_dir = .{ .path = opts.static_dir_path },
        .install_dir = .prefix,
        .install_subdir = "",
    });

    // Install images from the content directory
    // TODO: re-enable the more fine-grained asset collection approach

    const install_assets = project.addInstallDirectory(.{
        .source_dir = .{ .path = opts.content_dir_path },
        .install_dir = .prefix,
        .install_subdir = "",
        .include_extensions = &.{ "png", "jpg", "jpeg", "webp", "webm", "gif" },
    });

    project.getInstallStep().dependOn(&install_assets.step);
    project.getInstallStep().dependOn(&install_static.step);
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zine",
        .root_source_file = .{ .path = "server/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("mime", b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    }).module("mime"));

    b.installArtifact(exe);

    const super_exe = b.addExecutable(.{
        .name = "super_exe",
        .root_source_file = .{ .path = "super.zig" },
        .target = target,
        .optimize = optimize,
    });
    super_exe.strip = true;

    super_exe.addModule("super", b.dependency("super", .{
        .target = target,
        .optimize = optimize,
    }).module("super"));

    super_exe.addModule("scripty", b.dependency("super", .{
        .target = target,
        .optimize = optimize,
    }).builder.dependency("scripty", .{}).module("scripty"));

    b.installArtifact(super_exe);

    const ts = b.dependency("super", .{}).builder.dependency("tree-sitter", .{});
    super_exe.linkLibrary(ts.artifact("tree-sitter"));
    super_exe.linkLibC();
}
