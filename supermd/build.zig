const std = @import("std");
pub const Ast = struct {};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gfm = b.dependency("gfm", .{});
    const supermd = b.addModule("supermd", .{
        .root_source_file = b.path("src/root.zig"),
        .link_libc = true,
    });
    // super.addImport("scripty", scripty.module("scripty"));
    supermd.linkLibrary(gfm.artifact("cmark-gfm"));
    supermd.linkLibrary(gfm.artifact("cmark-gfm-extensions"));

    // const ziggy = b.dependency("ziggy", .{ .target = target, .optimize = optimize });
    // supermd.addImport("ziggy", ziggy.module("ziggy"));

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scripty = b.dependency("scripty", .{});
    unit_tests.root_module.addImport("scripty", scripty.module("scripty"));
    unit_tests.root_module.linkLibrary(gfm.artifact("cmark-gfm"));
    unit_tests.root_module.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const check_step = b.step("check", "Check the project");
    check_step.dependOn(&run_unit_tests.step);
}
