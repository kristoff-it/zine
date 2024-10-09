const std = @import("std");

const DepWriter = @This();

w: std.io.AnyWriter,

pub fn init(writer: std.io.AnyWriter) DepWriter {
	return .{.w=writer};
}

pub fn writeTarget(dw: DepWriter, target: []const u8) !void {
	try dw.w.print("\n{s}:", .{target});
}

pub fn writePrereq(dw: DepWriter, prereq: []const u8) !void {
	try dw.w.print(" \"{s}\"", .{prereq});
}
