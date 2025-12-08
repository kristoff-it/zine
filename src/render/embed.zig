// this implementation is not strong and robust

const std = @import("std");
const context = @import("../context.zig");
const Build = @import("../Build.zig");
const mime = @import("mime");
const log = std.log.scoped(.embed);

pub fn processExportHtml(
    gpa: std.mem.Allocator,
    build: *const Build,
    page: *const context.Page,
    html_content: []const u8,
    w: anytype,
) !void {
    var i: usize = 0;
    var scratch = std.ArrayListUnmanaged(u8){};
    defer scratch.deinit(gpa);

    // Get page URL for prefix
    const v = build.variants[page._scan.variant_id];
    var page_url_buffer: [512]u8 = undefined;
    const page_url_formatted = page._scan.url.fmt(&v.string_table, &v.path_table, "/", false);
    const page_url = std.fmt.bufPrint(&page_url_buffer, "{f}", .{page_url_formatted}) catch return;

    while (i < html_content.len) {
        const lt = std.mem.indexOfScalarPos(u8, html_content, i, '<');
        if (lt == null) {
            try w.writeAll(html_content[i..]);
            break;
        }
        try w.writeAll(html_content[i..lt.?]);
        i = lt.?;

        // Handle comments <!-- ... -->
        if (std.mem.startsWith(u8, html_content[i..], "<!--")) {
            if (std.mem.indexOfPos(u8, html_content, i, "-->")) |end| {
                const comment_end = end + 3;
                try w.writeAll(html_content[i..comment_end]);
                i = comment_end;
                continue;
            }
            // If malformed (no closing -->), let the loop continue to process < as part of tag or text
        }

        // Naive tag parsing
        var j = i + 1;
        // Skip / if closing tag
        if (j < html_content.len and html_content[j] == '/') {
            j += 1;
        }

        // Get tag name
        const name_start = j;
        while (j < html_content.len and (std.ascii.isAlphanumeric(html_content[j]) or html_content[j] == '-')) : (j += 1) {}
        const tag_name = html_content[name_start..j];

        // Find end of tag >
        var cursor = j;
        var in_quote: ?u8 = null;
        var tag_end: ?usize = null;

        while (cursor < html_content.len) : (cursor += 1) {
            const char = html_content[cursor];
            if (in_quote) |q| {
                if (char == q) in_quote = null;
            } else {
                if (char == '"' or char == '\'') {
                    in_quote = char;
                } else if (char == '>') {
                    tag_end = cursor;
                    break;
                }
            }
        }

        if (tag_end == null) {
            // Malformed, just print <
            try w.writeByte('<');
            i += 1;
            continue;
        }

        var tag_content = html_content[i .. tag_end.? + 1]; // <... >
        var modified_tag_buf: std.ArrayListUnmanaged(u8) = .{};
        defer modified_tag_buf.deinit(gpa);

        // Check for ID attribute to prefix
        if (findAttrValue(tag_content, "id")) |id| {
            scratch.clearRetainingCapacity();
            try scratch.appendSlice(gpa, page_url);
            try scratch.appendSlice(gpa, "-");
            try scratch.appendSlice(gpa, id);

            try writeTagWithNewAttr(modified_tag_buf.writer(gpa), tag_content, "id", scratch.items);
            tag_content = modified_tag_buf.items;
        }

        var handled = false;

        if (std.mem.eql(u8, tag_name, "img")) {
            handled = handleImg(gpa, build, page, tag_content, w) catch |err| blk: {
                log.err("Failed to process img tag: {s}", .{@errorName(err)});
                break :blk false;
            };
        } else if (std.mem.eql(u8, tag_name, "a")) {
            handled = handleAnchor(gpa, tag_content, w, &scratch, page_url) catch |err| blk: {
                log.err("Failed to process anchor tag: {s}", .{@errorName(err)});
                break :blk false;
            };
        }

        if (!handled) {
            // If no special processing was done, write original tag
            try w.writeAll(tag_content);
        }

        i = tag_end.? + 1;
    }
}

