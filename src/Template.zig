const Template = @This();

const std = @import("std");
const superhtml = @import("superhtml");
const tracy = @import("tracy");
const root = @import("root.zig");
const fatal = @import("fatal.zig");
const worker = @import("worker.zig");
const Build = @import("Build.zig");
const StringTable = @import("StringTable.zig");
const String = StringTable.String;
const PathTable = @import("PathTable.zig");
const Path = PathTable.Path;
const PathName = PathTable.PathName;
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
layout: bool,

pub fn deinit(t: *const Template, gpa: Allocator) void {
    gpa.free(t.src);
    t.html_ast.deinit(gpa);
    t.ast.deinit(gpa);
}

pub fn parse(
    t: *Template,
    gpa: Allocator,
    arena: Allocator,
    build: *const Build,
    pn: PathName,
) void {
    const zone = tracy.trace(@src());
    defer zone.end();

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const path = try std.fmt.allocPrint(arena, "{/}", .{
        pn.fmt(&build.st, &build.pt, null),
    });

    const max = std.math.maxInt(u32);
    const src = build.layouts_dir.readFileAlloc(
        gpa,
        path,
        max,
    ) catch |err| fatal.file(path, err);

    t.src = src;

    t.html_ast = try .init(
        gpa,
        src,
        if (std.mem.endsWith(u8, path, ".xml")) .xml else .superhtml,
    );
    if (t.html_ast.errors.len > 0) return;

    t.ast = try .init(gpa, t.html_ast, src);

    if (t.ast.errors.len == 0 and t.ast.extends_idx != 0) {
        const parent_name = t.ast.nodes[t.ast.extends_idx].templateValue().span.slice(src);
        const parent_path = try root.join(arena, &.{ "templates", parent_name }, '/');
        const parent_pn = PathName.get(&build.st, &build.pt, parent_path) orelse {
            t.missing_parent = true;
            return;
        };
        if (!build.templates.contains(parent_pn)) {
            t.missing_parent = true;
            return;
        }

        t.missing_parent = false;
    }
}
