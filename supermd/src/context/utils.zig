const std = @import("std");
const ctx = @import("../context.zig");
const Allocator = std.mem.Allocator;
const Signature = @import("../doctypes.zig").Signature;

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
        pub const signature: Signature = .{
            .params = switch (tag) {
                .content,
                .directive,
                => unreachable,
                .string => &.{.str},
                .bool => &.{.bool},
                .err => &.{},
                .int => &.{.int},
            },
            .ret = .anydirective,
        };
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

            const value = if (tag == .err) blk: {
                if (args.len != 0) return .{
                    .err = "expected 0 arguments",
                };
                break :blk true;
            } else blk: {
                if (args.len != 1) return bad_arg;

                break :blk @field(args[0], @tagName(tag));
            };

            if (std.meta.activeTag(args[0]) != tag) {
                return bad_arg;
            }

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
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .anydirective,
        };
        pub const description =
            \\Sets the source location of this directive to an external URL.
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
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .anydirective,
        };
        pub const description =
            \\Sets the source location of this directive to a page asset.
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
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .anydirective,
        };
        pub const description =
            \\Sets the source location of this directive to a site asset.
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
        pub const signature: Signature = .{
            .params = &.{.str},
            .ret = .anydirective,
        };
        pub const description =
            \\Sets the source location of this directive to a build asset.
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
        pub const signature: Signature = .{
            .params = &.{ .str, .{ .Opt = .str } },
            .ret = .anydirective,
        };
        pub const description =
            \\Sets the source location of this directive to a page.
            \\
            \\The first argument is a page path, while the second, optional 
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
            \\  - content/foo/bar.smd
            \\  - content/foo/bar/index.smd
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
                    .kind = .absolute,
                    .ref = ref,
                    .locale = code,
                },
            };
            return .{ .directive = d };
        }
    };
    pub const sub = struct {
        pub const signature: Signature = .{
            .params = &.{ .str, .{ .Opt = .str } },
            .ret = .anydirective,
        };
        pub const description =
            \\Same as `page()`, but the reference is relative to the current 
            \\page.
            \\
            \\Only works on Section pages (i.e. pages with a `index.smd`
            \\filename).
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
                    .kind = .sub,
                    .ref = ref,
                    .locale = code,
                },
            };
            return .{ .directive = d };
        }
    };

    pub const sibling = struct {
        pub const signature: Signature = .{
            .params = &.{ .str, .{ .Opt = .str } },
            .ret = .anydirective,
        };
        pub const description =
            \\Same as `page()`, but the reference is relative to the section
            \\the current page belongs to.
            \\
            \\># [NOTE]($block)
            \\>While section pages define a section, *as pages* they don't
            \\>belong to the section they define.
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
                    .kind = .sibling,
                    .ref = ref,
                    .locale = code,
                },
            };
            return .{ .directive = d };
        }
    };
};
