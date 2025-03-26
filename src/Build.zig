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
const Path = PathTable.Path;
const String = StringTable.String;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Git = @import("Git.zig");

const log = std.log.scoped(.build);
const config_file_basename = "zine.ziggy";
const cache_dir_basename = ".zine-cache";

cfg: Config,
cfg_arena: std.heap.ArenaAllocator.State,
cli: CliOptions,
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
install_dir: std.fs.Dir,

pub const Assets = std.AutoArrayHashMapUnmanaged(PathName, std.atomic.Value(u32));
pub const Templates = std.AutoArrayHashMapUnmanaged(Template.TaggedName, Template);

const Config = union(enum) {
    Multilingual: MultilingualSite,
    Site: Site,

    pub fn getLayoutsDirPath(c: *const Config) []const u8 {
        return switch (c.*) {
            .Site => |s| s.layouts_dir_path,
            .Multilingual => |m| m.layouts_dir_path,
        };
    }
    pub fn getAssetsDirPath(c: *const Config) []const u8 {
        return switch (c.*) {
            .Site => |s| s.assets_dir_path,
            .Multilingual => |m| m.assets_dir_path,
        };
    }

    pub fn getStaticAssets(c: *const Config) []const []const u8 {
        return switch (c.*) {
            .Site => |s| s.static_assets,
            .Multilingual => |m| m.static_assets,
        };
    }

    pub fn getSiteTitle(c: *const Config, locale_id: u32) []const u8 {
        return switch (c.*) {
            .Site => |s| s.title,
            .Multilingual => |m| m.locales[locale_id].site_title,
        };
    }

    pub fn getHostUrl(c: *const Config, locale_id: ?u32) []const u8 {
        return switch (c.*) {
            .Site => |s| s.host_url,
            .Multilingual => |m| if (locale_id) |lid| m.locales[lid].host_url_override orelse m.host_url else m.host_url,
        };
    }
};

pub const Site = struct {
    /// Title of the website
    title: []const u8,
    /// URL where the website will be hosted.
    /// It must not contain a subpath.
    host_url: []const u8,
    /// Set this value if your website is hosted under a subpath of `host_url`.
    ///
    /// `host_url` and `url_prefix_path` are split to allow the development
    /// server to generate correct relative paths when serving the website
    /// locally.
    url_path_prefix: ?[]const u8 = null,
    /// If you want your site to be placed in a subdirectory of the output
    /// directory.
    /// Zig Build's output directory is `zig-out` by default, customizable
    /// by passing `-p path` to the build command invocation.
    output_path_prefix: []const u8 = "",
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    assets_dir_path: []const u8,
    /// Subpaths in `assets_dir_path` that will be installed unconditionally.
    /// All other assets will be installed only if referenced by a content file
    /// or a layout by calling `$site.asset('foo').link()`.
    ///
    /// Examples of incorrect usage of this field:
    /// - site-wide CSS files (should be `link`ed by templates)
    /// - RSS feeds (should be generated by defining `alternative` pages)
    ///
    /// Examples of correct usage of this field:
    /// - `favicon.ico` and other similar assets auto-discovered by browsers
    /// - `CNAME` (used by GitHub Pages when you set a custom domain)
    static_assets: []const []const u8 = &.{},
};

pub const MultilingualSite = struct {
    /// URL where the website will be hosted.
    /// It must not contain a path other than `/`.
    host_url: []const u8,
    /// Directory that contains mappings from placeholders to translations,
    /// expressed as Ziggy files.
    ///
    /// Each Ziggy file must be named after the locale it's meant to offer
    /// translations for.
    i18n_dir_path: []const u8,
    layouts_dir_path: []const u8,
    assets_dir_path: []const u8,
    /// Location where site and build assets will be installed. By default
    /// assets will be installed directly in the output location.
    ///
    /// In mulitilingual websites Zine will create a single copy of site
    /// assets which will then be installed at this location. It will be your
    /// duty to then copy this directory elsewhere if needed in your deployment
    /// setup (e.g. when deploying different localized variants to different
    /// hosts). Note that *page* assets will still be installed next to their
    /// relative page.
    assets_prefix_path: []const u8 = "",
    /// Subpaths in `assets_dir_path` that will be installed unconditionally.
    /// All other assets will be installed only if referenced by a content file
    /// or a layout by using `$site.asset('foo').link()`.
    ///
    /// Examples of incorrect usage of this field:
    /// - site-wide CSS files (should be `link`ed by templates)
    /// - RSS feeds (should be generated by defining `alternative` pages)
    ///
    /// Examples of correct usage of this field:
    /// - `favicon.ico` and other similar assets auto-discovered by browsers
    /// - `CNAME` (used by GitHub Pages when you set a custom domain)
    static_assets: []const []const u8 = &.{},
    /// A list of locales of this website.
    ///
    /// For each entry the following values must be unique:
    ///   - `code`
    ///   - `output_prefix_override` (if set) + `host_url_override`
    locales: []const Locale,
};

