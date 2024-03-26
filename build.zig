const std = @import("std");
const templating = @import("zine/templating.zig");
const content = @import("zine/content.zig");

pub const AddWebsiteOptions = union(enum) {
    multilingual: MultilingualSite,
    site: Site,
};

pub const MultilingualSite = struct {
    host_url: []const u8,
    layouts_dir_path: []const u8,
    static_dir_path: []const u8,
    i18n_dir_path: []const u8,
    variants: []const LocalizedVariant,

    pub const LocalizedVariant = struct {
        ///A language-NATION code, e.g. 'en-US'.
        locale_code: []const u8,
        ///Content dir for this localized variant.
        content_dir_path: []const u8,
        ///Site title for this localized variant.
        title: []const u8,
        ///Set to a non-null value when deploying this variant from a
        ///dedicated host (e.g. 'https://us.site.com', 'http://de.site.com').
        host_url_override: ?[]const u8 = null,
        /// |  output_ |     host_     |     resulting    |      output     |
        /// |  prefix_ |      url_     |        url       |       path      |
        /// | override |   override    |      prefix      |      prefix     |
        /// | -------- | ------------- | ---------------- | --------------- |
        /// |   null   |      null     | site.com/en-US/  | zig-out/en-US/  |
        /// |   null   | "us.site.com" | us.site.com/     | zig-out/en-US/  |
        /// |   "foo"  |      null     | site.com/foo/    | zig-out/foo/    |
        /// |   "foo"  | "us.site.com" | us.site.com/foo/ | zig-out/foo/    |
        /// |    ""    |      null     | site.com/        | zig-out/        |
        ///
        /// The last case is how you create a default localized variant.
        output_prefix_override: ?[]const u8 = null,
    };
};

pub const Site = struct {
    title: []const u8,
    host_url: []const u8,
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    static_dir_path: []const u8,
    output_prefix: []const u8 = "",
};

/// Adds a 'serve' step to the project's build and sets up the zine build pipeline.
pub fn addWebsite(project: *std.Build, opts: Site) !void {
    try addWebsiteImpl(project, .{ .site = opts });
}

/// Adds a 'serve' step to the project's build and sets up the zine build pipeline.
pub fn addMultilingualWebsite(project: *std.Build, opts: MultilingualSite) !void {
    try addWebsiteImpl(project, .{ .multilingual = opts });
}

fn addWebsiteImpl(project: *std.Build, opts: AddWebsiteOptions) !void {
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

    try content.scan(project, zine_dep, opts);
    setupDevelopmentServer(project, zine_dep, opts);

    // Install static files
    const static_dir_path = switch (opts) {
        .multilingual => |ml| ml.static_dir_path,
        .site => |s| s.static_dir_path,
    };
    const install_static = project.addInstallDirectory(.{
        .source_dir = .{ .path = static_dir_path },
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
    run_server.addArgs(&.{ "--root", project.install_path });

    switch (opts) {
        .multilingual => |ml| {
            run_server.addArgs(&.{ "--input-dir", ml.static_dir_path });
            run_server.addArgs(&.{ "--input-dir", ml.layouts_dir_path });
            for (ml.variants) |v| {
                if (v.host_url_override) |_| {
                    @panic("TODO: a variant specifies a dedicated host but multihost support for the dev server has not been implemented yet.");
                }
                run_server.addArgs(&.{ "--input-dir", v.content_dir_path });
            }
        },
        .site => |s| {
            run_server.addArgs(&.{ "--input-dir", s.static_dir_path });
            run_server.addArgs(&.{ "--input-dir", s.layouts_dir_path });
            run_server.addArgs(&.{ "--input-dir", s.content_dir_path });
        },
    }

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

    const layout = b.addExecutable(.{
        .name = "layout",
        .root_source_file = .{ .path = "zine/src/layout.zig" },
        .target = target,
        .optimize = optimize,
        // .strip = true,

    });

    const super = b.dependency("super", mode);
    const scripty = super.builder.dependency("scripty", mode);
    const ziggy = b.dependency("ziggy", mode);
    const zeit = b.dependency("zeit", mode);
    const syntax = b.dependency("syntax", mode);
    const ts = syntax.builder.dependency("tree-sitter", mode);

    layout.root_module.addImport("options", options);
    layout.root_module.addImport("super", super.module("super"));
    layout.root_module.addImport("scripty", scripty.module("scripty"));
    layout.root_module.addImport("ziggy", ziggy.module("ziggy"));
    layout.root_module.addImport("zeit", zeit.module("zeit"));
    layout.root_module.addImport("syntax", syntax.module("syntax"));
    layout.root_module.addImport("treez", ts.module("treez"));
    layout.linkLibrary(ts.artifact("tree-sitter"));
    layout.linkLibC();

    b.installArtifact(layout);

    const docgen = b.addExecutable(.{
        .name = "docgen",
        .root_source_file = .{ .path = "zine/src/docgen.zig" },
        .target = target,
        .optimize = .Debug,
    });
    docgen.root_module.addImport("zeit", zeit.module("zeit"));
    docgen.root_module.addImport("ziggy", ziggy.module("ziggy"));
    b.installArtifact(docgen);

    const md_renderer = b.addExecutable(.{
        .name = "markdown-renderer",
        .root_source_file = .{ .path = "zine/src/markdown-renderer.zig" },
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });

    const gfm = b.dependency("gfm", mode);

    md_renderer.root_module.addImport("ziggy", ziggy.module("ziggy"));
    md_renderer.root_module.addImport("zeit", zeit.module("zeit"));
    md_renderer.root_module.addImport("syntax", syntax.module("syntax"));
    md_renderer.root_module.addImport("treez", ts.module("treez"));

    md_renderer.linkLibrary(gfm.artifact("cmark-gfm"));
    md_renderer.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    md_renderer.linkLibC();

    b.installArtifact(md_renderer);
}
