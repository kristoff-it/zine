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
    const debug_opt = project.option(
        bool,
        "debug",
        "build Zine tools in debug mode",
    ) orelse false;

    const log: []const []const u8 = project.option(
        []const []const u8,
        "log",
        "logging scopes to enable (defaults to all scopes)",
    ) orelse &.{};

    const optimize: std.builtin.OptimizeMode = if (debug_opt) .Debug else .ReleaseFast;
    const zine_dep = project.dependency("zine", .{ .optimize = optimize, .log = log });

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
    run_server.addArg(project.graph.zig_exe);
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

pub fn scriptyReferenceDocs(project: *std.Build, output_file_path: []const u8) void {
    const zine_dep = project.dependency("zine", .{ .optimize = .Debug });

    const run_docgen = project.addRunArtifact(zine_dep.artifact("docgen"));
    const reference_md = run_docgen.addOutputFileArg("scripty_reference.md");

    const wf = project.addWriteFiles();
    wf.addCopyFileToSource(reference_md, output_file_path);

    const desc = project.fmt("Regenerates Scripty reference docs in '{s}'", .{output_file_path});
    const run_step = project.step("docgen", desc);
    run_step.dependOn(&wf.step);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const log: []const []const u8 = b.option(
        []const []const u8,
        "log",
        "logging scopes to enable (defaults to all scopes)",
    ) orelse &.{};

    const mode = .{ .target = target, .optimize = optimize };

    const options = blk: {
        const options = b.addOptions();
        const out = options.contents.writer();
        try out.writeAll(
            \\// module = zine
            \\const std = @import("std");
            \\pub const log_scope_levels: []const std.log.ScopeLevel = &.{
            \\
        );
        for (log) |l| try out.print(
            \\.{{.scope = .{s}, .level = .debug}},
        , std.zig.fmtId(l));
        try out.writeAll("};");
        break :blk options.createModule();
    };

    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = .{ .path = "zine/server/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .macos) {
        server.linkFramework("CoreServices");
    }

    const mime = b.dependency("mime", mode);
    const ws = b.dependency("ws", mode);

    server.root_module.addImport("options", options);
    server.root_module.addImport("mime", mime.module("mime"));
    server.root_module.addImport("ws", ws.module("websocket"));

    b.installArtifact(server);

    const super_exe = b.addExecutable(.{
        .name = "super_exe",
        .root_source_file = .{ .path = "zine/src/super.zig" },
        .target = target,
        .optimize = optimize,
        // .strip = true,
    });

    const super = b.dependency("super", mode);
    const scripty = super.builder.dependency("scripty", mode);
    const ts = super.builder.dependency("tree-sitter", mode);
    const datetime = b.dependency("datetime", mode);

    super_exe.root_module.addImport("options", options);
    super_exe.root_module.addImport("super", super.module("super"));
    super_exe.root_module.addImport("scripty", scripty.module("scripty"));
    super_exe.root_module.addImport("datetime", datetime.module("zig-datetime"));
    super_exe.linkLibrary(ts.artifact("tree-sitter"));
    super_exe.linkLibC();

    b.installArtifact(super_exe);

    const docgen = b.addExecutable(.{
        .name = "docgen",
        .root_source_file = .{ .path = "zine/src/docgen.zig" },
        .target = target,
        .optimize = .Debug,
    });
    docgen.root_module.addImport("datetime", datetime.module("zig-datetime"));
    b.installArtifact(docgen);

    const md_renderer = b.addExecutable(.{
        .name = "markdown-renderer",
        .root_source_file = .{ .path = "zine/src/markdown-renderer.zig" },
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });

    const gfm = b.dependency("gfm", mode);
    const frontmatter = b.dependency("frontmatter", mode);
    md_renderer.root_module.addImport("datetime", datetime.module("zig-datetime"));
    md_renderer.root_module.addImport("frontmatter", frontmatter.module("frontmatter"));

    md_renderer.linkLibrary(gfm.artifact("cmark-gfm"));
    md_renderer.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    md_renderer.linkLibC();

    b.installArtifact(md_renderer);
}
