const std = @import("std");
const layout = @embedFile("layout");

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = try std.process.argsAlloc(arena);
    const in_path = args[1];
    const out_path = args[2];

    const rendered_md_string = in_string: {
        const in_file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            std.debug.print("Error while opening file: {s}\n", .{in_path});
            return err;
        };
        defer in_file.close();

        var buf_reader = std.io.bufferedReader(in_file.reader());
        const r = buf_reader.reader();
        break :in_string try r.readAllAlloc(arena, 1024);
    };

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        std.debug.print("Error while creating file: {s}\n", .{out_path});
        return err;
    };
    defer out_file.close();

    const tag = "var=\"$page.content\">";
    const injection_point = comptime std.mem.indexOf(u8, layout, tag) orelse
        @compileError("Unable to find `$page.content`!");

    try out_file.writeAll(layout[0 .. injection_point + tag.len]);
    try out_file.writeAll(rendered_md_string);
    try out_file.writeAll(layout[injection_point + tag.len ..]);
}
