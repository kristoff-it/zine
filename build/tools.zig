const std = @import("std");

const templating = @import("templating.zig");
const content = @import("content.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scopes: []const []const u8 = b.option(
        []const []const u8,
        "scope",
        "logging scopes to enable",
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
        for (scopes) |l| try out.print(
            \\.{{.scope = .{s}, .level = .debug}},
        , std.zig.fmtId(l));
        try out.writeAll("};");
        break :blk options.createModule();
    };

    const index_assets = b.addExecutable(.{
        .name = "index-assets",
        .root_source_file = b.path("src/exes/index-assets.zig"),
        .target = target,
        .optimize = optimize,
    });
    index_assets.root_module.addImport("options", options);
    b.installArtifact(index_assets);

    const update_assets = b.addExecutable(.{
        .name = "update-assets",
        .root_source_file = b.path("src/exes/update-assets.zig"),
        .target = target,
        .optimize = optimize,
    });
    update_assets.root_module.addImport("options", options);
    b.installArtifact(update_assets);

    // "BDFL version resolution" strategy
    const scripty = b.dependency("scripty", .{}).module("scripty");

    const superhtml = b.dependency("superhtml", mode).module("superhtml");
    superhtml.addImport("scripty", scripty);

    const ziggy = b.dependency("ziggy", mode).module("ziggy");
    const supermd = b.dependency("supermd", mode).module("supermd");
    supermd.addImport("scripty", scripty);
    supermd.addImport("superhtml", superhtml);
    supermd.addImport("ziggy", ziggy);

    const zeit = b.dependency("zeit", mode).module("zeit");
    const syntax = b.dependency("flow_syntax", mode);
    const ts = syntax.builder.dependency("tree_sitter", mode);
    const treez = ts.module("treez");
    const wuffs = b.dependency("wuffs", mode);

    const zine = b.addModule("zine", .{
        .root_source_file = b.path("src/root.zig"),
    });
    zine.addImport("ziggy", ziggy);
    zine.addImport("scripty", scripty);
    zine.addImport("supermd", supermd);
    zine.addImport("superhtml", superhtml);
    zine.addImport("zeit", zeit);
    zine.addImport("syntax", syntax.module("syntax"));
    zine.addImport("treez", treez);

    setupServer(b, options, target, optimize);

    const layout = b.addExecutable(.{
        .name = "layout",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/exes/layout.zig"),
            .target = target,
            .optimize = optimize,
            // .strip = true,
            // Workaround for https://github.com/ziglang/zig/issues/23052
            .sanitize_c = true,
        }),
    });

    layout.root_module.addImport("options", options);
    layout.root_module.addImport("zine", zine);
    layout.root_module.addImport("ziggy", ziggy);
    layout.root_module.addImport("scripty", scripty);
    layout.root_module.addImport("supermd", supermd);
    layout.root_module.addImport("superhtml", superhtml);
    layout.root_module.addImport("zeit", zeit);
    layout.root_module.addImport("syntax", syntax.module("syntax"));
    layout.root_module.addImport("treez", treez);
    layout.root_module.addImport("wuffs", wuffs.module("wuffs"));
    layout.linkLibrary(ts.artifact("tree-sitter"));

    b.installArtifact(layout);

    const shtml_docgen = b.addExecutable(.{
        .name = "shtml_docgen",
        .root_source_file = b.path("src/exes/docgen.zig"),
        .target = target,
        .optimize = .Debug,
    });
    shtml_docgen.root_module.addImport("zine", zine);
    shtml_docgen.root_module.addImport("zeit", zeit);
    shtml_docgen.root_module.addImport("ziggy", ziggy);
    b.installArtifact(shtml_docgen);

    if (b.option(
        bool,
        "fuzz",
        "enable building tooling for fuzz testing",
    ) orelse false) {
        setupFuzzing(b, target, optimize);
    }

    try setupSnapshotTesting(b, scopes);
}

fn setupSnapshotTesting(b: *std.Build, scopes: []const []const u8) !void {
    const test_step = b.step("test", "builds test websites under test/ and compares with golden snapshot");

    const diff = b.addSystemCommand(&.{
        "git",
        "diff",
        "--cached",
        "--exit-code",
    });

    diff.addDirectoryArg(b.path("tests/"));

    test_step.dependOn(&diff.step);

    // We need to stage all of tests/ in order for untracked files to show up in
    // the diff. It's also not a bad automatism since it avoids the problem of
    // forgetting to stage new snapshot files.
    const git_add = b.addSystemCommand(&.{ "git", "add", "tests/" });

    diff.step.dependOn(&git_add.step);

    const tests_dir = try b.build_root.handle.openDir("tests/", .{
        .iterate = true,
    });

    var it = tests_dir.iterateAssumeFirstIteration();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name[0] == '.') continue;

        const build_site = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "build",
            "-Ddebug",
            "-p",
            "../snapshot",
        });

        build_site.addArgs(scopes);

        build_site.setEnvironmentVariable("ZIG_LOCAL_CACHE_DIR", b.pathJoin(
            &.{ b.build_root.path.?, ".zig-cache" },
        ));

        build_site.setCwd(b.path(b.pathJoin(&.{
            "tests/",
            entry.name,
            "src",
        })));

        git_add.step.dependOn(&build_site.step);
    }
}

fn setupServer(
    b: *std.Build,
    options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = b.path("src/exes/server/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .macos) {
        server.linkFramework("CoreServices");
    }

    const mime = b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    });

    server.root_module.addImport("options", options);
    server.root_module.addImport("mime", mime.module("mime"));

    b.installArtifact(server);
}

fn setupFuzzing(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const afl = b.lazyImport(@This(), "afl_kit") orelse return;

    const scripty_afl_obj = b.addObject(.{
        .name = "scripty",
        .root_source_file = b.path("src/fuzz/scripty.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    scripty_afl_obj.root_module.stack_check = false;
    scripty_afl_obj.root_module.link_libc = true;

    const afl_exe = afl.addInstrumentedExe(b, target, optimize, scripty_afl_obj);
    b.getInstallStep().dependOn(&b.addInstallFile(afl_exe, "scripty-afl").step);
}
