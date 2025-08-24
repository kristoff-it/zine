const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.highlight);
const Writer = std.Io.Writer;
const options = @import("options");
const syntax = @import("syntax");
const treez = @import("treez");
const tracy = @import("tracy");
const HtmlSafe = @import("superhtml").HtmlSafe;

pub const DotsToUnderscores = struct {
    bytes: []const u8,

    pub fn format(self: DotsToUnderscores, w: *Writer) !void {
        for (self.bytes) |b| {
            switch (b) {
                '.' => try w.writeAll("_"),
                else => try w.writeByte(b),
            }
        }
    }
};

var query_cache: syntax.QueryCache = .{
    .allocator = @import("main.zig").gpa,
    .mutex = std.Thread.Mutex{},
};

const ClassSet = struct {
    classes: std.StringHashMap(void),

    const Self = @This();

    pub fn init(gpa: Allocator) ClassSet {
        return .{
            .classes = std.StringHashMap(void).init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.classes.deinit();
    }

    pub fn addClass(self: *Self, class: []const u8) !void {
        try self.classes.put(class, {});
    }

    pub fn removeClass(self: *Self, class: []const u8) void {
        _ = self.classes.remove(class);
    }

    pub fn getClasses(self: Self, gpa: Allocator, result: *std.ArrayList([]const u8)) !void {
        result.clearRetainingCapacity();
        var it = self.classes.keyIterator();
        while (it.next()) |key| try result.append(gpa, key.*);
    }
};

const ClassChange = struct {
    position: usize,
    is_add: bool,
    class: []const u8,

    pub fn lessThan(_: void, a: ClassChange, b: ClassChange) bool {
        return a.position < b.position;
    }
};

fn printSpan(
    arena: Allocator,
    w: *Writer,
    code: []const u8,
    start: usize,
    end: usize,
    classes: []const []const u8,
) !void {
    if (classes.len == 0) {
        try w.print("{f}", .{HtmlSafe{ .bytes = code[start..end] }});
        return;
    }

    var class_str: std.ArrayList(u8) = .empty;
    defer class_str.deinit(arena);

    for (classes, 0..) |class, i| {
        if (i > 0) try class_str.append(arena, ' ');
        try class_str.appendSlice(arena, class);
    }

    try w.print(
        \\<span class="{f}">{f}</span>
    , .{
        DotsToUnderscores{ .bytes = class_str.items },
        HtmlSafe{ .bytes = code[start..end] },
    });
}

pub fn highlightCode(
    arena: Allocator,
    lang_name: []const u8,
    code: []const u8,
    w: *Writer,
) !void {
    const zone = tracy.traceNamed(@src(), "highlightCode");
    defer zone.end();
    tracy.messageCopy(lang_name);

    if (!options.enable_treesitter) {
        try w.print("{f}", .{HtmlSafe{ .bytes = code }});
        return;
    }

    const lang = blk: {
        const query_zone = tracy.traceNamed(@src(), "syntax");
        defer query_zone.end();

        break :blk syntax.create_file_type_static(
            arena,
            lang_name,
            &query_cache,
        ) catch {
            const syntax_fallback_zone = tracy.traceNamed(@src(), "syntax fallback");
            defer syntax_fallback_zone.end();
            const fake_filename = try std.fmt.allocPrint(arena, "file.{s}", .{lang_name});
            break :blk try syntax.create_guess_file_type_static(arena, "", fake_filename, &query_cache);
        };
    };

    {
        const refresh_zone = tracy.traceNamed(@src(), "refresh");
        defer refresh_zone.end();
        try lang.refresh_full(code);
    }
    // we don't want to free any resource from the query cache
    // defer lang.destroy();

    const tree = lang.tree orelse return;
    const cursor = try treez.Query.Cursor.create();
    defer cursor.destroy();

    {
        const query_zone = tracy.traceNamed(@src(), "exec query");
        defer query_zone.end();
        cursor.execute(lang.query, tree.getRootNode());
    }

    const match_zone = tracy.traceNamed(@src(), "render");
    defer match_zone.end();

    cursor.execute(lang.query, tree.getRootNode());

    var changes: std.ArrayList(ClassChange) = .empty;

    while (cursor.nextMatch()) |match| {
        for (match.captures()) |capture| {
            const range = capture.node.getRange();
            const capture_name = lang.query.getCaptureNameForId(capture.id);

            try changes.append(arena, .{
                .position = range.start_byte,
                .is_add = true,
                .class = capture_name,
            });

            try changes.append(arena, .{
                .position = range.end_byte,
                .is_add = false,
                .class = capture_name,
            });
        }
    }

    std.sort.insertion(ClassChange, changes.items, {}, ClassChange.lessThan);

    var current_classes = ClassSet.init(arena);
    defer current_classes.deinit();

    var class_list: std.ArrayList([]const u8) = .empty;
    defer class_list.deinit(arena);

    var current_pos: usize = 0;

    for (changes.items) |change| {
        if (change.position > current_pos) {
            try current_classes.getClasses(arena, &class_list);
            try printSpan(arena, w, code, current_pos, change.position, class_list.items);
            current_pos = change.position;
        }

        if (change.is_add) {
            try current_classes.addClass(change.class);
            continue;
        }

        current_classes.removeClass(change.class);
    }

    if (current_pos < code.len) {
        try current_classes.getClasses(arena, &class_list);
        try printSpan(arena, w, code, current_pos, code.len, class_list.items);
    }
}
