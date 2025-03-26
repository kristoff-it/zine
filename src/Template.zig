const Template = @This();

const std = @import("std");
const superhtml = @import("superhtml");
const tracy = @import("tracy");
const fatal = @import("fatal.zig");
const worker = @import("worker.zig");
const Build = @import("Build.zig");
const StringTable = @import("StringTable.zig");
const String = StringTable.String;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// Reference counting, all other fields are only present if rc > 0
rc: std.atomic.Value(u32) = .init(0),
src: []const u8 = undefined,
html_ast: superhtml.html.Ast = undefined,
// Only present if html_ast.errors.len == 0
ast: superhtml.Ast = undefined,
// Only present if ast.errors.len == 0
missing_parent: bool = undefined,

pub const TaggedName = packed struct {
    is_layout: bool,
    name: u31,

    pub const max = std.math.maxInt(u32) / 2;

    pub fn fromString(s: String, is_layout: bool) TaggedName {
        assert(@intFromEnum(s) < max);
        return .{ .is_layout = is_layout, .name = @intCast(@intFromEnum(s)) };
    }

    pub fn toString(tn: TaggedName) String {
        return @enumFromInt(tn.name);
    }
};

pub fn deinit(t: *const Template, gpa: Allocator) void {
    gpa.free(t.src);
    t.html_ast.deinit(gpa);
    t.ast.deinit(gpa);
}

pub fn parse(
    t: *Template,
    gpa: Allocator,
    arena: Allocator,
    table: *const StringTable,
    templates: *const Build.Templates,
    layouts_dir: std.fs.Dir,
    name: []const u8,
    is_layout: bool,
) void {
    const zone = tracy.trace(@src());
    defer zone.end();

    assert(t.rc.load(.acquire) > 0);
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const path = if (is_layout) name else try std.fs.path.join(arena, &.{
        "templates",
        name,
    });

    const max = std.math.maxInt(u32);
    const src = layouts_dir.readFileAlloc(gpa, path, max) catch |err| fatal.file(name, err);

    t.src = src;
    t.html_ast = try .init(
        gpa,
        src,
        if (std.mem.endsWith(u8, name, ".xml")) .xml else .superhtml,
    );
    if (t.html_ast.errors.len > 0) return;
    t.ast = try .init(gpa, t.html_ast, src);

    if (t.ast.errors.len == 0 and t.ast.extends_idx != 0) {
        const parent_name = t.ast.nodes[t.ast.extends_idx].templateValue().span.slice(src);
        const parent_str = table.get(parent_name) orelse {
            t.missing_parent = true;
            return;
        };
        const parent = templates.getPtr(.fromString(parent_str, false)) orelse {
            t.missing_parent = true;
            return;
        };

        t.missing_parent = false;
        if (parent.rc.fetchAdd(1, .acq_rel) == 0) {
            // We were the first to activate this template
            worker.addJob(.{
                .template_parse = .{
                    .table = table,
                    .templates = templates,
                    .layouts_dir = layouts_dir,
                    .template = parent,
                    .name = parent_name,
                    .is_layout = false,
                },
            });
        }
    }
}
