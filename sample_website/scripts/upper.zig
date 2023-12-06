const std = @import("std");
const zine = @import("zine");

pub fn script(str: []const u8) []const u8 {
    return std.ascii.toUpper(str);
}
