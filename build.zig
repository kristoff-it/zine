const std = @import("std");

pub const BuildAsset = struct {
    /// Name of this asset
    name: []const u8,
    /// LazyPath of the generated asset.
    ///
    /// The LazyPath cannot be generated by calling `b.path`.
    /// Use the 'assets' directory for non-buildtime assets.
    lp: std.Build.LazyPath,
    /// Installation path relative to the website's asset output path prefix.
    ///
    /// It is recommended to give the file an appropriate file extension.
    /// No need to specify this value if the asset is not meant to be
    /// `link()`ed
    install_path: ?[]const u8 = null,
    /// Installs the asset unconditionally when set to true.
    ///
    /// When set to false, the asset will be installed only if `link()`ed
    /// in a content file or layout (requires `install_path` to be set).
    ///
    /// Note that even when this property is set to false the asset will be
    /// generated by the Zig build system regardless.
    install_always: bool = false,
};

pub const Options = struct {
    /// The directory that contains 'zine.ziggy'.
    /// Defaults to the directory where your 'build.zig' lives.
    website_root: ?std.Build.LazyPath = null,

    /// Assets generated by the Zig build system to be made available to Zine.
    build_assets: []const BuildAsset = &.{},

    /// Path where to install the website, relative to the zig build install
    /// prefix.
    install_path: []const u8 = "",

    /// Whether Zine should be built from source or grabbed from the
    /// environment. In ephemeral environments like CI runners you might
    /// want to build from source only if you are also saving Zig's cache dirs.
    zine: union(enum) {
        /// Build Zine from source (the default).
        source,
        /// Get Zine from the environment. You can either specify a path
        /// to the executable or leave it null if you have 'zine' available
        /// in PATH.
        path: ?[]const u8,
    } = .source,

    /// Debug settings for Zine.
    debug: struct {
        /// The optimization level to use when building Zine.
        optimize: std.builtin.OptimizeMode = .ReleaseFast,

        /// Logging scopes to enable.
        scopes: []const []const u8 = &.{},
    } = .{},
};

/// Builds a Zine website.
pub fn website(project: *std.Build, opts: Options) *std.Build.Step.Run {
    const zine_dep = project.dependencyFromBuildZig(@This(), .{
        .optimize = opts.debug.optimize,
        .scope = opts.debug.scopes,
    });

    const run_zine = switch (opts.zine) {
        .source => project.addRunArtifact(zine_dep.artifact("zine")),
        .path => |path| project.addSystemCommand(&.{path orelse "zine"}),
    };
    run_zine.setCwd(opts.website_root orelse project.path("."));
    run_zine.addArg("release");

    const full_install_path = project.pathJoin(&.{
        project.install_prefix,
        opts.install_path,
    });
    run_zine.addArg(project.fmt("--install={s}", .{full_install_path}));

    for (opts.build_assets) |a| {
        run_zine.addArg(project.fmt("--build-asset={s}", .{a.name}));
        run_zine.addFileArg(a.lp);
        if (a.install_always) {
            const out_path = a.install_path orelse std.debug.panic(
                "Build assets '{s}' specifies install_always = true  " ++
                    "but defines no install path.",
                .{a.name},
            );
            run_zine.addArg(project.fmt("--output-always={s}", .{
                out_path,
            }));
        } else if (a.install_path) |ip| {
            run_zine.addArg(project.fmt("--output={s}", .{ip}));
        }
    }

    return run_zine;
}