fn handleImg(
    gpa: std.mem.Allocator,
    build: *const Build,
    page: *const context.Page,
    tag_content: []const u8,
    w: anytype,
) !bool {
    const span = findAttrSpan(tag_content, "src") orelse return false;
    const src = tag_content[span.start..span.end];

    if (std.mem.startsWith(u8, src, "http://") or std.mem.startsWith(u8, src, "https://")) {
        log.warn("Remote image embedding is not supported. Skipping embed for src: {s}", .{src});
        return false;
    }

    if (try resolveRawPath(gpa, src, build, page)) |abs_path| {
        defer gpa.free(abs_path);

        // Write part before src value
        try w.writeAll(tag_content[0..span.start]);

        // Stream the embedded image
        const embedded = try embedImage(gpa, abs_path, w);
        if (!embedded) {
            // Fallback to original src if embed fails
            log.warn("Failed to embed image at {s}. Using original src.", .{abs_path});
            try w.writeAll(src);
        }

        // Write part after src value
        try w.writeAll(tag_content[span.end..]);
        return true;
    }

    return false;
}

fn handleAnchor(
    gpa: std.mem.Allocator,
    tag_content: []const u8,
    w: anytype,
    scratch: *std.ArrayListUnmanaged(u8),
    page_url: []const u8,
) !bool {
    const href = findAttrValue(tag_content, "href") orelse return false;

    if (std.mem.startsWith(u8, href, "#")) {
        // Internal anchor link, add page prefix
        const anchor_text = href[1..]; // Remove #

        scratch.clearRetainingCapacity();
        const writer = scratch.writer(gpa);

        try writer.writeByte('#');
        try writer.writeAll(page_url);
        try writer.writeByte('-');
        try writer.writeAll(anchor_text);

        try writeTagWithNewAttr(w, tag_content, "href", scratch.items);
        return true;
    } else if (std.mem.startsWith(u8, href, "/")) {
        // Internal site link, convert path to hyphen format
        const path_part = href[1..]; // Remove leading /

        scratch.clearRetainingCapacity();
        const writer = scratch.writer(gpa);

        // Check if it contains a # for anchor
        if (std.mem.indexOf(u8, path_part, "#")) |hash_pos| {
            const path_before_hash_segment = href[1 .. hash_pos + 1];
            const anchor_text = path_part[hash_pos + 1 ..];

            try writer.writeAll(path_before_hash_segment);
            try writer.writeByte('-');
            try writer.writeAll(anchor_text);
        } else {
            var processed_path: []const u8 = href;
            if (processed_path.len > 1 and processed_path[processed_path.len - 1] == '/') {
                processed_path = processed_path[0 .. processed_path.len - 1];
            }

            try writer.writeAll("#");
            try writer.writeAll(processed_path);
        }

        try writeTagWithNewAttr(w, tag_content, "href", scratch.items);
        return true;
    }

    return false;
}


const Span = struct {
    start: usize,
    end: usize,
};

pub fn findAttrSpan(tag: []const u8, attr: []const u8) ?Span {
    var i: usize = 0;
    while (i < tag.len) {
        const start = std.mem.indexOfPos(u8, tag, i, attr) orelse return null;
        if (start > 0 and (std.ascii.isAlphanumeric(tag[start - 1]) or tag[start - 1] == '-')) {
            i = start + 1;
            continue;
        }
        var cursor = start + attr.len;
        if (cursor < tag.len and tag[cursor] != ' ' and tag[cursor] != '=') {
            i = start + 1;
            continue;
        }
        while (cursor < tag.len and tag[cursor] == ' ') cursor += 1;
        if (cursor >= tag.len or tag[cursor] != '=') return null;
        cursor += 1;
        while (cursor < tag.len and tag[cursor] == ' ') cursor += 1;
        if (cursor >= tag.len) return null;

        const q = tag[cursor];
        if (q == '"' or q == '\'') {
            cursor += 1;
            const val_start = cursor;
            while (cursor < tag.len and tag[cursor] != q) cursor += 1;
            return Span{ .start = val_start, .end = cursor };
        } else {
            const val_start = cursor;
            while (cursor < tag.len and tag[cursor] != ' ' and tag[cursor] != '>') cursor += 1;
            return Span{ .start = val_start, .end = cursor };
        }
    }
    return null;
}

