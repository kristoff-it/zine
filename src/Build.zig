const Build = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const tracy = @import("tracy");
const ziggy = @import("ziggy");
const fatal = @import("fatal.zig");
const context = @import("context.zig");
const Variant = @import("Variant.zig");
const Template = @import("Template.zig");
const PathTable = @import("PathTable.zig");
const StringTable = @import("StringTable.zig");
const root = @import("root.zig");
const BuildAsset = root.BuildAsset;
const Path = PathTable.Path;
const String = StringTable.String;
const PathName = PathTable.PathName;

const Git = @import("Git.zig");

const log = std.log.scoped(.build);
const cache_dir_basename = ".zine-cache";

cfg: *const root.Config,
build_assets: *const std.StringArrayHashMapUnmanaged(BuildAsset),
any_prerendering_error: bool = false,
any_rendering_error: std.atomic.Value(bool) = .{ .raw = false },

base_dir_path: []const u8,
base_dir: Io.Dir,
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
layouts_dir: Io.Dir,
templates: Templates = .{},
site_assets_dir: Io.Dir,
site_assets: Assets = .empty,
i18n_dir: Io.Dir,
// Translation key map. Each entry is a slice with the same length as the
// number of variants.
tks: std.StringHashMapUnmanaged([]?*context.Page) = .empty,
mode: Mode,

pub const Mode = union(enum) {
    memory: struct {
        // Errors that don't already have a natural storage location
        // (eg page errors are stored in the page itself)
        errors: std.ArrayListUnmanaged(Error) = .empty,
    },
    disk: struct {
        output_dir: Io.Dir,
    },

    const Error = struct {
        ref: []const u8, // the file this error relates to
        msg: []const u8,
    };
};

pub const Assets = std.AutoArrayHashMapUnmanaged(PathName, std.atomic.Value(u32));
pub const Templates = std.AutoArrayHashMapUnmanaged(PathName, Template);

pub fn deinit(b: *const Build, io: Io, gpa: Allocator) void {
    {
        var dir = b.base_dir;
        dir.close(io);
    }
    b.st.deinit(gpa);
    b.pt.deinit(gpa);
    for (b.variants) |v| v.deinit(io, gpa);
    gpa.free(b.variants);
    {
        var dir = b.layouts_dir;
        dir.close(io);
    }
    for (b.templates.entries.items(.value)) |t| t.deinit(gpa);
    {
        var ts = b.templates;
        ts.deinit(gpa);
    }
    {
        var dir = b.site_assets_dir;
        dir.close(io);
    }
    switch (b.mode) {
        .memory => {},
        .disk => |disk| {
            var dir = disk.output_dir;
            dir.close(io);
        },
    }

    if (b.cfg.site == .multilingual) {
        var dir = b.i18n_dir;
        dir.close(io);
    }
}

