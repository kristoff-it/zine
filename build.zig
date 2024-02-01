const std = @import("std");
const templating = @import("zine/templating.zig");
const markdown = @import("zine/markdown.zig");

pub const AddWebsiteOptions = struct {
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    static_dir_path: []const u8,
    site: Site,
};

pub const Site = struct {
    base_url: []const u8,
    title: []const u8,
};

/// Adds a 'serve' step to the project's build and sets up the zine build pipeline.
pub fn addWebsite(project: *std.Build, opts: AddWebsiteOptions) !void {
    const zine_dep = project.dependency("zine", .{});
    setupDevelopmentServer(project, zine_dep, opts);
    // const layouts = try templating.scan(project, zine_dep, opts.layouts_dir_path);

    try markdown.scan(project, zine_dep, opts);

    // Install static files
    const install_static = project.addInstallDirectory(.{
        .source_dir = .{ .path = opts.static_dir_path },
        .install_dir = .prefix,
        .install_subdir = "",
    });
    project.getInstallStep().dependOn(&install_static.step);
}

fn setupDevelopmentServer(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    opts: AddWebsiteOptions,
) void {
    const server_exe = zine_dep.artifact("server");
    const run_server = project.addRunArtifact(server_exe);
    run_server.addArg("serve");
    run_server.addArgs(&.{
        "--root",      project.install_path,
        "--input-dir", opts.content_dir_path,
        "--input-dir", opts.layouts_dir_path,
        "--input-dir", opts.static_dir_path,
    });

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

    // Define markdown-renderer executable
    @import("zine/build_scripts/markdown-renderer.zig").build(b);

    const exe = b.addExecutable(.{
        .name = "server",
        .root_source_file = .{ .path = "zine/server/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .macos) {
        exe.linkFramework("CoreServices");
    }

    exe.root_module.addImport("mime", b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    }).module("mime"));

    exe.root_module.addImport("ws", b.dependency("ws", .{
        .target = target,
        .optimize = optimize,
    }).module("websocket"));

    b.installArtifact(exe);

    const super_exe = b.addExecutable(.{
        .name = "super_exe",
        .root_source_file = .{ .path = "zine/src/super.zig" },
        .target = target,
        .optimize = optimize,
        // .strip = true,
    });

    super_exe.root_module.addImport("super", b.dependency("super", .{
        .target = target,
        .optimize = optimize,
    }).module("super"));

    super_exe.root_module.addImport("scripty", b.dependency("super", .{
        .target = target,
        .optimize = optimize,
    }).builder.dependency("scripty", .{}).module("scripty"));

    super_exe.root_module.addImport("datetime", b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    }).module("zig-datetime"));

    b.installArtifact(super_exe);

    const ts = b.dependency("super", .{}).builder.dependency("tree-sitter", .{});
    super_exe.linkLibrary(ts.artifact("tree-sitter"));
    super_exe.linkLibC();
}
