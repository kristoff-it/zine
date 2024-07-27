const zine = @This();
const std = @import("std");

// This file only contains definitions that might be
// of interest to advanced Zine users, Zine's main
// build function is in another castle!
pub const build = @import("build/tools.zig").build;

pub const Site = struct {
    title: []const u8,
    host_url: []const u8,
    layouts_dir_path: []const u8,
    content_dir_path: []const u8,
    static_dir_path: []const u8,
    output_prefix: []const u8 = "",

    /// Enables Zine's -Ddebug and -Dscope flags
    /// (only useful if you're developing Zine)
    debug: bool = false,
};

pub const MultilingualSite = struct {
    host_url: []const u8,
    layouts_dir_path: []const u8,
    static_dir_path: []const u8,
    i18n_dir_path: []const u8,
    variants: []const LocalizedVariant,

    /// Enables Zine's -Ddebug and -Dscope flags
    /// (only useful if you're developing Zine)
    debug: bool = false,

    pub const LocalizedVariant = struct {
        ///A language-NATION code, e.g. 'en-US'.
        locale_code: []const u8,
        ///Content dir for this localized variant.
        content_dir_path: []const u8,
        ///Site title for this localized variant.
        title: []const u8,
        ///Set to a non-null value when deploying this variant from a
        ///dedicated host (e.g. 'https://us.site.com', 'http://de.site.com').
        host_url_override: ?[]const u8 = null,
        /// |  output_ |     host_     |     resulting    |      output     |
        /// |  prefix_ |      url_     |        url       |       path      |
        /// | override |   override    |      prefix      |      prefix     |
        /// | -------- | ------------- | ---------------- | --------------- |
        /// |   null   |      null     | site.com/en-US/  | zig-out/en-US/  |
        /// |   null   | "us.site.com" | us.site.com/     | zig-out/en-US/  |
        /// |   "foo"  |      null     | site.com/foo/    | zig-out/foo/    |
        /// |   "foo"  | "us.site.com" | us.site.com/foo/ | zig-out/foo/    |
        /// |    ""    |      null     | site.com/        | zig-out/        |
        ///
        /// The last case is how you create a default localized variant.
        output_prefix_override: ?[]const u8 = null,
    };
};

/// Defines a default Zine project:
/// - Creates a 'website' step that will generate all the static content and
///   install it in the prefix directory.
/// - Creates a 'serve' step that depends on 'website' and that also starts
///   Zine's development server on a default address (localhost:1990).
/// - Defines custom flags:
///   - `-Dport` to override the port used by the development server
/// - Sets other default Zine options
///
/// Look at the implementation of this function to see how you can use
/// `addWebsiteStep` and `addDevelopmentServerStep` for more fine-grained
/// control over the pipeline.
pub fn website(b: *std.Build, site: Site) void {
    // Setup debug flags if the user enabled Zine debug.
    const opts = zine.defaultZineOptions(b, site.debug);

    const website_step = b.step(
        "website",
        "Builds the website",
    );
    zine.addWebsite(b, opts, website_step, site);

    // Invoking the default step also builds the website
    b.getInstallStep().dependOn(website_step);

    const serve = b.step(
        "serve",
        "Starts the Zine development server",
    );

    const port = b.option(
        u16,
        "port",
        "port to listen on for the development server",
    ) orelse 1990;

    zine.addDevelopmentServer(b, opts, serve, .{
        .host = "localhost",
        .port = port,
        .input_dirs = &.{
            site.static_dir_path,
            site.layouts_dir_path,
            site.content_dir_path,
        },
    });

    // Build the website once before starting the web server
    serve.dependOn(b.getInstallStep());
}

