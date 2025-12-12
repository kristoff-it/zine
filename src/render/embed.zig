const std = @import("std");

const mime = @import("mime");
const superhtml = @import("superhtml");

const Build = @import("../Build.zig");
const context = @import("../context.zig");

pub fn processExportHtml(
    gpa: std.mem.Allocator,
    build: *const Build,
    page: *const context.Page,
    html_content: []const u8,
    w: anytype,
) !void {
    var ast = try superhtml.html.Ast.init(gpa, html_content, .html, false);
    defer ast.deinit(gpa);

    // Pre-calculate page URL prefix once
    const v = build.variants[page._scan.variant_id];
    const page_url_formatted = page._scan.url.fmt(&v.string_table, &v.path_table, "/", false);
    const page_url = try std.fmt.allocPrint(gpa, "{f}", .{page_url_formatted});
    defer gpa.free(page_url);

    // Handle empty AST
    if (ast.nodes.len == 0) return;

    // Start recursive rendering from root
    try renderNode(gpa, &ast, 0, build, page, html_content, w, page_url);
}

fn renderNode(
    gpa: std.mem.Allocator,
    ast: *const superhtml.html.Ast,
    node_idx: u32,
    build: *const Build,
    page: *const context.Page,
    src: []const u8,
    w: anytype,
    page_url: []const u8,
) !void {
    const node = ast.nodes[node_idx];

    switch (node.kind) {
        .root => {
            var child_idx = node.first_child_idx;
            while (child_idx != 0) {
                try renderNode(gpa, ast, child_idx, build, page, src, w, page_url);
                child_idx = ast.nodes[child_idx].next_idx;
            }
        },
        .text, .comment, .doctype => {
            // Write content as-is
            try w.writeAll(node.open.slice(src));
        },
        else => {
            // Element handling
            const tag_name = node.startTagIterator(src, .html).name_span.slice(src);

            // 1. Filter: Skip unwanted tags completely (including children)
            if (std.mem.eql(u8, tag_name, "script") or std.mem.eql(u8, tag_name, "link")) {
                return;
            }

            // 2. Open Tag Reconstruction
            try w.writeByte('<');
            try w.writeAll(tag_name);

            const TagType = enum { img, a, other };
            const tag_type: TagType = if (std.mem.eql(u8, tag_name, "img")) .img
                                      else if (std.mem.eql(u8, tag_name, "a")) .a
                                      else .other;

            var it = node.startTagIterator(src, .html);
            while (it.next(src)) |attr| {
                const name = attr.name.slice(src);
                // Default value is the original slice
                var val_slice = if (attr.value) |v| v.span.slice(src) else "";
                var needs_free = false;
                defer if (needs_free) gpa.free(val_slice);

                // 3. Attribute Transformation
                if (std.mem.eql(u8, name, "id")) {
                    // Prefix ID: page_url + "-" + original_id
                    val_slice = try std.fmt.allocPrint(gpa, "{s}-{s}", .{ page_url, val_slice });
                    needs_free = true;

                } else {
                    switch (tag_type) {
                        .img => if (std.mem.eql(u8, name, "src")) {
                             // Embed Image: resolve path -> base64
                             if (!std.mem.startsWith(u8, val_slice, "http://") and !std.mem.startsWith(u8, val_slice, "https://")) {
                                 if (try resolveRawPath(gpa, val_slice, build, page)) |abs_path| {
                                     defer gpa.free(abs_path);
                                     if (try embedImageToString(gpa, abs_path)) |b64| {
                                         val_slice = b64;
                                         needs_free = true;
                                     }
                                 }
                             }else{
                                 std.debug.print("error: Unsupport online images", .{});
                             }
                        },
                        .a => if (std.mem.eql(u8, name, "href")) {
                            // Fix Links: adjust anchors and relative paths
                            if (std.mem.startsWith(u8, val_slice, "#")) {
                                val_slice = try std.fmt.allocPrint(gpa, "#{s}-{s}", .{ page_url, val_slice[1..] });
                                needs_free = true;
                            } else if (std.mem.startsWith(u8, val_slice, "/")) {
                                const path_part = val_slice[1..];
                                if (std.mem.indexOf(u8, path_part, "#")) |hash_pos| {
                                    val_slice = try std.fmt.allocPrint(gpa, "{s}-{s}", .{ val_slice[1 .. hash_pos + 1], path_part[hash_pos + 1 ..] });
                                    needs_free = true;
                                } else {
                                    var processed = val_slice;
                                    if (processed.len > 1 and processed[processed.len - 1] == '/') {
                                        processed = processed[0 .. processed.len - 1];
                                    }
                                    val_slice = try std.fmt.allocPrint(gpa, "#{s}", .{processed});
                                    needs_free = true;
                                }
                            }
                        },
                        .other => {},
                    }
                }

                // Write attribute
                try w.writeByte(' ');
                try w.writeAll(name);
                if (attr.value != null) {
                    try w.print("=\"{s}\"", .{val_slice});
                }
            }

            try w.writeByte('>');

            // Special handling for <pre> or <code> to dump raw content
            if (std.mem.eql(u8, tag_name, "pre") or std.mem.eql(u8, tag_name, "code")) {
                if (node.close.start > node.open.end) {
                    try w.writeAll(src[node.open.end..node.close.start]);
                }
                try w.print("</{s}>", .{tag_name});
                return; // Do not recurse into children for <pre>/<code>
            }

            // General case for other elements: recurse children without gap-filling
            if (!isVoid(tag_name)) {
                var child_idx = node.first_child_idx;
                while (child_idx != 0) {
                    try renderNode(gpa, ast, child_idx, build, page, src, w, page_url);
                    child_idx = ast.nodes[child_idx].next_idx;
                }
                try w.print("</{s}>", .{tag_name});
            }
        },
    }
}

