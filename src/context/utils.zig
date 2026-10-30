const std = @import("std");
const ziggy = @import("ziggy");
const super = @import("superhtml");
const Allocator = std.mem.Allocator;
const Asset = @import("Asset.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Page = context.Page;

pub const log = std.log.scoped(.builtin);

/// Convert a term name to a URL-safe slug.
/// Lowercases, replaces non-alphanumeric with hyphens, collapses consecutive
/// hyphens, and trims leading/trailing hyphens.
pub fn slugify(gpa: Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(gpa);
    var prev_was_hyphen = true; // prevents leading hyphen
    for (input) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try result.append(gpa, std.ascii.toLower(ch));
            prev_was_hyphen = false;
        } else if (!prev_was_hyphen) {
            try result.append(gpa, '-');
            prev_was_hyphen = true;
        }
    }
    // Trim trailing hyphen
    if (result.items.len > 0 and result.items[result.items.len - 1] == '-') {
        result.items.len -= 1;
    }
    return result.toOwnedSlice(gpa);
}

/// Extract taxonomy terms from a page for the given taxonomy name.
/// For "tags", reads from the built-in page.tags field.
/// For other names, reads from page.custom.{name} (must be array of strings).
pub fn extractTermsFromPage(
    gpa: Allocator,
    page: *const Page,
    taxonomy_name: []const u8,
) !?[]const []const u8 {
    if (std.mem.eql(u8, taxonomy_name, "tags")) {
        return if (page.tags.len > 0) page.tags else null;
    }

    // Read from page.custom
    switch (page.custom) {
        .kv => |kv| {
            const val = kv.fields.get(taxonomy_name) orelse return null;
            switch (val) {
                .array => |arr| {
                    if (arr.len == 0) return null;
                    const terms = try gpa.alloc([]const u8, arr.len);
                    for (arr, 0..) |elem, i| {
                        switch (elem) {
                            .bytes => |b| terms[i] = b,
                            else => return null,
                        }
                    }
                    return terms;
                },
                else => return null,
            }
        },
        else => return null,
    }
}