/// Serves a Zine website via the Zine live server, allowing you to edit
/// the input files and obtaining instant rebuild and page reload.
/// Currently does not support `--watch` but will in the future.
///
/// Ignores `opts.install_path` as it keeps all generated files in memory.
pub fn serve(project: *std.Build, opts: Options) *std.Build.Step.Run {
    const zine_dep = project.dependencyFromBuildZig(@This(), .{
        .optimize = opts.debug.optimize,
        .scope = opts.debug.scopes,
    });

    const run_zine = project.addRunArtifact(zine_dep.artifact("zine"));
    run_zine.setCwd(opts.website_root orelse project.path("."));

    for (opts.build_assets) |a| {
        run_zine.addArg(project.fmt("--build-asset={s}", .{a.name}));
        run_zine.addFileArg(a.lp);
        if (a.install_always) {
            const out_path = a.install_path orelse std.debug.panic(
                "Build assets '{s}' specifies output_always = true  " ++
                    "but defines no install path.",
                .{a.name},
            );
            run_zine.addArg(project.fmt("--output-always={s}", .{
                out_path,
            }));
        } else if (a.install_path) |ip| {
            run_zine.addArg(project.fmt("--output={s}", .{ip}));
        }
    }

    return run_zine;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        // .preferred_optimize_mode = .ReleaseFast,
    });

    const version: Version = if (b.option(
        bool,
        "preview",
        "Make a preview release of Zine",
    ) orelse false) .{
        .tag = getVersion(b).commit,
    } else getVersion(b);

    const tsan = b.option(
        bool,
        "tsan",
        "enable thread sanitizer",
    ) orelse false;

    const enable_tracy = b.option(
        bool,
        "tracy",
        "Enable Tracy profiling",
    ) orelse false;

    const highlight = b.option(
        bool,
        "highlight",
        "Include treesitter grammars for build-time syntax highlighting (enabled by default). Disabling reduces executable size significantly.",
    ) orelse true;

    const tracy = b.dependency("tracy", .{ .enable = enable_tracy });

    const scopes: []const []const u8 = b.option(
        []const []const u8,
        "scope",
        "logging scopes to enable",
    ) orelse &.{};

    const mode = .{ .target = target, .optimize = optimize };

    const options = blk: {
        const options = b.addOptions();
        const out = options.contents.writer();
        try out.print(
            \\// module = zine
            \\const std = @import("std");
            \\pub const tsan = {};
            \\pub const enable_treesitter = {};
            \\pub const version = "{s}";
            \\pub const log_scope_levels: []const std.log.ScopeLevel = &.{{
            \\
        , .{ tsan, highlight, version.string() });

        for (scopes) |l| try out.print(
            \\.{{.scope = .{s}, .level = .debug}},
        , std.zig.fmtId(l));
        try out.writeAll("};");
        break :blk options.createModule();
    };

    const scripty = b.dependency("scripty", .{
        .target = target,
        .optimize = optimize,
        .tracy = enable_tracy,
    }).module("scripty");

    const superhtml = b.dependency("superhtml", .{
        .target = target,
        .optimize = optimize,
        .tracy = enable_tracy,
    }).module("superhtml");

    const ziggy = b.dependency("ziggy", mode).module("ziggy");
    const supermd = b.dependency("supermd", .{
        .target = target,
        .optimize = optimize,
        .tracy = enable_tracy,
    }).module("supermd");
    supermd.addImport("scripty", scripty);
    supermd.addImport("superhtml", superhtml);
    supermd.addImport("ziggy", ziggy);

    const zeit = b.dependency("zeit", mode).module("zeit");
    const syntax = b.dependency("flow_syntax", .{
        .target = target,
        .optimize = optimize,
    });
    const ts = syntax.builder.dependency("tree_sitter", mode);
    const treez = ts.module("treez");

    const mime = b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    });

    // const wuffs = b.dependency("wuffs", mode);

    const release = b.step("release", "Create release builds of Zine");
    if (version == .tag) {
        setupReleaseStep(b, release, version.string());
    } else {
        release.dependOn(
            &b.addFail("error: git tag missing, cannot make release builds").step,
        );
    }

    const shtml_docgen = b.addExecutable(.{
        .name = "shtml_docgen",
        .root_source_file = b.path("src/docgen.zig"),
        .target = target,
        .optimize = .Debug,
    });
    shtml_docgen.root_module.addImport("zeit", zeit);
    shtml_docgen.root_module.addImport("ziggy", ziggy);
    shtml_docgen.root_module.addImport("supermd", supermd);
    shtml_docgen.root_module.addImport("superhtml", superhtml);

    if (b.option(
        bool,
        "docgen",
        "enable building the SuperHTML docgen tool",
    ) orelse false) {
        b.installArtifact(shtml_docgen);
    }

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

        .sanitize_thread = tsan,
    });

    if (target.result.os.tag == .macos) {
        const frameworks = b.lazyDependency("frameworks", .{}) orelse return;
        zine_exe.addIncludePath(frameworks.path("include"));
        zine_exe.addFrameworkPath(frameworks.path("Frameworks"));
        zine_exe.addLibraryPath(frameworks.path("lib"));
        zine_exe.linkFramework("CoreServices");
    }

    // zine_exe.root_module.addImport("zine", zine);
    zine_exe.root_module.addImport("ziggy", ziggy);
    zine_exe.root_module.addImport("scripty", scripty);
    zine_exe.root_module.addImport("supermd", supermd);
    zine_exe.root_module.addImport("superhtml", superhtml);
    zine_exe.root_module.addImport("zeit", zeit);
    zine_exe.root_module.addImport("syntax", syntax.module("syntax"));
    zine_exe.root_module.addImport("treez", treez);
    zine_exe.root_module.addImport("options", options);
    zine_exe.root_module.addImport("tracy", tracy.module("tracy"));
    zine_exe.root_module.addImport("mime", mime.module("mime"));

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
    diff.addDirectoryArg(b.path("tests"));
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
            run_camera.addArg("debug");
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
            });

            const reset_snapshot = b.addRemoveDirTree(b.path(b.pathJoin(
                &.{ src_path, "snapshot" },
            )));

            const run_zine = b.addRunArtifact(zine_exe);
            run_zine.addArg("release");
            run_zine.addArg("--install=snapshot");
            run_zine.setCwd(b.path(src_path));
            run_zine.has_side_effects = true;
            run_zine.step.dependOn(&reset_snapshot.step);

            const stderr_out = run_zine.captureStdErr();
            const update_snap = b.addUpdateSourceFiles();
            update_snap.addCopyFileToSource(stderr_out, b.pathJoin(
                &.{ src_path, "snapshot.txt" },
            ));

            update_snap.step.dependOn(&run_zine.step);
            git_add.step.dependOn(&update_snap.step);
        }
    }
    // drafts on
    {
        const tests_dir = try b.build_root.handle.openDir("tests/drafts", .{
            .iterate = true,
        });

        var it = tests_dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (entry.name[0] == '.') continue;

            const src_path = b.pathJoin(&.{
                "tests/drafts",
                entry.name,
            });

            const reset_snapshot = b.addRemoveDirTree(b.path(b.pathJoin(
                &.{ src_path, "snapshot" },
            )));

            const run_zine = b.addRunArtifact(zine_exe);
            run_zine.addArg("release");
            run_zine.addArg("--drafts");
            run_zine.addArg("--install=snapshot");
            run_zine.setCwd(b.path(src_path));
            run_zine.has_side_effects = true;
            run_zine.step.dependOn(&reset_snapshot.step);

            const stderr_out = run_zine.captureStdErr();
            const update_snap = b.addUpdateSourceFiles();
            update_snap.addCopyFileToSource(stderr_out, b.pathJoin(
                &.{ src_path, "snapshot.txt" },
            ));

            update_snap.step.dependOn(&run_zine.step);
            git_add.step.dependOn(&update_snap.step);
        }
    }
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

