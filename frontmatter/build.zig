const std = @import("std");
pub usingnamespace @import("frontmatter.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const frontmatter = b.addModule("frontmatter", .{
        .root_source_file = b.path("frontmatter.zig"),
    });

    const ziggy = b.dependency("ziggy", .{ .target = target, .optimize = optimize });
    frontmatter.addImport("ziggy", ziggy.module("ziggy"));

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("frontmatter", frontmatter);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