// --- Helpers ---

//getNodeEnd is no longer needed

fn isVoid(tag_name: []const u8) bool {
    const void_tags = &[_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    };
    for (void_tags) |t| {
        if (std.mem.eql(u8, tag_name, t)) return true;
    }
    return false;
}

pub fn embedCss(
    gpa: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    w: anytype,
) !bool {
    const extension = std.fs.path.extension(path);
    if (!std.mem.eql(u8, extension, ".css")) {
        std.debug.print("warning: Unsupported css extension: {s}\n", .{path});
        return false;
    }

    const file = try dir.openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(content);

    try w.print("<style>\n{s}\n</style>", .{content});
    return true;
}

fn embedImageToString(gpa: std.mem.Allocator, abs_path: []const u8) !?[]const u8 {
    const extension = std.fs.path.extension(abs_path);
    if (extension.len < 2) return null;

    const mime_enum = mime.extension_map.get(extension) orelse return null;
    const mime_type = @tagName(mime_enum);
    if (!std.mem.startsWith(u8, mime_type, "image/")) {
        std.debug.print("warning: Unsupported mime type of images: {s}\n", .{mime_type});
        return null;
    }

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch return null;
    defer file.close();

    const file_size = file.getEndPos() catch return null;
    const file_content = try file.readToEndAlloc(gpa, file_size);
    defer gpa.free(file_content);

    const b64_len = std.base64.standard.Encoder.calcSize(file_size);
    const prefix = try std.fmt.allocPrint(gpa, "data:{s};base64,", .{mime_type});
    const total_len = prefix.len + b64_len;

    const buffer = try gpa.alloc(u8, total_len);
    @memcpy(buffer[0..prefix.len], prefix);
    _ = std.base64.standard.Encoder.encode(buffer[prefix.len..], file_content);

    return buffer;
}

pub fn resolveRawPath(
    gpa: std.mem.Allocator,
    path: []const u8,
    build: *const Build,
    page: *const context.Page,
) !?[]const u8 {
    if (path.len == 0) return null;

    const base_dir_path = build.base_dir_path;

    if (build.build_assets.get(path)) |build_asset| {
        return try std.fs.path.join(gpa, &.{ base_dir_path, build_asset.input_path });
    }

    if (path[0] == '/') {
        const assets_dir_path = build.cfg.getAssetsDirPath();
        return try std.fs.path.join(gpa, &.{ base_dir_path, assets_dir_path, path[1..] });
    } else {
        const v = build.variants[page._scan.variant_id];
        const content_dir_path = v.content_dir_path;
        const page_dir_path = try std.fmt.allocPrint(gpa, "{f}", .{
            page._scan.file.path.fmt(&v.string_table, &v.path_table, null, false),
        });
        defer gpa.free(page_dir_path);
        return try std.fs.path.join(gpa, &.{ base_dir_path, content_dir_path, page_dir_path, path });
    }
}
