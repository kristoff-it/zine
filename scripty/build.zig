const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const datetime = b.dependency("datetime", .{}).module("zig-datetime");

    const module = b.addModule("scripty", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{.{
            .name = "datetime",
            .module = datetime,
        }},
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // unit_tests.strip = true;

    unit_tests.addModule("scripty", module);
    unit_tests.addModule("datetime", datetime);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
