const Asset = @This();

const std = @import("std");
const _ziggy = @import("ziggy");
const scripty = @import("scripty");
const utils = @import("utils.zig");
const context = @import("../context.zig");
const log = utils.log;
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Int = context.Int;

_meta: struct {
    ref: []const u8,
    // full path to the asset
    path: []const u8,
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
        ) !Value {
            const bad_arg: Value = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;

            switch (asset._meta.kind) {
                else => {},
                .build => |bip| if (bip == null) {
                    return Value.errFmt(gpa, "build asset '{s}' is being linked but it doesn't define an `install_path` in `build.zig`", .{
                        asset._meta.ref,
                    });
                },
            }

            const url = try context.assetCollect(
                asset._meta.ref,
                asset._meta.path,
                asset._meta.kind,
            );

            return Value.from(gpa, url);
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
            self: Asset,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            _ = gpa;
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const stat = std.fs.cwd().statFile(self._meta.path) catch {
                return .{ .err = "i/o error while reading asset file" };
            };
            return Int.init(@intCast(stat.size));
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
            self: Asset,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const data = std.fs.cwd().readFileAlloc(gpa, self._meta.path, std.math.maxInt(u32)) catch {
                return .{ .err = "i/o error while reading asset file" };
            };
            return Value.from(gpa, data);
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
            self: Asset,
            gpa: Allocator,
            args: []const Value,
        ) !Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const data = std.fs.cwd().readFileAlloc(gpa, self._meta.path, std.math.maxInt(u32)) catch {
                return .{ .err = "i/o error while reading asset file" };
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
            self: Asset,
            gpa: Allocator,
            args: []const Value,
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

            return Value.fromZiggy(gpa, parsed);
        }
    };
};