pub fn findAttrValue(tag: []const u8, attr: []const u8) ?[]const u8 {
    if (findAttrSpan(tag, attr)) |span| {
        return tag[span.start..span.end];
    }
    return null;
}

pub fn writeTagWithNewAttr(w: anytype, tag: []const u8, attr: []const u8, new_val: []const u8) !void {
    if (findAttrSpan(tag, attr)) |span| {
        try w.writeAll(tag[0..span.start]);
        try w.writeAll(new_val);
        try w.writeAll(tag[span.end..]);
    } else {
        try w.writeAll(tag);
    }
}

pub fn embedCss(
    gpa: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    w: anytype,
) !bool {
    const extension = std.fs.path.extension(path);
    if (!std.mem.eql(u8, extension, ".css")) {
        log.warn("Unsupported css extension: {s}", .{path});
        return false;
    }

    const file = try dir.openFile(path, .{});
    defer file.close();

    // Get file size first
    const file_size = try file.getEndPos();

    // Allocate buffer for file content
    const content = try gpa.alloc(u8, file_size);
    defer gpa.free(content);

    // Read entire file
    _ = try file.readAll(content);

    try w.print("<style>\n{s}\n</style>", .{content});
    return true;
}

pub fn embedImage(
    gpa: std.mem.Allocator,
    abs_path: []const u8, // Expecting absolute path or path relative to cwd
    w: anytype,
) !bool {
    const extension = std.fs.path.extension(abs_path);
    if (extension.len < 2) return false;

    const mime_enum = mime.extension_map.get(extension) orelse return false;
    const mime_type = @tagName(mime_enum);
    if (!std.mem.startsWith(u8, mime_type, "image/")){
        log.warn("Unsupported mime type of images: {s}", .{mime_type});
        return false;
    }

    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();

    // Get file size first
    const file_size = try file.getEndPos();

    // Calculate base64 encoded size
    const b64_len = std.base64.standard.Encoder.calcSize(file_size);

    // Allocate single buffer for both file content and base64
    const buffer = try gpa.alloc(u8, b64_len);
    defer gpa.free(buffer);

    // Store file content at the end of the buffer
    const file_content_start = b64_len - file_size;
    const file_content = buffer[file_content_start..];
    _ = try file.readAll(file_content);

    // Encode base64 to the beginning of the buffer
    _ = std.base64.standard.Encoder.encode(buffer, file_content);

    try w.print("data:{s};base64,{s}", .{ mime_type, buffer });

    return true;
}

pub fn resolveRawPath(
    gpa: std.mem.Allocator,
    path: []const u8,
    build: *const Build,
    page: *const context.Page,
) !?[]const u8 {
    if (path.len == 0) return null;

    const base_dir_path = build.base_dir_path;

    // Check if it's a build asset first
    if (build.build_assets.get(path)) |build_asset| {
        return try std.fs.path.join(gpa, &.{ base_dir_path, build_asset.input_path });
    }

    if (path[0] == '/') {
        // Site asset
        const assets_dir_path = build.cfg.getAssetsDirPath();
        return try std.fs.path.join(gpa, &.{ base_dir_path, assets_dir_path, path[1..] });
    } else {
        // Page asset (relative)
        const v = build.variants[page._scan.variant_id];
        const content_dir_path = v.content_dir_path;

        const page_dir_path = try std.fmt.allocPrint(gpa, "{f}", .{
            page._scan.file.path.fmt(&v.string_table, &v.path_table, null, false),
        });
        defer gpa.free(page_dir_path);

        return try std.fs.path.join(gpa, &.{ base_dir_path, content_dir_path, page_dir_path, path });
    }
}
