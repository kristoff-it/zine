const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("super", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{
                .name = "frontmatter",
                .module = b.dependency("frontmatter", .{}).module("frontmatter"),
            },
            .{
                .name = "scripty",
                .module = b.dependency("scripty", .{}).module("scripty"),
            },
        },
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        // .filter = "page.html",
    });

    const ts = b.dependency("tree-sitter", .{});
    unit_tests.linkLibrary(ts.artifact("tree-sitter"));
    unit_tests.linkLibC();
    // unit_tests.strip = true;

    unit_tests.addModule("super", module);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
