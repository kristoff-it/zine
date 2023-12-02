const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    try zine.addWebsite(b, .{
        .templates_dir_path = "",
        .content_dir_path = "./content",
        .zine = b.dependency("zine", .{}),
    });
}
