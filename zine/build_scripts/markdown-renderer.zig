const std = @import("std");

pub fn build(b: *std.Build) void {
    const gfm = b.dependency("gfm", .{});

    const exe = b.addExecutable(.{
        .name = "markdown-renderer",
        .root_source_file = .{ .path = "zine/src/markdown-renderer.zig" },
        .target = b.resolveTargetQuery(.{}),
    });

    exe.root_module.addImport("datetime", b.dependency("datetime", .{}).module("zig-datetime"));
    exe.root_module.addImport("frontmatter", b.dependency("frontmatter", .{}).module("frontmatter"));

    exe.linkLibrary(gfm.artifact("cmark-gfm"));
    exe.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
    });

    unit_tests.root_module.addImport("datetime", b.dependency("datetime", .{}).module("zig-datetime"));
    unit_tests.root_module.addImport("frontmatter", b.dependency("frontmatter", .{}).module("frontmatter"));

    unit_tests.linkLibrary(gfm.artifact("cmark-gfm"));
    unit_tests.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
