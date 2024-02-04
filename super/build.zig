const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mode = .{ .target = target, .optimize = optimize };

    const frontmatter = b.dependency("frontmatter", mode);
    const scripty = b.dependency("scripty", mode);
    const ts = b.dependency("tree-sitter", mode);

    const super = b.addModule("super", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .link_libc = true,
    });

    super.addImport("frontmatter", frontmatter.module("frontmatter"));
    super.addImport("scripty", scripty.module("scripty"));
    super.linkLibrary(ts.artifact("tree-sitter"));

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = .Debug,
        // .strip = true,
        // .filter = "page.html",
    });

    unit_tests.linkLibrary(ts.artifact("tree-sitter"));
    unit_tests.linkLibC();
    unit_tests.root_module.addImport("super", super);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
