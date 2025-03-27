const Build = @This();

const std = @import("std");
const tracy = @import("tracy");
const ziggy = @import("ziggy");
const fatal = @import("fatal.zig");
const Variant = @import("Variant.zig");
const Template = @import("Template.zig");
const PathTable = @import("PathTable.zig");
const StringTable = @import("StringTable.zig");
const root = @import("root.zig");
const BuildAsset = root.BuildAsset;
const Path = PathTable.Path;
const String = StringTable.String;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Git = @import("Git.zig");

const log = std.log.scoped(.build);
const cache_dir_basename = ".zine-cache";

cfg: *const root.Config,
build_assets: *const std.StringArrayHashMapUnmanaged(BuildAsset),
any_prerendering_error: bool = false,
any_rendering_error: std.atomic.Value(bool) = .{ .raw = false },

base_dir_path: []const u8,
base_dir: std.fs.Dir,
st: StringTable,
pt: PathTable,
// Fields below are only valid after the corresponding processing stage
// has been reached, see main.zig for more info.
variants: []Variant = &.{},
// Layouts and templates are only identified by filename,
// layouts are expected to be placed directly under layouts_dir_path
// while templates are expected to be nested under `templates/`.
// This is extremely restrictive but there are some design considerations
// to make about relaxing this limitation.
// Should templates allowed to be placed anywhere? Should the "templates
// subdirectory" approach be global (ie only one templates dir) or should
// it be made relative to where the layout lives (eg 'layouts/foo/templates',
// 'layouts/bar/templates')?
layouts_dir: std.fs.Dir,
templates: Templates = .{},
site_assets_dir: std.fs.Dir,
site_assets: Assets = .empty,
i18n_dir: std.fs.Dir,
mode: Mode,

pub const Mode = union(enum) {
    memory: struct {
        // Errors that don't already have a natural storage location
        // (eg page errors are stored in the page itself)
        errors: std.ArrayListUnmanaged(Error) = .empty,
    },
    disk: struct {
        install_dir: std.fs.Dir,
    },

    const Error = struct {
        ref: []const u8, // the file this error relates to
        msg: []const u8,
    };
};

pub const Assets = std.AutoArrayHashMapUnmanaged(PathName, std.atomic.Value(u32));
pub const Templates = std.AutoArrayHashMapUnmanaged(Template.TaggedName, Template);

pub fn deinit(b: *const Build, gpa: Allocator) void {
    {
        var dir = b.base_dir;
        dir.close();
    }
    b.st.deinit(gpa);
    b.pt.deinit(gpa);
    for (b.variants) |v| v.deinit(gpa);
    gpa.free(b.variants);
    {
        var dir = b.layouts_dir;
        dir.close();
    }
    for (b.templates.entries.items(.value)) |t| t.deinit(gpa);
    {
        var ts = b.templates;
        ts.deinit(gpa);
    }
    {
        var dir = b.site_assets_dir;
        dir.close();
    }
    switch (b.mode) {
        .memory => {},
        .disk => |disk| {
            var dir = disk.install_dir;
            dir.close();
        },
    }

    if (b.cfg.* == .Multilingual) {
        var dir = b.i18n_dir;
        dir.close();
    }
}

/// Tries to load a zine.ziggy config file by searching
/// recursivly upwards from cwd. Once the config file is found,
/// it ensures the existence of all required directories and
/// loads git repository info (if in a repo).
pub fn load(gpa: Allocator, cfg: *const root.Config, opts: root.Options) Build {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const base_dir = std.fs.cwd().openDir(
        opts.base_dir_path,
        .{},
    ) catch |err|
        fatal.dir(opts.base_dir_path, err);

    const layouts_dir = base_dir.makeOpenPath(
        cfg.getLayoutsDirPath(),
        .{ .iterate = true },
    ) catch |err| fatal.dir(cfg.getLayoutsDirPath(), err);

    const assets_dir = base_dir.makeOpenPath(
        cfg.getAssetsDirPath(),
        .{ .iterate = true },
    ) catch |err| fatal.dir(cfg.getAssetsDirPath(), err);

    var table: StringTable = .empty;
    _ = try table.intern(gpa, "");

    var path_table: PathTable = .empty;
    _ = try path_table.intern(gpa, &.{});

    const mode: Mode = switch (opts.mode) {
        .memory => .{ .memory = .{} },
        .disk => |disk| blk: {
            const install_base_dir = if (disk.output_dir_path == null)
                base_dir
            else
                std.fs.cwd();
            const install_dir = install_base_dir.makeOpenPath(
                disk.output_dir_path orelse "public",
                .{},
            ) catch |err| fatal.dir(
                disk.output_dir_path orelse "public",
                err,
            );

            break :blk .{ .disk = .{ .install_dir = install_dir } };
        },
    };

    const i18n_dir = switch (cfg.*) {
        .Site => undefined,
        .Multilingual => |ml| base_dir.makeOpenPath(
            ml.i18n_dir_path,
            .{},
        ) catch |err| fatal.dir(ml.i18n_dir_path, err),
    };

    return .{
        .cfg = cfg,
        .build_assets = opts.build_assets,
        .base_dir = base_dir,
        .base_dir_path = opts.base_dir_path,
        .layouts_dir = layouts_dir,
        .site_assets_dir = assets_dir,
        .st = table,
        .pt = path_table,
        .mode = mode,
        .i18n_dir = i18n_dir,
    };
}

