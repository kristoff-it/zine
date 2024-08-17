const std = @import("std");
const ctx = @import("../context.zig");
const Allocator = std.mem.Allocator;

// Redirects calls from the outer Directive to inner Kinds
pub fn directiveCall(
    d: *ctx.Directive,
    gpa: Allocator,
    fn_name: []const u8,
    args: []const ctx.Value,
) !ctx.Value {
    switch (d.kind) {
        inline else => |*k, tag| {
            const Bs = @typeInfo(@TypeOf(k)).Pointer.child.Builtins;

            inline for (@typeInfo(Bs).Struct.decls) |decl| {
                if (decl.name[0] == '_') continue;
                if (std.mem.eql(u8, decl.name, fn_name)) {
                    return @field(Bs, decl.name).call(
                        k,
                        d,
                        gpa,
                        args,
                    );
                }
            }

            return ctx.Value.errFmt(
                gpa,
                "builtin not found in '{s}'",
                .{@tagName(tag)},
            );
        },
    }
}

// Creates a basic builtin to set a field in a Directive
pub fn directiveBuiltin(
    comptime field_name: []const u8,
    comptime tag: @typeInfo(ctx.Value).Union.tag_type.?,
    comptime desc: []const u8,
) type {
    return struct {
        pub const description = desc;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            _: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{
                .err = std.fmt.comptimePrint("expected 1 {s} argument", .{
                    @tagName(tag),
                }),
            };

            if (args.len != 1) return bad_arg;

            if (std.meta.activeTag(args[0]) != tag) {
                return bad_arg;
            }

            const value = @field(args[0], @tagName(tag));

            if (@field(self, field_name) != null) {
                return .{ .err = "field already set" };
            }

            @field(self, field_name) = value;
            return .{ .directive = d };
        }
    };
}

pub const SrcBuiltins = struct {
    pub const url = struct {
        pub const description =
            \\Sets the source location of this image to an external URL.
            \\
            \\Use `asset`, `siteAsset`, and `buildAsset` to refer to local
            \\assets.
            \\
            \\It is required to set the source location of an image.
        ;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            gpa: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const link = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            if (self.src != null) {
                return .{ .err = "field already set" };
            }

            const u = std.Uri.parse(link) catch |err| {
                return ctx.Value.errFmt(gpa, "invalid URL: {}", .{err});
            };

            if (u.scheme.len == 0) {
                return .{
                    .err = "URLs must specify a scheme (eg 'https'), use other builtins to reference assets",
                };
            }

            @field(self, "src") = .{ .url = link };

            return .{ .directive = d };
        }
    };

    pub const asset = struct {
        pub const description =
            \\Sets the source location of this image to a page asset.
            \\
            \\See also `url`, `siteAsset`, and `buildAsset`.
            \\
            \\It is required to set the source location of an image.
        ;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            _: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const page_asset = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            if (self.src != null) {
                return .{ .err = "field already set" };
            }

            @field(self, "src") = .{ .page_asset = page_asset };
            return .{ .directive = d };
        }
    };

    pub const siteAsset = struct {
        pub const description =
            \\Sets the source location of this image to a site asset.
            \\
            \\See also `url`, `asset`, and `buildAsset`.
            \\
            \\It is required to set the source location of an image.
        ;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            _: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const site_asset = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            if (self.src != null) {
                return .{ .err = "field already set" };
            }

            @field(self, "src") = .{ .site_asset = site_asset };
            return .{ .directive = d };
        }
    };
    pub const buildAsset = struct {
        pub const description =
            \\Sets the source location of this image to a build asset.
            \\
            \\See also `url`, `asset`, and `siteAsset`.
            \\
            \\It is required to set the source location of an image.
        ;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            _: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const build_asset = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            if (self.src != null) {
                return .{ .err = "field already set" };
            }

            @field(self, "src") = .{ .build_asset = build_asset };
            return .{ .directive = d };
        }
    };

    pub const page = struct {
        pub const description =
            \\Links to a page.
            \\
            \\The first argument is a page path, while the second optional 
            \\argument is the locale code for mulitlingual websites. In 
            \\mulitlingual websites, the locale code defaults to the same
            \\locale of the current content file.
            \\
            \\The path is relative to the content directory and should exclude
            \\the markdown suffix as Zine will automatically infer which file
            \\naming convention is used by the target page. 
            \\
            \\For example, the value 'foo/bar' will be automatically
            \\matched by Zine with either:
            \\        - content/foo/bar.md
            \\        - content/foo/bar/index.md
        ;
        pub fn call(
            self: anytype,
            d: *ctx.Directive,
            _: Allocator,
            args: []const ctx.Value,
        ) !ctx.Value {
            const bad_arg = .{ .err = "expected 1 or 2 string arguments" };
            if (args.len < 1 or args.len > 2) return bad_arg;

            const ref = switch (args[0]) {
                .string => |s| s,
                else => return bad_arg,
            };

            const code = if (args.len == 1) null else switch (args[1]) {
                .string => |s| s,
                else => return bad_arg,
            };

            if (self.src != null) {
                return .{ .err = "field already set" };
            }

            @field(self, "src") = .{
                .page = .{
                    .ref = ref,
                    .locale = code,
                },
            };
            return .{ .directive = d };
        }
    };
};
