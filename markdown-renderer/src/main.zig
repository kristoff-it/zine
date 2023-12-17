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
    const assets_in_path = args[1];
    const assets_dep_path = args[2];
    const assets_out_path = args[3];
    const md_in_path = args[4];
    const html_out_path = args[5];

    var assets_in_dir = std.fs.cwd().openDir(assets_in_path, .{}) catch |err| {
        std.debug.print("Error while opening assets input dir: {s}\n", .{assets_in_path});
        return err;
    };
    defer assets_in_dir.close();

    const assets_dep_file = std.fs.cwd().createFile(assets_dep_path, .{}) catch |err| {
        std.debug.print("Error while creating file: {s}\n", .{assets_dep_path});
        return err;
    };
    defer assets_dep_file.close();

    var assets_out_dir = std.fs.cwd().openDir(assets_out_path, .{}) catch |err| {
        std.debug.print("Error while opening assets output dir: {s}\n", .{assets_out_path});
        return err;
    };
    defer assets_out_dir.close();

    const in_file = std.fs.cwd().openFile(md_in_path, .{}) catch |err| {
        std.debug.print("Error while opening file: {s}\n", .{md_in_path});
        return err;
    };
    defer in_file.close();

    var buf_reader = std.io.bufferedReader(in_file.reader());
    const r = buf_reader.reader();
    const fm = try frontmatter.parse(std.json.Value, r, arena);
    _ = fm;

    const in_string = try r.readAllAlloc(arena, 1024);

    const out_file = std.fs.cwd().createFile(html_out_path, .{}) catch |err| {
        std.debug.print("Error while creating file: {s}\n", .{html_out_path});
        return err;
    };
    defer out_file.close();

    const ast = c.cmark_parse_document(in_string.ptr, in_string.len, c.CMARK_OPT_DEFAULT).?;

    const iter = Iter.init(ast);
    defer iter.deinit();

    try assets_dep_file.writeAll("assets: ");
    var seen_assets = std.StringHashMap(void).init(arena);
    while (iter.next()) |node| {
        if (node.isImage()) {
            std.debug.print("md-renderer: found image\n", .{});
            const link = node.link() orelse {
                @panic("TODO: explain that an image without url was found in the markdown file");
            };

            // Skip duplicates
            if (seen_assets.contains(link)) continue;

            // Skip non-local images
            if (std.mem.startsWith(u8, link, "http")) continue;

            assets_in_dir.access(link, .{}) catch {
                @panic("TODO: explain that a missing image has been found in a markdown file");
            };

            std.debug.print("copying  {s}\n", .{link});

            const path = try std.fs.path.join(arena, &.{ assets_in_path, link });
            try assets_dep_file.writer().print("{s} ", .{path});
            try assets_in_dir.copyFile(link, assets_out_dir, link, .{});
            try seen_assets.put(link, {});
        }
    }

    const html_raw: [*:0]const u8 = c.cmark_render_html(ast, c.CMARK_OPT_DEFAULT, null);

    try out_file.writeAll(std.mem.span(html_raw));
}

const Iter = struct {
    it: *c.cmark_iter,

    pub fn init(ast: *c.cmark_node) Iter {
        return .{ .it = c.cmark_iter_new(ast).? };
    }

    pub fn deinit(self: Iter) void {
        c.cmark_iter_free(self.it);
    }

    pub fn next(self: Iter) ?Node {
        while (true) switch (c.cmark_iter_next(self.it)) {
            c.CMARK_EVENT_DONE => return null,
            c.CMARK_EVENT_EXIT => continue,
            c.CMARK_EVENT_ENTER => break,
            else => unreachable,
        };

        return .{ .n = c.cmark_iter_get_node(self.it).? };
    }
};

const Node = struct {
    n: *c.cmark_node,

    pub fn isImage(self: Node) bool {
        const t = c.cmark_node_get_type(self.n);
        return t == (0x8000 | 0x4000 | 0x000a);
    }

    pub fn link(self: Node) ?[]const u8 {
        const ptr = c.cmark_node_get_url(self.n) orelse return null;
        return std.mem.span(ptr);
    }
};
