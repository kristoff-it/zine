const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    const zine_dep = b.dependency("zine", .{});

    const zine_exe = zine_dep.artifact("zine");
    const run_server = b.addRunArtifact(zine_exe);
    run_server.addArgs(&.{ "serve", "--root", b.install_path });
    if (b.option(u16, "port", "port to listen on for the development server")) |port| {
        run_server.addArgs(&.{ "-p", b.fmt("{d}", .{port}) });
    }

    const run_step = b.step("serve", "Run the local development web server");
    run_step.dependOn(&run_server.step);
    run_server.step.dependOn(b.getInstallStep());

    try zine.addWebsite(b, .{
        .content_dir_path = "./content",
        .zine = zine_dep,
    });
}
