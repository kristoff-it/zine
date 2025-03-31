const Asset = @This();

const std = @import("std");
const _ziggy = @import("ziggy");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const fatal = @import("../fatal.zig");
const context = @import("../context.zig");
const PathTable = @import("../PathTable.zig");
const html = @import("../render/html.zig");
const join = @import("../root.zig").join;
const Signature = @import("doctypes.zig").Signature;
const PathName = PathTable.PathName;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Int = context.Int;
const log = utils.log;
const assert = std.debug.assert;

_meta: struct {
    ref: []const u8,
    // full path to the asset
    url: PathName,
    kind: context.AssetKindUnion,
},

pub const Kind = enum {
    /// An asset inside of `assets_dir_path`
    site,
    /// An asset inside of `content_dir_path`, placed next to a content page.
    page,
    /// A build-time asset, stored inside the cache.
    build,
};

pub fn init(ref: []const u8, path: []const u8, kind: context.AssetKindUnion) Value {
    return .{
        .asset = .{
            ._meta = .{
                .ref = ref,
                .path = path,
                .kind = kind,
            },
        },
    };
}

pub const docs_description = "Represents an asset.";
pub const dot = scripty.defaultDot(Asset, Value, false);
pub const Builtins = struct {
    pub const link = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns a link to the asset.
            \\
            \\Calling `link` on an asset will cause it to be installed
            \\under the same relative path into the output directory.
            \\
            \\    `content/post/bar.jpg` -> `public/post/bar.jpg`
            \\  `assets/foo/bar/baz.jpg` -> `public/foo/bar/baz.jpg`
            \\
            \\Build assets will be installed under the path defined in
            \\your `build.zig`.
        ;
        pub const examples =
            \\<img src="$site.asset('logo.jpg').link()">
            \\<img src="$page.asset('profile.jpg').link()">
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;

            var buf = std.ArrayList(u8).init(gpa);
            errdefer buf.deinit();

            const w = buf.writer();
            switch (asset._meta.kind) {
                .page => |variant_id| {
                    try ctx.printLinkPrefix(
                        w,
                        variant_id,
                        false,
                    );
                    const v = ctx._meta.build.variants[variant_id];
                    const hint = v.urls.getPtr(asset._meta.url).?;
                    assert(hint.kind == .page_asset);
                    _ = hint.kind.page_asset.fetchAdd(1, .acq_rel);

                    const st = &v.string_table;
                    const pt = &v.path_table;
                    try w.print("{/}", .{
                        asset._meta.url.fmt(st, pt, null),
                    });
                },
                .site => {
                    try html.printAssetUrlPrefix(ctx, ctx.page, w);
                    const rc = ctx._meta.build.site_assets.getPtr(asset._meta.url).?;
                    _ = rc.fetchAdd(1, .acq_rel);

                    const st = &ctx._meta.build.st;
                    const pt = &ctx._meta.build.pt;
                    try w.print("{/}", .{
                        asset._meta.url.fmt(st, pt, null),
                    });
                },
                .build => {
                    try html.printAssetUrlPrefix(ctx, ctx.page, w);
                    const ba = ctx._meta.build.build_assets.getPtr(
                        asset._meta.ref,
                    ).?;

                    _ = ba.rc.fetchAdd(1, .acq_rel);
                    const op = ba.output_path orelse return Value.errFmt(
                        gpa,
                        "unable to install build asset '{s}' as it does not specify an install path",
                        .{asset._meta.ref},
                    );
                    try w.print("{s}", .{op});
                },
            }

            return Value.from(gpa, buf.items);
        }
    };
    pub const size = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the size of an asset file in bytes.
        ;
        pub const examples =
            \\<div :text="$site.asset('foo.json').size()"></div>
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            switch (asset._meta.kind) {
                .page => |variant_id| {
                    const v = &ctx._meta.build.variants[variant_id];
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                        ),
                    }) catch unreachable;

                    const stat = v.content_dir.statFile(path) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                    return Int.init(@intCast(stat.size));
                },
                .site => {
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &ctx._meta.build.st,
                            &ctx._meta.build.pt,
                            null,
                        ),
                    }) catch unreachable;

                    const stat = ctx._meta.build.site_assets_dir.statFile(path) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                    return Int.init(@intCast(stat.size));
                },
                .build => @panic("TODO"),
            }
        }
    };
    pub const bytes = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the raw contents of an asset.
        ;
        pub const examples =
            \\<div :text="$page.assets.file('foo.json').bytes()"></div>
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            switch (asset._meta.kind) {
                .page => |variant_id| {
                    const v = &ctx._meta.build.variants[variant_id];
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                        ),
                    }) catch unreachable;

                    const data = v.content_dir.readFileAlloc(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                    ) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                    return Value.from(gpa, data);
                },
                .site => {
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &ctx._meta.build.st,
                            &ctx._meta.build.pt,
                            null,
                        ),
                    }) catch unreachable;

                    const data = ctx._meta.build.site_assets_dir.readFileAlloc(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                    ) catch |err| fatal.file(path, err);

                    return Value.from(gpa, data);
                },
                .build => {
                    const ba = ctx._meta.build.build_assets.getPtr(
                        asset._meta.ref,
                    ).?;

                    const data = ctx._meta.build.base_dir.readFileAlloc(
                        gpa,
                        ba.input_path,
                        std.math.maxInt(u32),
                    ) catch |err| fatal.file(ba.input_path, err);

                    return Value.from(gpa, data);
                },
            }
        }
    };
    pub const sriHash = struct {
        pub const signature: Signature = .{ .ret = .String };
        pub const docs_description =
            \\Returns the Base64-encoded SHA384 hash of an asset, prefixed with `sha384-`, for use with Subresource Integrity.
        ;
        pub const examples =
            \\<script src="$site.asset('foo.js').link()" integrity="$site.asset('foo.js').sriHash()"></script>
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const data = switch (asset._meta.kind) {
                .page => |variant_id| blk: {
                    const v = &ctx._meta.build.variants[variant_id];
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                        ),
                    }) catch unreachable;

                    break :blk v.content_dir.readFileAlloc(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                    ) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                },
                .site => blk: {
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &ctx._meta.build.st,
                            &ctx._meta.build.pt,
                            null,
                        ),
                    }) catch unreachable;

                    break :blk ctx._meta.build.site_assets_dir.readFileAlloc(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                    ) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                },
                .build => @panic("TODO"),
            };

            const sha384 = std.crypto.hash.sha2.Sha384;
            const base64 = std.base64.standard.Encoder;

            var hashed_data: [sha384.digest_length]u8 = undefined;
            sha384.hash(data, &hashed_data, .{});

            var hashed_encoded_data: [base64.calcSize(hashed_data.len)]u8 = undefined;
            _ = base64.encode(&hashed_encoded_data, &hashed_data);

            const result: []u8 = try gpa.dupe(u8, "sha384-" ++ hashed_encoded_data);
            return Value.from(gpa, result);
        }
    };

    pub const ziggy = struct {
        pub const signature: Signature = .{ .ret = .any };
        pub const docs_description =
            \\Tries to parse the asset as a Ziggy document.
        ;
        pub const examples =
            \\<div :text="$page.assets.file('foo.ziggy').ziggy().get('bar')"></div>
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const data = switch (asset._meta.kind) {
                .page => |variant_id| blk: {
                    const v = &ctx._meta.build.variants[variant_id];
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &v.string_table,
                            &v.path_table,
                            null,
                        ),
                    }) catch unreachable;

                    break :blk v.content_dir.readFileAllocOptions(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                        null,
                        1,
                        0,
                    ) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                },
                .site => blk: {
                    const path = std.fmt.bufPrint(&buf, "{}", .{
                        asset._meta.url.fmt(
                            &ctx._meta.build.st,
                            &ctx._meta.build.pt,
                            null,
                        ),
                    }) catch unreachable;

                    break :blk ctx._meta.build.site_assets_dir.readFileAllocOptions(
                        gpa,
                        path,
                        std.math.maxInt(u32),
                        null,
                        1,
                        0,
                    ) catch {
                        return .{ .err = "i/o error while reading asset file" };
                    };
                },
                .build => @panic("TODO"),
            };

            log.debug("parsing ziggy file: '{s}'", .{data});

            var diag: _ziggy.Diagnostic = .{ .path = asset._meta.ref };
            const parsed = _ziggy.parseLeaky(_ziggy.dynamic.Value, gpa, data, .{
                .diagnostic = &diag,
                .copy_strings = .to_unescape,
            }) catch {
                return Value.errFmt(
                    gpa,
                    "Error while parsing Ziggy file: {}",
                    .{diag},
                );
            };

            return Value.fromZiggy(gpa, parsed);
        }
    };
};
