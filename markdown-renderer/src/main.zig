const std = @import("std");
const frontmatter = @import("frontmatter");

const c = @cImport({
    @cInclude("cmark-gfm.h");
});

pub fn main() !void {
    var arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const args = try std.process.argsAlloc(arena);
    const in_path = args[1];
    const out_path = args[2];

    const in_string = in_string: {
        const in_file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            std.debug.print("Error while opening file: {s}\n", .{in_path});
            return err;
        };
        defer in_file.close();

        var buf_reader = std.io.bufferedReader(in_file.reader());
        const r = buf_reader.reader();
        const fm = try frontmatter.parse(r, arena);
        _ = fm; // TODO: decide if we need this at all or not

        break :in_string try r.readAllAlloc(arena, 1024);
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
