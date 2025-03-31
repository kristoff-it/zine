const Variant = @This();
const log = std.log.scoped(.variant);

const std = @import("std");
const builtin = @import("builtin");
const ziggy = @import("ziggy");
const tracy = @import("tracy");
const fatal = @import("fatal.zig");
const worker = @import("worker.zig");
const context = @import("context.zig");
const Build = @import("Build.zig");
const StringTable = @import("StringTable.zig");
const PathTable = @import("PathTable.zig");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Page = context.Page;
const FrontParser = ziggy.frontmatter.Parser(Page);
const String = StringTable.String;
const Path = PathTable.Path;
const PathName = PathTable.PathName;

output_path_prefix: []const u8,
/// Open for the full duration of the program.
content_dir: std.fs.Dir,
content_dir_path: []const u8,
/// Stores path components
string_table: StringTable,
/// Stores paths as slices of components (stored in string_table)
path_table: PathTable,
/// Section 0 is invalid, always start iterating from [1..].
sections: std.ArrayListUnmanaged(Section),
root_index: ?u32, // index into pages
pages: std.ArrayListUnmanaged(Page),
/// Output urls for pages, and assets.
/// - Scan phase: adds pages and assets
/// - Main thread after parse phase: adds aliases and alternatives
urls: std.AutoHashMapUnmanaged(PathName, LocationHint),
/// Overflowing LocationHints end up in here, populated alongside 'urls'.
collisions: std.ArrayListUnmanaged(Collision),

i18n: context.Map.ZiggyMap,
i18n_src: [:0]const u8,
i18n_diag: ziggy.Diagnostic,
i18n_arena: std.heap.ArenaAllocator.State,

const Collision = struct {
    url: PathName,
    loc: LocationHint,
    previous: LocationHint,
};

/// Tells you where to look when figuring out what an output URL maps to.
pub const ResourceKind = enum { page_main, page_alias, page_alternative, page_asset };
pub const LocationHint = struct {
    id: u32, // index into pages
    kind: union(ResourceKind) {
        page_main,
        page_alias,
        page_alternative: []const u8,
        // for page assets, 'id' is the page that owns the asset
        page_asset: std.atomic.Value(u32), // reference counting
    },
    pub fn fmt(
        lh: LocationHint,
        st: *const StringTable,
        pt: *const PathTable,
        pages: []const Page,
    ) LocationHint.Formatter {
        return .{ .lh = lh, .st = st, .pt = pt, .pages = pages };
    }

    pub const Formatter = struct {
        lh: LocationHint,
        st: *const StringTable,
        pt: *const PathTable,
        pages: []const Page,

        pub fn format(
            f: LocationHint.Formatter,
            comptime _: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            const page = f.pages[f.lh.id];
            try writer.print("{}", .{page._scan.file.fmt(f.st, f.pt, null)});

            switch (f.lh.kind) {
                .page_main => {
                    try writer.writeAll(" (main output)");
                },
                .page_alias => {
                    try writer.writeAll(" (page alias)");
                },
                .page_alternative => |alt| {
                    try writer.print(" (page alternative '{s}')", .{alt});
                },
                .page_asset => {
                    try writer.writeAll(" (page asset)");
                },
            }
        }
    };
};

pub const Section = struct {
    active: bool = true,
    content_sub_path: Path,
    parent_section: u32, // index into sections, 0 = no parent section
    index: u32, // index into pages
    pages: std.ArrayListUnmanaged(u32) = .empty, // indices into pages

    pub fn deinit(s: *const Section, gpa: Allocator) void {
        {
            var p = s.pages;
            p.deinit(gpa);
        }
    }

    pub fn activate(
        s: *Section,
        gpa: Allocator,
        variant: *const Variant,
        index: *Page,
        drafts: bool,
    ) void {
        const zone = tracy.trace(@src());
        defer zone.end();

        index.parse(gpa, worker.cmark, null, variant, drafts);
        s.active = index._parse.active;
    }

    pub fn sortPages(
        s: *Section,
        pages: []Page,
    ) void {
        const Ctx = struct {
            pages: []Page,
            pub fn lessThan(ctx: @This(), lhs: u32, rhs: u32) bool {
                return ctx.pages[rhs].date.lessThan(ctx.pages[lhs].date);
            }
        };

        const ctx: Ctx = .{ .pages = pages };
        std.sort.insertion(u32, s.pages.items, ctx, Ctx.lessThan);
    }
};