fn setupReleaseStep(
    b: *std.Build,
    release_step: *std.Build.Step,
    version: []const u8,
) void {
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    std.fs.cwd().makePath(b.pathJoin(&.{
        b.install_prefix,
        "releases",
    })) catch unreachable;

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const optimize = .ReleaseFast;

        const tracy = b.dependency("tracy", .{ .enable = false });
        const scripty = b.dependency("scripty", .{
            .target = target,
            .optimize = optimize,
            .tracy = false,
        }).module("scripty");

        const superhtml = b.dependency("superhtml", .{
            .target = target,
            .optimize = optimize,
            .tracy = false,
        }).module("superhtml");

        const ziggy = b.dependency("ziggy", .{
            .target = target,
            .optimize = optimize,
        }).module("ziggy");

        const supermd = b.dependency("supermd", .{
            .target = target,
            .optimize = optimize,
            .tracy = false,
        }).module("supermd");
        supermd.addImport("scripty", scripty);
        supermd.addImport("superhtml", superhtml);
        supermd.addImport("ziggy", ziggy);

        const zeit = b.dependency("zeit", .{
            .target = target,
            .optimize = optimize,
        }).module("zeit");

        const syntax = b.dependency("flow_syntax", .{
            .target = target,
            .optimize = optimize,
        });

        const ts = syntax.builder.dependency("tree_sitter", .{
            .target = target,
            .optimize = optimize,
        });

        const treez = ts.module("treez");

        const mime = b.dependency("mime", .{
            .target = target,
            .optimize = optimize,
        });

        const options = blk: {
            const options = b.addOptions();
            const out = options.contents.writer();
            out.print(
                \\// module = zine
                \\const std = @import("std");
                \\pub const tsan = false;
                \\pub const enable_treesitter = true;
                \\pub const version = "{s}";
                \\pub const log_scope_levels: []const std.log.ScopeLevel = &.{{}};
                \\
            , .{version}) catch unreachable;
            break :blk options.createModule();
        };

        const zine_exe_release = b.addExecutable(.{
            .name = "zine",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        });

        zine_exe_release.root_module.addImport("options", options);
        zine_exe_release.root_module.addImport("ziggy", ziggy);
        zine_exe_release.root_module.addImport("scripty", scripty);
        zine_exe_release.root_module.addImport("supermd", supermd);
        zine_exe_release.root_module.addImport("superhtml", superhtml);
        zine_exe_release.root_module.addImport("zeit", zeit);
        zine_exe_release.root_module.addImport("syntax", syntax.module("syntax"));
        zine_exe_release.root_module.addImport("treez", treez);
        zine_exe_release.root_module.addImport("tracy", tracy.module("tracy"));
        zine_exe_release.root_module.addImport("mime", mime.module("mime"));

        if (target.result.os.tag == .macos) {
            const frameworks = b.lazyDependency("frameworks", .{
                .target = target,
                .optimize = optimize,
            }) orelse return;
            zine_exe_release.addIncludePath(frameworks.path("include"));
            zine_exe_release.addFrameworkPath(frameworks.path("Frameworks"));
            zine_exe_release.addLibraryPath(frameworks.path("lib"));
            zine_exe_release.linkFramework("CoreServices");
        }

        switch (t.os_tag.?) {
            .macos, .windows => {
                const archive_name = b.fmt("{s}.zip", .{
                    t.zigTriple(b.allocator) catch unreachable,
                });

                const zip = b.addSystemCommand(&.{
                    "zip",
                    "-9",
                    // "-dd",
                    "-q",
                    "-j",
                });
                const archive = zip.addOutputFileArg(archive_name);
                zip.addDirectoryArg(zine_exe_release.getEmittedBin());
                _ = zip.captureStdOut();

                release_step.dependOn(&b.addInstallFileWithDir(
                    archive,
                    .{ .custom = "releases" },
                    archive_name,
                ).step);
            },
            else => {
                const archive_name = b.fmt("{s}.tar.xz", .{
                    t.zigTriple(b.allocator) catch unreachable,
                });

                const tar = b.addSystemCommand(&.{
                    "tar",
                    "-cJf",
                });

                const archive = tar.addOutputFileArg(archive_name);
                tar.addArg("-C");

                tar.addDirectoryArg(zine_exe_release.getEmittedBinDirectory());
                tar.addArg("zine");
                _ = tar.captureStdOut();

                release_step.dependOn(&b.addInstallFileWithDir(
                    archive,
                    .{ .custom = "releases" },
                    archive_name,
                ).step);
            },
        }
    }
}

