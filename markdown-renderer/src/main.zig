const std = @import("std");
const c = @cImport({
    @cInclude("cmark-gfm.h");
});

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const ally = arena.allocator();

    const args = try std.process.argsAlloc(ally);
    const in_path = args[1];
    const out_path = args[2];

    const in_string = in_string: {
        const in_file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            std.debug.print("Error while opening file: {s}\n", .{in_path});
            return err;
        };
        defer in_file.close();

        break :in_string try in_file.reader().readAllAlloc(ally, 1024);
    };

    const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        std.debug.print("Error while creating file: {s}\n", .{out_path});
        return err;
    };
    defer out_file.close();

    const ast = c.cmark_parse_document(in_string.ptr, in_string.len, c.CMARK_OPT_DEFAULT);
    const html_raw: [*:0]const u8 = c.cmark_render_html(ast, c.CMARK_OPT_DEFAULT, null);

    try out_file.writeAll(std.mem.span(html_raw));
}
