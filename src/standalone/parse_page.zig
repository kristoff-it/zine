const std = @import("std");
const Build = @import("../main.zig").Build;
const Section = @import("scan_content.zig").Section;

pub fn parsePage(build: Build, page: *Section.Page, section: *Section) void {
    var buf: [4096 * 2]u8 = undefined;
    const path = std.fmt.bufPrint("{}", .{std.fs.path.fmtJoin(&.{
        // page.
    })});
    const file = std.fs.cwd().readFileAlloc(gpa, )
}
