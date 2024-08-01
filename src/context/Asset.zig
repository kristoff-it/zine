const Asset = @This();

const std = @import("std");
const _ziggy = @import("ziggy");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const log = utils.log;
const Signature = @import("docgen.zig").Signature;
const context = @import("../context.zig");
const Value = context.Value;
const Allocator = std.mem.Allocator;

_kind: Kind,
// - build: name of the asset
// - asset: rel path of the asset (rooted in either content/ or assets/)
_ref: []const u8,
// absolute path to the asset
_path: []const u8,
// defined install path for a build asset as defined in the user's build.zig
// unused otherwise
_build_out_path: ?[]const u8 = null,
_collector: *const context.AssetCollectorExtern = &.{},

pub const Kind = enum {
    /// An asset inside of `assets_dir_path`
    site,
    /// An asset inside of `content_dir_path`, placed next to a content page.
    page,
    /// A build-time asset, stored inside the cache.
    build,
};

pub const description = "Represents an asset.";
pub const dot = scripty.defaultDot(Asset, Value);
pub const Builtins = struct {
    pub const link = struct {
        pub const signature: Signature = .{
            .parameters = .{.bool},
            .ret = .str,
        };
        pub const description =
            \\Returns a link to the asset.
            \\
            \\If the provided boolean argument is `true`, the link will
            \\be suffixed with a query parameter that contains a hash of
            \\the file's contents, wich can be used as a cache-busting 
            \\technique.
            \\
            \\Calling `link` on an asset will cause it to be installed 
            \\under the same relative path into the output directory.
            \\
            \\    `content/post/bar.jpg` -> `zig-out/post/bar.jpg`
            \\  `assets/foo/bar/baz.jpg` -> `zig-out/foo/bar/baz.jpg`
            \\
            \\Build assets will be installed under the path defined in 
            \\your `build.zig`.
        ;
        pub const examples =
            \\<img src="$site.asset('profile.jpg').link(true)">
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const bad_arg = .{
                .err = "expected 1 boolean argument",
            };
            if (args.len != 1) return bad_arg;

            const unique = switch (args[0]) {
                .bool => |s| s,
                else => return bad_arg,
            };

            const build_out_path = switch (asset._kind) {
                .build => asset._build_out_path orelse {
                    return Value.errFmt(gpa, "build asset '{s}' is being linked but it doesn't define an `install_path` in `build.zig`", .{
                        asset._ref,
                    });
                },
                // not used when kind is not build
                else => undefined,
            };

            return asset._collector.call(gpa, .{
                .kind = asset._kind,
                .ref = asset._ref,
                .path = asset._path,
                .build_out_path = build_out_path,
                .unique = unique,
            });
        }
    };
    pub const size = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\Returns the size of an asset file in bytes.
        ;
        pub const examples =
            \\<div var="$site.asset('foo.json').size()"></div>
        ;
        pub fn call(
            self: Asset,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const stat = std.fs.cwd().statFile(self._path) catch {
                return .{ .err = "i/o error while reading asset file" };
            };
            return .{ .int = @intCast(stat.size) };
        }
    };
    pub const bytes = struct {
        pub const signature: Signature = .{
            .ret = .str,
        };
        pub const description =
            \\Returns the raw contents of an asset.
        ;
        pub const examples =
            \\<div var="$page.assets.file('foo.json').bytes()"></div>
        ;
        pub fn call(
            self: Asset,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const data = std.fs.cwd().readFileAlloc(gpa, self._path, std.math.maxInt(u32)) catch {
                return .{ .err = "i/o error while reading asset file" };
            };
            return .{ .string = data };
        }
    };

    pub const ziggy = struct {
        pub const signature: Signature = .{
            .ret = .dyn,
        };
        pub const description =
            \\Tries to parse the asset as a Ziggy document.
        ;
        pub const examples =
            \\<div var="$page.assets.file('foo.ziggy').ziggy().get('bar')"></div>
        ;
        pub fn call(
            self: Asset,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const data = std.fs.cwd().readFileAllocOptions(
                gpa,
                self._path,
                std.math.maxInt(u32),
                null,
                1,
                0,
            ) catch {
                return .{ .err = "i/o error while reading asset file" };
            };

            log.debug("parsing ziggy file: '{s}'", .{data});

            var diag: _ziggy.Diagnostic = .{ .path = self._ref };
            const parsed = _ziggy.parseLeaky(_ziggy.dynamic.Value, gpa, data, .{
                .diagnostic = &diag,
                .copy_strings = .to_unescape,
            }) catch {
                var buf = std.ArrayList(u8).init(gpa);
                try buf.writer().print("Error while parsing Ziggy file: {}", .{diag});
                return .{ .err = buf.items };
            };

            return .{ .dynamic = parsed };
        }
    };
};