/// Tries to load a zine.ziggy config file by searching
/// recursivly upwards from cwd. Once the config file is found,
/// it ensures the existence of all required directories and
/// loads git repository info (if in a repo).
pub fn load(io: Io, gpa: Allocator, cfg: *const root.Config, opts: root.Options) Build {
    const base_dir = Io.Dir.cwd().openDir(
        io,
        opts.base_dir_path,
        .{},
    ) catch |err|
        fatal.dir(opts.base_dir_path, err);

    const layouts_dir = base_dir.createDirPathOpen(
        io,
        cfg.getLayoutsDirPath(),
        .{ .open_options = .{ .iterate = true } },
    ) catch |err| fatal.dir(cfg.getLayoutsDirPath(), err);

    const assets_dir = base_dir.createDirPathOpen(
        io,
        cfg.getAssetsDirPath(),
        .{ .open_options = .{ .iterate = true } },
    ) catch |err| fatal.dir(cfg.getAssetsDirPath(), err);

    var table: StringTable = .empty;
    _ = table.intern(gpa, "") catch fatal.oom();

    var path_table: PathTable = .empty;
    _ = path_table.intern(gpa, &.{}) catch fatal.oom();

    const mode: Mode = switch (opts.mode) {
        .memory => .{ .memory = .{} },
        .disk => |disk| blk: {
            const output_base_dir = if (disk.output_dir_path == null)
                base_dir
            else
                Io.Dir.cwd();
            const output_dir = output_base_dir.createDirPathOpen(
                io,
                disk.output_dir_path orelse "public",
                .{ .open_options = .{ .iterate = true } },
            ) catch |err| fatal.dir(
                disk.output_dir_path orelse "public",
                err,
            );

            if (disk.check_empty_output) ensureEmpty(
                io,
                output_dir,
                disk.output_dir_path orelse "public",
            );

            break :blk .{ .disk = .{ .output_dir = output_dir } };
        },
    };

    const i18n_dir = switch (cfg.site) {
        .simple => undefined,
        .multilingual => |ml| base_dir.createDirPathOpen(
            io,
            ml.i18n_dir_path,
            .{ .open_options = .{ .iterate = true } },
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

fn ensureEmpty(io: Io, dir: Io.Dir, path: []const u8) void {
    var it = dir.iterateAssumeFirstIteration();
    const next = it.next(io) catch |err| fatal.dir(path, err);
    if (next != null) {
        fatal.msg(
            \\error: the output directory is not empty
            \\
            \\info: the output path:
            \\      {s}
            \\
            \\note: use `-f` or `--force` to output a release in
            \\      a non-empty directory, but be aware that old 
            \\      files will **NOT** be removed!
            \\
            \\
        , .{path});
    }
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
/// Maps directories to a list of all files they contain in their subtree.
/// Indexes into `b.site_assets`. Uses arena allocator, meant to be discarded after use.
pub const AssetDirMap = std.StringArrayHashMapUnmanaged(FileSpan);
pub const FileSpan = struct {
    start: usize,
    end: usize,
    last_for: usize,
};
pub fn scanSiteAssets(
    b: *Build,
    io: Io,
    gpa: Allocator,
    arena: Allocator,
) !AssetDirMap {
    const zone = tracy.trace(@src());
    defer zone.end();

    var dir_map: AssetDirMap = .empty;
    var dir_stack: std.ArrayList(struct { name: []const u8, map_idx: usize }) = .empty;

    try dir_map.putNoClobber(arena, "", .{ .start = 0, .end = undefined, .last_for = 0 });
    try dir_stack.append(arena, .{ .name = "", .map_idx = 0 });
    defer dir_map.values()[0].end = b.site_assets.entries.len;

    const empty_path: Path = @enumFromInt(0);
    assert(b.pt.get(&.{}) == empty_path);

    var progress = root.progress.start("Scan templates", 0);
    defer progress.end();

    while (dir_stack.pop()) |dir_entry| {
        var dir = switch (dir_entry.name.len) {
            0 => b.site_assets_dir,
            else => blk: {
                const dir_map_val = &dir_map.values()[dir_entry.map_idx];
                dir_map_val.start = b.site_assets.entries.len;
                break :blk b.site_assets_dir.openDir(io, dir_entry.name, .{ .iterate = true }) catch |err| {
                    fatal.dir(dir_entry.name, err);
                };
            },
        };
        defer if (dir_entry.name.len > 0) dir.close(io);

        var first_subdir: ?[]const u8 = null;
        const first_dir_slot = dir_stack.items.len;

        var it = dir.iterateAssumeFirstIteration();
        while (it.next(io) catch |err| fatal.dir(dir_entry.name, err)) |entry| {
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
                    const asset_sub_path = switch (dir_entry.name.len) {
                        0 => empty_path,
                        else => try b.pt.internPath(
                            gpa,
                            &b.st,
                            dir_entry.name,
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
                        dir_entry.name,
                        entry.name,
                    });

                    if (first_subdir == null) {
                        first_subdir = path_bytes;
                        try dir_stack.append(arena, .{
                            .name = path_bytes,
                            .map_idx = undefined,
                        });
                    } else {
                        try dir_stack.append(arena, .{
                            .name = path_bytes,
                            .map_idx = dir_map.entries.len,
                        });
                        try dir_map.putNoClobber(arena, path_bytes, .{
                            .start = undefined,
                            .end = undefined,
                            .last_for = 0,
                        });
                    }
                },
            }
        }

        if (first_subdir) |path_bytes| {
            dir_stack.items[first_dir_slot].map_idx = dir_map.entries.len;
            try dir_map.putNoClobber(arena, path_bytes, .{
                .start = undefined,
                .end = undefined,
                .last_for = dir_entry.map_idx,
            });
        } else {
            var last_for = dir_entry.map_idx;
            while (last_for != 0) {
                const dir_map_val = &dir_map.values()[last_for];
                dir_map_val.end = b.site_assets.entries.len;
                last_for = dir_map_val.last_for;
            }
        }
    }
    return dir_map;
}

pub fn scanTemplates(b: *Build, io: Io, gpa: Allocator, arena: Allocator) !void {
    const zone = tracy.trace(@src());
    defer zone.end();
    var progress = root.progress.start("Scan templates", 0);
    defer progress.end();

    const layouts_dir_path = b.cfg.getLayoutsDirPath();
    log.debug("scanTemplates('{s}')", .{layouts_dir_path});

    var dir_stack: std.ArrayListUnmanaged(struct {
        p: Path,
        path: []const u8,
        templates: bool,
    }) = .empty;
    try dir_stack.append(arena, .{
        .p = @enumFromInt(0),
        .path = "",
        .templates = false,
    });

    while (dir_stack.pop()) |dir_entry| {
        var dir = if (dir_entry.path.len == 0) b.layouts_dir else b.layouts_dir.openDir(
            io,
            dir_entry.path,
            .{ .iterate = true },
        ) catch |err| fatal.dir(dir_entry.path, err);
        defer if (dir_entry.path.len > 0) dir.close(io);

        var dir_it = dir.iterateAssumeFirstIteration();
        while (dir_it.next(io) catch |err| fatal.dir(dir_entry.path, err)) |entry| {
            if (std.mem.startsWith(u8, entry.name, ".")) continue;
            switch (entry.kind) {
                else => continue,
                .file, .sym_link => {
                    if (std.mem.endsWith(u8, entry.name, ".html")) {
                        std.debug.print("WARNING: found plain HTML file {f}, did you mean to give it a shtml extension?\n", .{
                            root.fmtJoin('/', &.{
                                layouts_dir_path,
                                dir_entry.path,
                                entry.name,
                            }),
                        });
                        continue;
                    }
                    if (std.mem.endsWith(u8, entry.name, ".shtml") or
                        std.mem.endsWith(u8, entry.name, ".xml"))
                    {
                        log.debug("new layout: '{s}'", .{entry.name});
                        progress.completeOne();

                        const str = try b.st.intern(gpa, entry.name);
                        const pn: PathName = .{
                            .path = dir_entry.p,
                            .name = str,
                        };

                        try b.templates.putNoClobber(gpa, pn, .{
                            .layout = !dir_entry.templates,
                        });
                    }
                },
                .directory => {
                    try dir_stack.append(arena, .{
                        .path = try root.join(arena, &.{ dir_entry.path, entry.name }, '/'),
                        .templates = dir_entry.templates or (dir_entry.path.len == 0 and
                            std.mem.eql(u8, entry.name, "templates")),
                        .p = try b.pt.internExtend(
                            gpa,
                            dir_entry.p,
                            try b.st.intern(gpa, entry.name),
                        ),
                    });
                },
            }
        }
    }
}