const Version = union(Kind) {
    tag: []const u8,
    commit: []const u8,
    // not in a git repo
    unknown,

    pub const Kind = enum { tag, commit, unknown };

    pub fn string(v: Version) []const u8 {
        return switch (v) {
            .tag, .commit => |tc| tc,
            .unknown => "unknown",
        };
    }
};
fn getVersion(b: *std.Build) Version {
    const git_path = b.findProgram(&.{"git"}, &.{}) catch return .unknown;
    var out: u8 = undefined;
    const git_describe = std.mem.trim(
        u8,
        b.runAllowFail(&[_][]const u8{
            git_path,            "-C",
            b.build_root.path.?, "describe",
            "--match",           "*.*.*",
            "--tags",
        }, &out, .Ignore) catch return .unknown,
        " \n\r",
    );

    return .{ .commit = git_describe };

    // switch (std.mem.count(u8, git_describe, "-")) {
    //     0, 1 => return .{ .tag = git_describe },
    //     2 => {
    //         // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
    //         var it = std.mem.splitScalar(u8, git_describe, '-');
    //         const tagged_ancestor = it.next() orelse unreachable;
    //         const commit_height = it.next() orelse unreachable;
    //         const commit_id = it.next() orelse unreachable;

    //         // Check that the commit hash is prefixed with a 'g'
    //         // (it's a Git convention)
    //         if (commit_id.len < 1 or commit_id[0] != 'g') {
    //             std.debug.panic("Unexpected `git describe` output: {s}\n", .{git_describe});
    //         }

    //         // The version is reformatted in accordance with
    //         // the https://semver.org specification.
    //         return .{
    //             .commit = b.fmt("{s}-dev.{s}+{s}", .{
    //                 tagged_ancestor,
    //                 commit_height,
    //                 commit_id[1..],
    //             }),
    //         };
    //     },
    //     3 => {
    //         // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
    //         var it = std.mem.splitScalar(u8, git_describe, '-');
    //         const tagged_ancestor = it.next() orelse unreachable;
    //         const commit_height = it.next() orelse unreachable;
    //         const commit_id = it.next() orelse unreachable;

    //         // Check that the commit hash is prefixed with a 'g'
    //         // (it's a Git convention)
    //         if (commit_id.len < 1 or commit_id[0] != 'g') {
    //             std.debug.panic("Unexpected `git describe` output: {s}\n", .{git_describe});
    //         }

    //         // The version is reformatted in accordance with
    //         // the https://semver.org specification.
    //         return .{
    //             .commit = b.fmt("{s}-dev.{s}+{s}", .{
    //                 tagged_ancestor,
    //                 commit_height,
    //                 commit_id[1..],
    //             }),
    //         };
    //     },
    // }
}