/// A localized variant of a multilingual website
pub const Locale = struct {
    /// A language-NATION code, e.g. 'en-US', used to identify each
    /// individual localized variant of the website.
    code: []const u8,
    /// A name that identifies this locale, e.g. 'English'
    name: []const u8,
    /// Content dir for this locale,
    content_dir_path: []const u8,
    /// Site title for this locale.
    site_title: []const u8,
    /// Set to a non-null value when deploying this locale from a dedicated
    /// host (e.g. 'https://us.site.com', 'http://de.site.com').
    ///
    /// It must not contain a subpath.
    host_url_override: ?[]const u8 = null,
    /// |  output_ |     host_     |     resulting    |    resulting    |
    /// |  prefix_ |      url_     |        url       |      path       |
    /// | override |   override    |      prefix      |     prefix      |
    /// | -------- | ------------- | ---------------- | --------------- |
    /// |   null   |      null     | site.com/en-US/  | zig-out/en-US/  |
    /// |   null   | "us.site.com" | us.site.com/     | zig-out/en-US/  |
    /// |   "foo"  |      null     | site.com/foo/    | zig-out/foo/    |
    /// |   "foo"  | "us.site.com" | us.site.com/foo/ | zig-out/foo/    |
    /// |    ""    |      null     | site.com/        | zig-out/        |
    ///
    /// The last case is how you create a default locale.
    output_prefix_override: ?[]const u8 = null,
};

// Mirrors closely the corresponding type in build.zig
pub const BuildAsset = struct {
    input_path: []const u8,
    install_path: ?[]const u8 = null,
    install_always: bool = false,
    rc: std.atomic.Value(u32),
};

pub const CliOptions = struct {
    output_dir_path: ?[]const u8 = null,
    build_assets: std.StringArrayHashMapUnmanaged(BuildAsset),

    pub fn deinit(co: *const CliOptions, gpa: Allocator) void {
        var ba = co.build_assets;
        ba.deinit(gpa);
    }

    pub fn parse(gpa: Allocator, args: []const []const u8) !CliOptions {
        var output_dir_path: ?[]const u8 = null;
        var build_assets: std.StringArrayHashMapUnmanaged(BuildAsset) = .empty;

        const eql = std.mem.eql;
        const startsWith = std.mem.startsWith;
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const a = args[idx];
            if (eql(u8, a, "-h") or eql(u8, a, "--help")) {
                @import("main.zig").fatalHelp();
                continue;
            }

            if (eql(u8, a, "-o") or eql(u8, a, "--output")) {
                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing argument to '{s}'",
                    .{a},
                );
                output_dir_path = args[idx];
                continue;
            }
            if (startsWith(u8, a, "--output=")) {
                output_dir_path = a["--output=".len..];
                continue;
            }

            if (startsWith(u8, a, "--build-asset=")) {
                const name = a["--build-asset=".len..];

                idx += 1;
                if (idx >= args.len) fatal.msg(
                    "error: missing build asset sub-argument for '{s}'",
                    .{name},
                );

                const input_path = args[idx];

                idx += 1;
                var install_path: ?[]const u8 = null;
                var install_always = false;
                if (idx < args.len) {
                    const next = args[idx];
                    if (startsWith(u8, next, "--install=")) {
                        install_path = next["--install=".len..];
                    } else if (startsWith(u8, next, "--install-always=")) {
                        install_always = true;
                        install_path = next["--install-always=".len..];
                    } else {
                        idx -= 1;
                    }
                }

                const gop = try build_assets.getOrPut(gpa, name);
                if (gop.found_existing) fatal.msg(
                    "error: duplicate build asset name '{s}'",
                    .{name},
                );

                gop.value_ptr.* = .{
                    .input_path = input_path,
                    .install_path = install_path,
                    .install_always = install_always,
                    .rc = .{ .raw = @intFromBool(install_always) },
                };
                continue;
            }

            fatal.msg("error: unexpected cli argument '{s}'\n", .{a});
        }

        return .{
            .output_dir_path = output_dir_path,
            .build_assets = build_assets,
        };
    }
};

