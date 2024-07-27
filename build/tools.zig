const std = @import("std");

const templating = @import("templating.zig");
const content = @import("content.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scopes: []const []const u8 = b.option(
        []const []const u8,
        "scope",
        "logging scopes to enable",
    ) orelse &.{};

    const mode = .{ .target = target, .optimize = optimize };

    const options = blk: {
        const options = b.addOptions();
        const out = options.contents.writer();
        try out.writeAll(
            \\// module = zine
            \\const std = @import("std");
            \\pub const log_scope_levels: []const std.log.ScopeLevel = &.{
            \\
        );
        for (scopes) |l| try out.print(
            \\.{{.scope = .{s}, .level = .debug}},
        , std.zig.fmtId(l));
        try out.writeAll("};");
        break :blk options.createModule();
    };

    // dummy comment
    const super = b.dependency("superhtml", mode);
    const scripty = super.builder.dependency("scripty", .{});
    const ziggy = b.dependency("ziggy", mode);
    const zeit = b.dependency("zeit", mode);
    const syntax = b.dependency("flow-syntax", mode);
    const ts = syntax.builder.dependency("tree-sitter", mode);

    const zine = b.addModule("zine", .{
        .root_source_file = b.path("src/root.zig"),
    });
    zine.addImport("ziggy", ziggy.module("ziggy"));
    zine.addImport("zeit", zeit.module("zeit"));
    zine.addImport("syntax", syntax.module("syntax"));
    zine.addImport("scripty", scripty.module("scripty"));
    zine.addImport("treez", ts.module("treez"));
    zine.addImport("superhtml", super.module("superhtml"));

    setupServer(b, options, target, optimize);

    const layout = b.addExecutable(.{
        .name = "layout",
        .root_source_file = b.path("src/exes/layout.zig"),
        .target = target,
        .optimize = optimize,
        // .strip = true,

    });

    layout.root_module.addImport("zine", zine);
    layout.root_module.addImport("options", options);
    layout.root_module.addImport("superhtml", super.module("superhtml"));
    layout.root_module.addImport("scripty", scripty.module("scripty"));
    layout.root_module.addImport("ziggy", ziggy.module("ziggy"));
    layout.root_module.addImport("zeit", zeit.module("zeit"));
    layout.root_module.addImport("syntax", syntax.module("syntax"));
    layout.root_module.addImport("treez", ts.module("treez"));
    layout.linkLibrary(ts.artifact("tree-sitter"));
    layout.linkLibC();

    b.installArtifact(layout);

    const docgen = b.addExecutable(.{
        .name = "docgen",
        .root_source_file = b.path("src/docgen.zig"),
        .target = target,
        .optimize = .Debug,
    });
    docgen.root_module.addImport("zine", zine);
    docgen.root_module.addImport("zeit", zeit.module("zeit"));
    docgen.root_module.addImport("ziggy", ziggy.module("ziggy"));
    b.installArtifact(docgen);

    const md_renderer = b.addExecutable(.{
        .name = "markdown-renderer",
        .root_source_file = b.path("src/exes/markdown-renderer.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });

    const gfm = b.dependency("gfm", mode);

    md_renderer.root_module.addImport("zine", zine);
    md_renderer.root_module.addImport("ziggy", ziggy.module("ziggy"));
    md_renderer.root_module.addImport("zeit", zeit.module("zeit"));
    md_renderer.root_module.addImport("syntax", syntax.module("syntax"));
    md_renderer.root_module.addImport("treez", ts.module("treez"));

    md_renderer.linkLibrary(gfm.artifact("cmark-gfm"));
    md_renderer.linkLibrary(gfm.artifact("cmark-gfm-extensions"));
    md_renderer.linkLibC();

    b.installArtifact(md_renderer);

    if (b.option(
        bool,
        "fuzz",
        "enable building tooling for fuzz testing",
    ) orelse false) {
        setupFuzzing(b, target, optimize);
    }
}

fn setupServer(
    b: *std.Build,
    options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = b.path("src/exes/server/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .macos) {
        server.linkFramework("CoreServices");
    }

    const mime = b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    });
    const ws = b.dependency("ws", .{
        .target = target,
        .optimize = optimize,
    });

    server.root_module.addImport("options", options);
    server.root_module.addImport("mime", mime.module("mime"));
    server.root_module.addImport("ws", ws.module("websocket"));

    b.installArtifact(server);
}

fn setupFuzzing(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const afl = b.lazyImport(@This(), "zig-afl-kit") orelse return;

    const scripty_afl_obj = b.addObject(.{
        .name = "scripty",
        .root_source_file = b.path("src/fuzz/scripty.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    scripty_afl_obj.root_module.stack_check = false;
    scripty_afl_obj.root_module.link_libc = true;

    const afl_exe = afl.addInstrumentedExe(b, target, optimize, scripty_afl_obj);
    b.defaultInstallStep().dependOn(&b.addInstallFile(afl_exe, "scripty-afl").step);
}
