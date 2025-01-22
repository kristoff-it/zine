const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        // .preferred_optimize_mode = .ReleaseFast,
    });

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

    // "BDFL version resolution" strategy
    const scripty = b.dependency("scripty", .{}).module("scripty");

    const superhtml = b.dependency("superhtml", mode).module("superhtml");
    superhtml.addImport("scripty", scripty);

    const ziggy = b.dependency("ziggy", mode).module("ziggy");
    const supermd = b.dependency("supermd", .{
        .target = target,
        .optimize = optimize,
        // .@"sanitize-thread" = optimize == .Debug,
    }).module("supermd");
    supermd.addImport("scripty", scripty);
    supermd.addImport("superhtml", superhtml);
    supermd.addImport("ziggy", ziggy);

    const zeit = b.dependency("zeit", mode).module("zeit");
    const syntax = b.dependency("flow_syntax", mode);
    const ts = syntax.builder.dependency("tree_sitter", mode);
    const treez = ts.module("treez");
    // const wuffs = b.dependency("wuffs", mode);

    // const zine = b.addModule("zine", .{
    //     .root_source_file = b.path("src/main.zig"),
    // });
    // zine.addImport("ziggy", ziggy);
    // zine.addImport("scripty", scripty);
    // zine.addImport("supermd", supermd);
    // zine.addImport("superhtml", superhtml);
    // zine.addImport("zeit", zeit);
    // zine.addImport("syntax", syntax.module("syntax"));
    // zine.addImport("treez", treez);

    setupServer(b, options, target, optimize);

    // const shtml_docgen = b.addExecutable(.{
    //     .name = "shtml_docgen",
    //     .root_source_file = b.path("src/exes/docgen.zig"),
    //     .target = target,
    //     .optimize = .Debug,
    // });
    // shtml_docgen.root_module.addImport("zine", zine);
    // shtml_docgen.root_module.addImport("zeit", zeit);
    // shtml_docgen.root_module.addImport("ziggy", ziggy);
    // b.installArtifact(shtml_docgen);

    if (b.option(
        bool,
        "fuzz",
        "enable building tooling for fuzz testing",
    ) orelse false) {
        setupFuzzing(b, target, optimize);
    }

    // setup the Zine standalone executable
    const zine_exe = b.addExecutable(.{
        .name = "zine",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = b.option(
            bool,
            "single-threaded",
            "build Zine in single-threaded mode",
        ) orelse false,
    });

    // zine_exe.root_module.addImport("zine", zine);
    zine_exe.root_module.addImport("ziggy", ziggy);
    zine_exe.root_module.addImport("scripty", scripty);
    zine_exe.root_module.addImport("supermd", supermd);
    zine_exe.root_module.addImport("superhtml", superhtml);
    zine_exe.root_module.addImport("zeit", zeit);
    zine_exe.root_module.addImport("syntax", syntax.module("syntax"));
    zine_exe.root_module.addImport("treez", treez);
    zine_exe.root_module.addImport("options", options);

    const check = b.step("check", "check the standalone zine executable");
    check.dependOn(&zine_exe.step);
    b.installArtifact(zine_exe);

    const run_step = b.step("run", "run the standalone zine executable");
    const zine_run = b.addRunArtifact(zine_exe);
    zine_run.setCwd(b.path("standalone-test"));
    if (b.args) |args| zine_run.addArgs(args);
    run_step.dependOn(&zine_run.step);

    try setupSnapshotTesting(b, target, zine_exe);
}

fn setupSnapshotTesting(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    zine_exe: *std.Build.Step.Compile,
) !void {
    const test_step = b.step("test", "build snapshot tests and diff the results");

    const camera = b.addExecutable(.{
        .name = "camera",
        .root_source_file = b.path("build/camera.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const diff = b.addSystemCommand(&.{
        "git",
        "diff",
        "--cached",
        "--exit-code",
    });
    diff.addDirectoryArg(b.path("tests/"));
    diff.setName("git diff tests/");
    test_step.dependOn(&diff.step);

    // We need to stage all of tests/ in order for untracked files to show up in
    // the diff. It's also not a bad automatism since it avoids the problem of
    // forgetting to stage new snapshot files.
    const git_add = b.addSystemCommand(&.{ "git", "add" });
    git_add.addDirectoryArg(b.path("tests/"));
    git_add.setName("git add tests/");
    diff.step.dependOn(&git_add.step);

    // content scanning
    {
        const tests_dir = try b.build_root.handle.openDir("tests/content-scanning", .{
            .iterate = true,
        });

        var it = tests_dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (entry.name[0] == '.') continue;

            const path = b.pathJoin(&.{
                "tests/content-scanning",
                entry.name,
            });

            const run_camera = b.addRunArtifact(camera);
            run_camera.addArtifactArg(zine_exe);
            run_camera.addArg("tree");
            run_camera.setCwd(b.path(path));
            run_camera.has_side_effects = true;

            const out = run_camera.captureStdErr();

            const update_snap = b.addUpdateSourceFiles();
            update_snap.addCopyFileToSource(out, b.pathJoin(&.{ path, "snapshot.txt" }));

            update_snap.step.dependOn(&run_camera.step);
            git_add.step.dependOn(&update_snap.step);
        }
    }

    // rendering
    {
        const tests_dir = try b.build_root.handle.openDir("tests/rendering", .{
            .iterate = true,
        });

        var it = tests_dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (entry.name[0] == '.') continue;

            const src_path = b.pathJoin(&.{
                "tests/rendering",
                entry.name,
                "src",
            });
            const out_path = b.pathJoin(&.{ "..", "snapshot" });

            const run_zine = b.addRunArtifact(zine_exe);
            run_zine.addArg("release");
            run_zine.addArg("--output");
            run_zine.addArg(out_path);
            run_zine.setCwd(b.path(src_path));
            run_zine.has_side_effects = true;

            git_add.step.dependOn(&run_zine.step);
        }
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