pub fn deinit(b: *const Build, gpa: Allocator) void {
    b.cfg_arena.promote(gpa).deinit();
    b.cli.deinit(gpa);
    gpa.free(b.base_dir_path);
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
    {
        var dir = b.install_dir;
        dir.close();
    }

    if (b.cfg == .Multilingual) {
        var dir = b.i18n_dir;
        dir.close();
    }
}

/// Tries to load a zine.ziggy config file by searching
/// recursivly upwards from cwd. Once the config file is found,
/// it ensures the existence of all required directories and
/// loads git repository info (if in a repo).
pub fn load(gpa: Allocator, arena: Allocator, args: []const []const u8) Build {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const cli: CliOptions = try .parse(gpa, args);

    const cwd_path = std.process.getCwdAlloc(arena) catch |err| {
        fatal.msg("error while trying to get the cwd path: {s}\n", .{
            @errorName(err),
        });
    };

    var cfg_arena = std.heap.ArenaAllocator.init(gpa);
    var base_dir_path: []const u8 = cwd_path;
    while (true) {
        const joined_path = try std.fs.path.join(arena, &.{
            base_dir_path, config_file_basename,
        });

        const data = std.fs.cwd().readFileAllocOptions(
            cfg_arena.allocator(),
            joined_path,
            1024 * 1024,
            null,
            1,
            0,
        ) catch |err| switch (err) {
            error.FileNotFound => {
                base_dir_path = std.fs.path.dirname(base_dir_path) orelse {
                    fatal.msg(
                        \\Unable to find a 'zine.ziggy' config file in this directory or any of its parents.
                        \\
                        \\TODO: implement `zine init` and suggest its usage here
                        \\
                    , .{});
                };
                continue;
            },
            else => fatal.file(joined_path, err),
        };

        var diag: ziggy.Diagnostic = .{ .path = joined_path };
        const cfg = ziggy.parseLeaky(Build.Config, cfg_arena.allocator(), data, .{
            .diagnostic = &diag,
            .copy_strings = .to_unescape,
        }) catch {
            fatal.msg(
                \\Error while loading the Zine config file:
                \\
                \\{}
                \\
                \\
            , .{diag.fmt(data)});
        };

        const base_dir = std.fs.cwd().openDir(
            base_dir_path,
            .{},
        ) catch |err|
            fatal.dir(base_dir_path, err);

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

        const install_base_dir = if (cli.output_dir_path == null) base_dir else std.fs.cwd();
        const install_dir = install_base_dir.makeOpenPath(
            cli.output_dir_path orelse "public",
            .{},
        ) catch |err| fatal.dir(cli.output_dir_path orelse "public", err);

        const i18n_dir = switch (cfg) {
            .Site => undefined,
            .Multilingual => |ml| base_dir.makeOpenPath(
                ml.i18n_dir_path,
                .{},
            ) catch |err| fatal.dir(ml.i18n_dir_path, err),
        };

        return .{
            .cfg = cfg,
            .cfg_arena = cfg_arena.state,
            .cli = cli,
            .base_dir = base_dir,
            .base_dir_path = try gpa.dupe(u8, base_dir_path),
            .layouts_dir = layouts_dir,
            .site_assets_dir = assets_dir,
            .st = table,
            .pt = path_table,
            .install_dir = install_dir,
            .i18n_dir = i18n_dir,
        };
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