fn collectGitInfo(
    arena: Allocator,
    path: []const u8,
    dir: std.fs.Dir,
) void {
    const g = Git.init(arena, path) catch |err| fatal(
        "error while collecting git info: {s}",
        .{@errorName(err)},
    );

    const f = dir.createFile("git.ziggy", .{}) catch |err| fatal(
        "error while creating .zig-cache/zine/git.ziggy: {s}",
        .{@errorName(err)},
    );
    defer f.close();

    var buf = std.ArrayList(u8).init(arena);
    ziggy.stringify(g, .{}, buf.writer()) catch fatal(
        "unexpected",
        .{},
    );

    f.writeAll(buf.items) catch fatal("unexpected", .{});
}

pub fn scanSiteAssets(
    b: *Build,
    gpa: Allocator,
    arena: Allocator,
) !void {
    const zone = tracy.trace(@src());
    defer zone.end();

    var dir_stack: std.ArrayListUnmanaged([]const u8) = .empty;
    try dir_stack.append(arena, "");

    const empty_path: Path = @enumFromInt(0);
    assert(b.pt.get(&.{}) == empty_path);

    var progress = root.progress.start("Scan templates", 0);
    defer progress.end();

    while (dir_stack.pop()) |dir_entry| {
        var dir = switch (dir_entry.len) {
            0 => b.site_assets_dir,
            else => b.site_assets_dir.openDir(dir_entry, .{ .iterate = true }) catch |err| {
                fatal.dir(dir_entry, err);
            },
        };
        defer if (dir_entry.len > 0) dir.close();

        var it = dir.iterateAssumeFirstIteration();
        while (it.next() catch |err| fatal.dir(dir_entry, err)) |entry| {
            // We do not ignore hidden files in assets for two reasons:
            // - Users might want to install "hidden" files on purpose
            // - Unlike other directories where one could want to place
            //   a directory that doesn't want Zine to recourse into,
            //   assets is the one place where users are not expected
            //   to put anything that isn't an asset ready to be installed
            //   as needed.
            // if (std.mem.startsWith(u8, entry.name, ".")) continue;
            switch (entry.kind) {
                else => continue,
                .file, .sym_link => {
                    progress.completeOne();

                    const name = try b.st.intern(gpa, entry.name);
                    const asset_sub_path = switch (dir_entry.len) {
                        0 => empty_path,
                        else => try b.pt.internPath(
                            gpa,
                            &b.st,
                            dir_entry,
                        ),
                    };

                    const pn: PathName = .{
                        .path = asset_sub_path,
                        .name = name,
                    };

                    try b.site_assets.putNoClobber(gpa, pn, .init(0));
                },
                .directory => {
                    const path_bytes = try std.fs.path.join(arena, &.{
                        dir_entry,
                        entry.name,
                    });
                    try dir_stack.append(arena, path_bytes);
                },
            }
        }
    }
}

pub fn scanTemplates(b: *Build, gpa: Allocator) !void {
    const zone = tracy.trace(@src());
    defer zone.end();

    const layouts_dir_path = b.cfg.getLayoutsDirPath();

    log.debug("scanTemplates('{s}')", .{layouts_dir_path});
    var progress = root.progress.start("Scan templates", 0);
    defer progress.end();

    var layouts_it = b.layouts_dir.iterateAssumeFirstIteration();
    while (layouts_it.next() catch |err| fatal.dir(layouts_dir_path, err)) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        switch (entry.kind) {
            else => continue,
            .file, .sym_link => {
                if (std.mem.endsWith(u8, entry.name, ".html")) {
                    std.debug.print("WARNING: found plain HTML file {s}{c}{s}, did you mean to give it a shtml extension?\n", .{
                        layouts_dir_path,
                        std.fs.path.sep,
                        entry.name,
                    });
                    continue;
                }
                if (std.mem.endsWith(u8, entry.name, ".shtml") or
                    std.mem.endsWith(u8, entry.name, ".xml"))
                {
                    log.debug("new layout: '{s}'", .{entry.name});
                    progress.completeOne();
                    const str = try b.st.intern(gpa, entry.name);
                    try b.templates.putNoClobber(gpa, .fromString(str, true), .{});
                }
            },
            .directory => {
                if (!std.mem.eql(u8, entry.name, "templates")) {
                    fatal.msg("error: layouts directory should only contain a 'templates' subdirectory but '{s}' was found.\n", .{
                        entry.name,
                    });
                }
            },
        }
    }

    const templates_dir_path = try std.fs.path.join(gpa, &.{
        layouts_dir_path,
        "templates",
    });
    var templates_dir = b.layouts_dir.openDir("templates", .{
        .iterate = true,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            log.debug("could not find template dir, leaving", .{});
            return;
        },
        else => fatal.dir(templates_dir_path, err),
    };
    defer templates_dir.close();

    var templates_it = templates_dir.iterateAssumeFirstIteration();
    while (templates_it.next() catch |err| fatal.dir(layouts_dir_path, err)) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        switch (entry.kind) {
            else => continue,
            .file, .sym_link => {
                if (std.mem.endsWith(u8, entry.name, ".html")) {
                    std.debug.print("WARNING: found plain HTML file {s}{c}{s}, did you mean to give it a shtml extension?\n", .{
                        templates_dir_path,
                        std.fs.path.sep,
                        entry.name,
                    });
                    continue;
                }
                if (std.mem.endsWith(u8, entry.name, ".shtml")) {
                    progress.completeOne();
                    log.debug("new template: '{s}'", .{entry.name});
                    const str = try b.st.intern(gpa, entry.name);
                    try b.templates.putNoClobber(gpa, .fromString(str, false), .{});
                }
            },
            .directory => {
                fatal.msg("error: templates subdirectory should not contain subdirectories but '{s}' was found.\n", .{
                    entry.name,
                });
            },
        }
    }
}
