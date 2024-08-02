const std = @import("std");

pub const Layout = struct {
    template: ?[]const u8,
    exe: *std.Build.Step.Compile,
};

pub fn scan(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    layouts_dir_path: []const u8,
) !std.StringHashMap(Layout) {
    // Filled out one by one
    var compiled_layouts = std.StringHashMap(Layout).init(project.allocator);
    // Passed down to `addLayoutCompilation` as one layout can discover
    // a long template dependence chain
    const compiled_templates = std.StringHashMap(Layout).init(project.allocator);
    _ = compiled_templates;

    const layouts_dir = try project.build_root.handle.openDir(
        layouts_dir_path,
        .{ .iterate = true },
    );

    var it = layouts_dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            else => continue,
            .file => if (std.mem.endsWith(u8, entry.name, ".html")) {
                const compiled_layout = addLayoutCompilation(
                    project,
                    zine_dep,
                    layouts_dir_path,
                    entry.name,
                ) catch |err| {
                    std.debug.print(
                        "Error while processing {s} in /{s}\n",
                        .{ entry.name, layouts_dir_path },
                    );
                    return err;
                };
                try compiled_layouts.put(entry.name, compiled_layout);
            },
        }
    }

    return compiled_layouts;
}

fn addLayoutCompilation(
    project: *std.Build,
    zine_dep: *std.Build.Dependency,
    layouts_dir_path: []const u8,
    name: []const u8,
) !Layout {
    const layout_path = project.pathJoin(&.{ layouts_dir_path, name });

    // Discorver if the layout extends a template or not
    const template = try findParentTemplateName(layout_path, project.allocator);

    if (template != null) {
        std.debug.print("Template inheritance is not implemented yet.\n", .{});
        return error.TODO;
    }

    const layout_exe = project.addExecutable(.{
        .name = name,
        .root_source_file = zine_dep.path("super.zig"),
    });

    layout_exe.addAnonymousModule("layout", .{
        .source_file = .{
            .path = layout_path,
        },
    });

    return .{
        .template = template,
        .exe = layout_exe,
    };
}

fn findParentTemplateName(
    project: *std.Build,
    path: []const u8,
    arena: std.mem.Allocator,
) !?[]const u8 {
    const file = try project.build_root.handle.openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const r = buf_reader.reader();

    var buf = std.ArrayList(u8).init(arena);
    r.streamUntilDelimiter(buf.writer(), '>', 4096) catch |err| {
        std.debug.print("I/O error while parsing the opening <zine> tag.\n", .{});
        return err;
    };

    const tag = blk: {
        const tag = std.mem.trimLeft(u8, buf.items, &std.ascii.whitespace);
        if (!std.mem.startsWith(u8, tag, "<")) return null;
        break :blk tag[1..];
    };

    var it = std.mem.tokenizeAny(u8, tag, std.ascii.whitespace ++ "=");
    var state: enum { zine, template, path } = .zine;
    while (it.next()) |tok| switch (state) {
        .zine => {
            if (!std.mem.eql(u8, tok, "zine")) {
                return null;
            }
            if (std.mem.indexOfScalar(u8, &std.ascii.whitespace, tag[it.index]) == null) {
                return error.BadZineTag;
            }
            state = .template;
        },
        .template => {
            if (!std.mem.eql(u8, tok, "template") or tag[it.index] != '=') {
                return error.BadZineTag;
            }
            state = .path;
        },
        .path => {
            if (!std.mem.startsWith(u8, tok, "\"") or
                !std.mem.endsWith(u8, tok, "\"") or
                it.next() != null)
            {
                return error.BadZineTag;
            }

            return std.mem.trim(u8, tok, "\"");
        },
    };

    if (state == .zine) return null;
    return error.BadZineTag;
}