/// Defines a default multilingual Zine project:
/// - Creates a 'website' step that will generate all the static content and
///   install it in the prefix directory.
/// - Creates a 'serve' step that depends on 'website' and that also starts
///   Zine's development server on a default address (localhost:1990).
/// - Defines custom flags:
///   - `-Dport` to override the port used by the development server
/// - Sets other default Zine options
///
/// Look at the implementation of this function to see how you can use
/// `addMultilingualWebsiteStep` and `addDevelopmentServerStep` for more
/// fine-grained control over the pipeline.
pub fn multilingualWebsite(b: *std.Build, multi: MultilingualSite) void {
    // Setup debug flags if the user enabled Zine debug.
    const opts = zine.defaultZineOptions(b, multi.debug);

    const website_step = b.step(
        "website",
        "Builds the website",
    );
    zine.addMultilingualWebsite(b, website_step, multi, opts);

    // Invoking the default step also builds the website
    b.getInstallStep().dependOn(website_step);

    const serve = b.step(
        "serve",
        "Starts the Zine development server",
    );

    const port = b.option(
        u16,
        "port",
        "port to listen on for the development server",
    ) orelse 1990;

    var input_dirs = std.ArrayList.init(b.allocator);
    input_dirs.appendSlice(&.{
        multi.static_dir_path,
        multi.layouts_dir_path,
    });

    for (multi.variants) |v| {
        if (v.host_url_override) |_| {
            @panic("TODO: a variant specifies a dedicated host but multihost support for the dev server has not been implemented yet.");
        }
        input_dirs.append(v.content_dir_path) catch unreachable;
    }

    zine.addDevelopmentServer(b, opts, serve, .{
        .host = "localhost",
        .port = port,
        .input_dirs = input_dirs.items,
    });

    // Build the website once before starting the web server
    serve.dependOn(b.getInstallStep());
}

pub fn addWebsite(
    b: *std.Build,
    opts: ZineOptions,
    step: *std.Build.Step,
    site: Site,
) void {
    @import("build/content.zig").addWebsiteImpl(
        b,
        opts,
        step,
        .{ .site = site },
    );
}
pub fn addMultilingualWebsite(
    b: *std.Build,
    step: *std.Build.Step,
    multi: MultilingualSite,
    opts: ZineOptions,
) void {
    @import("build/content.zig").addWebsiteImpl(
        b,
        opts,
        step,
        .{ .multilingual = multi },
    );
}

pub const DevelopmentServerOptions = struct {
    host: []const u8,
    port: u16 = 1990,
    input_dirs: []const []const u8,
};
pub fn addDevelopmentServer(
    b: *std.Build,
    zine_opts: ZineOptions,
    step: *std.Build.Step,
    server_opts: DevelopmentServerOptions,
) void {
    const zine_dep = b.dependencyFromBuildZig(zine, .{
        .optimize = zine_opts.optimize,
        .scope = zine_opts.scopes,
    });
    const server_exe = zine_dep.artifact("server");
    const run_server = b.addRunArtifact(server_exe);
    run_server.addArg("serve");
    run_server.addArg(b.graph.zig_exe);
    run_server.addArgs(&.{ "--root", b.install_path });

    run_server.addArgs(&.{ "-p", b.fmt("{d}", .{server_opts.port}) });

    for (server_opts.input_dirs) |dir| {
        run_server.addArgs(&.{ "--input-dir", dir });
    }

    step.dependOn(&run_server.step);
}

pub const ZineOptions = struct {
    optimize: std.builtin.OptimizeMode = .ReleaseFast,
    /// Logging scopes to enable, mainly useful
    /// when building in debug mode to develop Zine.
    scopes: []const []const u8 = &.{},
};
fn defaultZineOptions(b: *std.Build, debug: bool) ZineOptions {
    var flags: ZineOptions = .{};
    if (debug) {
        flags.optimize = if (b.option(
            bool,
            "debug",
            "build Zine tools in debug mode",
        ) orelse false) .Debug else .ReleaseFast;
        flags.scopes = b.option(
            []const []const u8,
            "scope",
            "logging scopes to enable",
        ) orelse &.{};
    }
    return flags;
}

pub fn scriptyReferenceDocs(
    project: *std.Build,
    output_file_path: []const u8,
) void {
    const zine_dep = project.dependencyFromBuildZig(
        zine,
        .{ .optimize = .Debug },
    );

    const run_docgen = project.addRunArtifact(zine_dep.artifact("docgen"));
    const reference_md = run_docgen.addOutputFileArg("scripty_reference.md");

    const wf = project.addWriteFiles();
    wf.addCopyFileToSource(reference_md, output_file_path);

    const desc = project.fmt("Regenerates Scripty reference docs in '{s}'", .{output_file_path});
    const run_step = project.step("docgen", desc);
    run_step.dependOn(&wf.step);
}
