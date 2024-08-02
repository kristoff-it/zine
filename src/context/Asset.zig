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

_meta: context.AssetCollectorExtern.Args,
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
            .ret = .str,
        };
        pub const description =
            \\Returns a link to the asset.
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
            \\<img src="$site.asset('logo.jpg').link()">
            \\<img src="$page.asset('profile.jpg').link()">
        ;
        pub fn call(
            asset: Asset,
            gpa: Allocator,
            args: []const Value,
            _: *utils.SuperHTMLResource,
        ) !Value {
            const bad_arg = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;

            switch (asset._meta.kind) {
                else => {},
                .build => |bip| if (bip == null) {
                    return Value.errFmt(gpa, "build asset '{s}' is being linked but it doesn't define an `install_path` in `build.zig`", .{
                        asset._meta.ref,
                    });
                },
            }

            return asset._collector.call(gpa, asset._meta);
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

            const stat = std.fs.cwd().statFile(self._meta.path) catch {
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

            const data = std.fs.cwd().readFileAlloc(gpa, self._meta.path, std.math.maxInt(u32)) catch {
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
                self._meta.path,
                std.math.maxInt(u32),
                null,
                1,
                0,
            ) catch {
                return .{ .err = "i/o error while reading asset file" };
            };

            log.debug("parsing ziggy file: '{s}'", .{data});

            var diag: _ziggy.Diagnostic = .{ .path = self._meta.ref };
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
