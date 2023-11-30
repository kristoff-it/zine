const std = @import("std");
const zashi = @import("zashi");

pub fn build(b: *std.Build) !void {
    const zashi_dep = b.dependency("zashi", .{});

    const zashi_exe = zashi_dep.artifact("zashi");
    const run_server = b.addRunArtifact(zashi_exe);
    run_server.addArgs(&.{ "serve", "--root", b.install_path });
    if (b.option(u16, "port", "port to listen on for the development server")) |port| {
        run_server.addArgs(&.{ "-p", b.fmt("{d}", .{port}) });
    }

    const run_step = b.step("serve", "Run the local development web server");
    run_step.dependOn(&run_server.step);
    run_server.step.dependOn(b.getInstallStep());

    try zashi.addWebsite(b, .{
        .content_dir_path = "./content",
        .zashi = zashi_dep,
    });
}