pub fn deinit(v: *const Variant, gpa: Allocator) void {
    {
        var dir = v.content_dir;
        dir.close();
    }
    // content_dir_path is in cfg_arena
    // gpa.free(v.content_dir_path);
    v.string_table.deinit(gpa);
    v.path_table.deinit(gpa);
    for (v.sections.items) |s| s.deinit(gpa);
    {
        var s = v.sections;
        s.deinit(gpa);
    }
    for (v.pages.items) |p| p.deinit(gpa);
    {
        var p = v.pages;
        p.deinit(gpa);
    }
    {
        var u = v.urls;
        u.deinit(gpa);
    }
    {
        var c = v.collisions;
        c.deinit(gpa);
    }
    v.i18n_arena.promote(gpa).deinit();
}

pub const MultilingualScanParams = struct {
    i18n_dir: std.fs.Dir,
    i18n_dir_path: []const u8,
    locale_code: []const u8,
};
pub fn scanContentDir(
    variant: *Variant,
    gpa: Allocator,
    arena: Allocator,
    base_dir: std.fs.Dir,
    content_dir_path: []const u8,
    variant_id: u32,
    multilingual: ?MultilingualScanParams,
    output_path_prefix: []const u8,
) void {
    const zone = tracy.trace(@src());
    defer zone.end();

    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    var path_table: PathTable = .empty;
    _ = try path_table.intern(gpa, &.{}); // empty path
    const empty_path = try path_table.intern(gpa, &.{});
    var string_table: StringTable = .empty;
    _ = try string_table.intern(gpa, ""); // invalid path component string
    const index_smd = try string_table.intern(gpa, "index.smd");
    const index_html = try string_table.intern(gpa, "index.html");
    _ = try string_table.intern(gpa, "index.html");

    var pages: std.ArrayListUnmanaged(Page) = .empty;
    var sections: std.ArrayListUnmanaged(Section) = .empty;
    try sections.append(gpa, undefined); // section zero is invalid

    var urls: std.AutoHashMapUnmanaged(PathName, LocationHint) = .empty;
    var collisions: std.ArrayListUnmanaged(Collision) = .empty;

    var dir_stack: std.ArrayListUnmanaged(struct {
        path: []const u8,
        parent_section: u32, // index into sections
        page_assets_owner: u32, // index into pages
    }) = .empty;
    try dir_stack.append(arena, .{
        .path = "",
        .parent_section = 0,
        .page_assets_owner = 0,
    });

    var root_index: ?u32 = null;
    var page_names: std.ArrayListUnmanaged(String) = .empty;
    var asset_names: std.ArrayListUnmanaged(String) = .empty;
    var dir_names: std.ArrayListUnmanaged(String) = .empty;
    const content_dir = base_dir.openDir(content_dir_path, .{
        .iterate = true,
    }) catch |err| fatal.dir(content_dir_path, err);

    while (dir_stack.pop()) |dir_entry| {
        var dir = switch (dir_entry.path.len) {
            0 => content_dir,
            else => content_dir.openDir(dir_entry.path, .{ .iterate = true }) catch |err| {
                fatal.dir(dir_entry.path, err);
            },
        };
        defer if (dir_entry.path.len > 0) dir.close();

        var found_index_smd = false;
        var it = dir.iterateAssumeFirstIteration();
        while (it.next() catch |err| fatal.dir(dir_entry.path, err)) |entry| {
            if (std.mem.startsWith(u8, entry.name, ".")) continue;
            switch (entry.kind) {
                else => continue,
                .file, .sym_link => {
                    const str = try string_table.intern(gpa, entry.name);
                    if (str == index_html) {
                        @panic("TODO: error reporting for index.html in content section");
                    }
                    if (std.mem.endsWith(u8, entry.name, ".smd")) {
                        if (str == index_smd) {
                            found_index_smd = true;
                            continue;
                        }
                        try page_names.append(arena, str);
                    } else {
                        try asset_names.append(arena, str);
                    }
                },
                .directory => {
                    const str = try string_table.intern(gpa, entry.name);
                    try dir_names.append(arena, str);
                },
            }
        }

        try urls.ensureUnusedCapacity(gpa, @intCast(@intFromBool(found_index_smd) +
            page_names.items.len + asset_names.items.len));

        // TODO: this should be a internPathExtend
        const content_sub_path = switch (dir_entry.path.len) {
            0 => empty_path,
            else => try path_table.internPath(
                gpa,
                &string_table,
                dir_entry.path,
            ),
        };

        // Would be nice to be able to use destructuring...
        var current_section = dir_entry.parent_section;
        const assets_owner_id = if (found_index_smd) blk: {
            const page_id: u32 = @intCast(pages.items.len);
            const is_root_index = dir_entry.path.len == 0;
            if (is_root_index) {
                // root index case
                root_index = page_id;
            } else {
                // Found index.smd: add it to the current section
                // and create a new section to be used for all
                // other files.
                try sections.items[dir_entry.parent_section].pages.append(
                    gpa,
                    page_id,
                );
            }

            current_section = @intCast(sections.items.len);
            try sections.append(gpa, .{
                .content_sub_path = content_sub_path,
                .parent_section = dir_entry.parent_section,
                .index = page_id,
            });

            const index_page = try pages.addOne(gpa);
            index_page._parse.active = false;
            index_page._scan = .{
                .file = .{
                    .path = content_sub_path,
                    .name = index_smd,
                },
                .url = content_sub_path,
                .page_id = page_id,
                .subsection_id = current_section,
                .parent_section_id = dir_entry.parent_section,
                .variant_id = variant_id,
            };
            if (builtin.mode == .Debug) {
                index_page._debug = .{ .stage = .init(.scanned) };
            }

            const pn: PathName = .{ .path = content_sub_path, .name = index_html };
            const lh: LocationHint = .{ .id = page_id, .kind = .page_main };

            const gop = urls.getOrPutAssumeCapacity(pn);
            if (gop.found_existing) {
                try collisions.append(gpa, .{
                    .url = pn,
                    .loc = lh,
                    .previous = gop.value_ptr.*,
                });
            } else {
                gop.value_ptr.* = lh;
            }

            break :blk page_id;
        } else dir_entry.page_assets_owner;

        const section = &sections.items[current_section];
        const section_pages_old_len = section.pages.items.len;
        try section.pages.resize(gpa, section_pages_old_len + page_names.items.len);
        const pages_old_len = pages.items.len;
        try pages.resize(gpa, pages_old_len + page_names.items.len);
        for (
            section.pages.items[section_pages_old_len..],
            pages.items[pages_old_len..],
            page_names.items,
            pages_old_len..,
        ) |*sp, *p, f, idx| {
            // If we don't do this here, later on the call to f.slice might
            // return a pointer that gets invalidated when the string table
            // is expanded.
            try string_table.string_bytes.ensureUnusedCapacity(
                gpa,
                f.slice(&string_table).len + 1,
            );
            const page_url = try path_table.internExtend(
                gpa,
                content_sub_path,
                try string_table.intern(
                    gpa,
                    std.fs.path.stem(f.slice(&string_table)), // TODO: extensionless page names?
                ),
            );

            sp.* = @intCast(idx);
            p._parse.active = false;
            p._scan = .{
                .file = .{
                    .path = content_sub_path,
                    .name = f,
                },
                .url = page_url,
                .page_id = @intCast(idx),
                .subsection_id = 0,
                .parent_section_id = current_section,
                .variant_id = variant_id,
            };
            if (builtin.mode == .Debug) {
                p._debug = .{ .stage = .init(.scanned) };
            }

            log.debug("'{s}/{s}' -> [{d}] -> [{d}]", .{
                dir_entry.path,
                f.slice(&string_table),
                page_url,
                page_url.slice(&path_table),
            });

            const pn: PathName = .{ .path = page_url, .name = index_html };
            const lh: LocationHint = .{ .id = @intCast(idx), .kind = .page_main };
            const gop = urls.getOrPutAssumeCapacity(pn);

            if (gop.found_existing) {
                try collisions.append(gpa, .{
                    .url = pn,
                    .loc = lh,
                    .previous = gop.value_ptr.*,
                });
            } else {
                gop.value_ptr.* = lh;
            }
        }

        // assets
        {
            if (dir_entry.path.len == 0 and !found_index_smd) {
                @panic("TODO: top level assets require an index.smd page");
            }

            const lh: LocationHint = .{
                .id = assets_owner_id,
                .kind = .{ .page_asset = .init(0) },
            };

            for (asset_names.items) |a| {
                const pn: PathName = .{ .path = content_sub_path, .name = a };
                const gop = urls.getOrPutAssumeCapacity(pn);
                if (gop.found_existing) {
                    try collisions.append(gpa, .{
                        .url = pn,
                        .loc = lh,
                        .previous = gop.value_ptr.*,
                    });
                } else {
                    gop.value_ptr.* = lh;
                }
            }
        }

        const dir_stack_old_len = dir_stack.items.len;
        try dir_stack.resize(arena, dir_stack_old_len + dir_names.items.len);
        for (dir_stack.items[dir_stack_old_len..], dir_names.items) |*d, f| {
            const dir_path_bytes = try std.fs.path.join(arena, &.{
                dir_entry.path,
                f.slice(&string_table),
            });
            const dir_path = try path_table.internPath(gpa, &string_table, dir_path_bytes);
            const pn: PathName = .{ .path = dir_path, .name = index_html };
            d.* = .{
                .path = dir_path_bytes,
                .parent_section = current_section,
                .page_assets_owner = if (urls.get(pn)) |hint| hint.id else assets_owner_id,
            };
        }

        page_names.clearRetainingCapacity();
        asset_names.clearRetainingCapacity();
        dir_names.clearRetainingCapacity();
    }

    var i18n: context.Map.ZiggyMap = .{};
    var i18n_src: [:0]const u8 = "";
    var i18n_diag: ziggy.Diagnostic = .{ .path = null };
    var i18n_arena = std.heap.ArenaAllocator.init(gpa);
    // Present when in a multilingual site
    if (multilingual) |ml| {
        const name = try std.fmt.allocPrint(
            i18n_arena.allocator(),
            "{s}.ziggy",
            .{ml.locale_code},
        );
        i18n_src = ml.i18n_dir.readFileAllocOptions(
            i18n_arena.allocator(),
            name,
            ziggy.max_size,
            0,
            1,
            0,
        ) catch |err| fatal.file(name, err);

        i18n_diag.path = name;
        i18n = ziggy.parseLeaky(
            context.Map.ZiggyMap,
            i18n_arena.allocator(),
            i18n_src,
            .{ .diagnostic = &i18n_diag },
        ) catch |err| switch (err) {
            error.OpenFrontmatter, error.MissingFrontmatter => unreachable,
            error.Overflow, error.OutOfMemory => return error.OutOfMemory,
            error.Syntax => .{
                // We will detect later that an error happened by looking
                // at the diagnostic struct.
            },
        };
    }

    variant.* = .{
        .output_path_prefix = output_path_prefix,
        .content_dir = content_dir,
        .content_dir_path = content_dir_path,
        .string_table = string_table,
        .path_table = path_table,
        .sections = sections,
        .root_index = root_index,
        .pages = pages,
        .urls = urls,
        .collisions = collisions,
        .i18n = i18n,
        .i18n_src = i18n_src,
        .i18n_diag = i18n_diag,
        .i18n_arena = i18n_arena.state,
    };
}

pub fn installAssets(
    v: *const Variant,
    progress: std.Progress.Node,
    install_dir: std.fs.Dir,
) void {
    const zone = tracy.trace(@src());
    defer zone.end();

    // errdefer |err| switch (err) {
    //     error.OutOfMemory => fatal.oom(),
    // };

    var it = v.urls.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const hint = entry.value_ptr.*;
        if (hint.kind != .page_asset) continue;
        if (hint.kind.page_asset.raw == 0) continue;

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "{}", .{key.fmt(
            &v.string_table,
            &v.path_table,
            null,
        )}) catch unreachable;

        _ = v.content_dir.updateFile(
            path,
            install_dir,
            path,
            .{},
        ) catch |err| fatal.file(path, err);

        progress.completeOne();
    }
}
