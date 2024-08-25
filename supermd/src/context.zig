const std = @import("std");
const scripty = @import("scripty");
const utils = @import("context/utils.zig");
const Signature = @import("doctypes.zig").Signature;
const Allocator = std.mem.Allocator;

pub const Content = struct {
    block: Directive = .{ .kind = .{ .block = .{} } },
    box: Directive = .{ .kind = .{ .box = .{} } },
    heading: Directive = .{ .kind = .{ .heading = .{} } },
    image: Directive = .{ .kind = .{ .image = .{} } },
    video: Directive = .{ .kind = .{ .video = .{} } },
    link: Directive = .{ .kind = .{ .link = .{} } },
    code: Directive = .{ .kind = .{ .code = .{} } },

    pub const dot = scripty.defaultDot(Content, Value, true);
    pub const description =
        \\The Scripty global scope in SuperMD gives you access
        \\to the various kind of rendering directives that can be
        \\used in SuperMD files.
    ;
    pub const Fields = struct {
        pub const block = Block.description;
        pub const heading = Heading.description;
        pub const image = Image.description;
        pub const video = Video.description;
        pub const link = Link.description;
        pub const code = Code.description;
    };
    pub const Builtins = struct {};
};

pub const Value = union(enum) {
    content: *Content,
    directive: *Directive,

    // Primitive values
    string: []const u8,
    err: []const u8,
    bool: bool,
    int: i64,

    pub fn errFmt(gpa: Allocator, comptime fmt: []const u8, args: anytype) !Value {
        const err_msg = try std.fmt.allocPrint(gpa, fmt, args);
        return .{ .err = err_msg };
    }

    pub fn fromStringLiteral(s: []const u8) Value {
        return .{ .string = s };
    }

    pub fn fromNumberLiteral(bytes: []const u8) Value {
        const num = std.fmt.parseInt(i64, bytes, 10) catch {
            return .{ .err = "error parsing numeric literal" };
        };
        return .{ .int = num };
    }

    pub fn fromBooleanLiteral(b: bool) Value {
        return .{ .bool = b };
    }

    pub fn from(gpa: Allocator, v: anytype) !Value {
        _ = gpa;
        return switch (@TypeOf(v)) {
            *Content => .{ .content = v },
            *Directive => .{ .directive = v },
            []const u8 => .{ .string = v },
            bool => .{ .bool = v },
            i64, usize => .{ .int = @intCast(v) },
            *Value => v.*,
            else => @compileError("TODO: implement Value.from for " ++ @typeName(@TypeOf(v))),
        };
    }

    pub fn dot(
        self: *Value,
        gpa: Allocator,
        path: []const u8,
    ) error{OutOfMemory}!Value {
        switch (self.*) {
            .content => |c| return c.dot(gpa, path),
            .directive => return .{ .err = "field access on directive" },
            else => return .{ .err = "field access on primitive value" },
        }
    }

    pub const call = scripty.defaultCall(Value);

    pub fn builtinsFor(
        comptime tag: @typeInfo(Value).Union.tag_type.?,
    ) type {
        const f = std.meta.fieldInfo(Value, tag);
        switch (@typeInfo(f.type)) {
            .Pointer => |ptr| {
                if (@typeInfo(ptr.child) == .Struct) {
                    return @field(ptr.child, "Builtins");
                }
            },
            .Struct => {
                return @field(f.type, "Builtins");
            },
            else => {},
        }

        return struct {};
    }
};

pub const Directive = struct {
    id: ?[]const u8 = null,
    attrs: ?[][]const u8 = null,
    kind: Kind,

    pub const Kind = union(enum) {
        block: Block,
        box: Box,
        heading: Heading,
        image: Image,
        video: Video,
        link: Link,
        code: Code,
        // sound: struct {
        //     id: ?[]const u8 = null,
        //     attrs: ?[]const []const u8 = null,
        // },
    };

    pub fn validate(d: *Directive, gpa: Allocator) !?Value {
        switch (d.kind) {
            inline else => |v| {
                const T = @TypeOf(v);
                if (@hasDecl(T, "validate")) {
                    return T.validate(gpa, d);
                }

                inline for (T.mandatory) |m| {
                    const f = @tagName(m);
                    if (@field(v, f) == null) {
                        return try Value.errFmt(gpa,
                            \\mandatory field '{s}' is unset
                        , .{f});
                    }
                }
                inline for (T.directive_mandatory) |dm| {
                    const f = @tagName(dm);
                    if (@field(d, f) == null) {
                        return try Value.errFmt(gpa,
                            \\mandatory field '{s}' is unset
                        , .{f});
                    }
                }
            },
        }
        return null;
    }

    pub const fallbackCall = utils.directiveCall;
    pub const PassByRef = true;
    pub const description =
        \\Each directive's functions will allow you to set the directive's 
        \\internal fields accordingly using a "builder pattern" / "fluent interface".
        \\
        \\For example, in:
        \\
        \\```markdown
        \\[]($image.asset('cat.jpg').id('meow'))
        \\```
        \\The call to `asset` returns a reference to the original
        \\`$image` directive, which in turn then gets modified a 
        \\second time by `id`.
        \\
        \\Different kinds of directives will have different functions 
        \\but all will support the functions listed here.
    ;
    pub const Builtins = struct {
        pub const id = struct {
            pub const signature: Signature = .{
                .params = &.{.str},
                .ret = .anydirective,
            };
            pub const description =
                \\Sets the unique identifier field of this directive.
            ;

            pub fn call(
                self: *Directive,
                _: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{
                    .err = "expected 1 string argument",
                };
                if (args.len != 1) return bad_arg;

                const value = switch (args[0]) {
                    .string => |s| s,
                    else => return bad_arg,
                };

                if (self.id != null) return .{ .err = "field already set" };

                self.id = value;

                return .{ .directive = self };
            }
        };
        pub const attrs = struct {
            pub const signature: Signature = .{
                .params = &.{ .str, .{ .Many = .str } },
                .ret = .anydirective,
            };
            pub const description =
                \\Appends to the attributes field of this Directive.
            ;

            pub fn call(
                self: *Directive,
                gpa: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{
                    .err = "expected 1 or more string arguments",
                };
                if (args.len == 0) return bad_arg;

                if (self.attrs != null) return .{ .err = "field already set" };

                const new = try gpa.alloc([]const u8, args.len);
                self.attrs = new;
                for (args, new) |arg, *attr| {
                    const value = switch (arg) {
                        .string => |s| s,
                        else => return bad_arg,
                    };
                    attr.* = value;
                }

                return .{ .directive = self };
            }
        };
    };
};

pub const Block = struct {
    end: ?bool = null,

    pub const description =
        \\A content block, used to define a portion of content
        \\that can be rendered separately by a template. 
    ;

    pub fn validate(_: Allocator, d: *Directive) !?Value {
        if (d.kind.block.end != null) {
            if (d.id != null or d.attrs != null) {
                return .{
                    .err = "end block directive cannot have any other property set",
                };
            }
        }
        return null;
    }
    pub const Builtins = struct {
        pub const end = utils.directiveBuiltin("end", .bool,
            \\Calling this function makes this block directive 
            \\terminate a previous block without opening a new
            \\one.
            \\
            \\An end block directive cannot have any other 
            \\property set.
        );
    };
};

pub const Heading = struct {
    pub const mandatory = .{};
    pub const directive_mandatory = .{};
    pub const Builtins = struct {};
    pub const description =
        \\Allows giving an id and attributes to a heading element.
    ;
};

pub const Box = struct {
    pub const mandatory = .{};
    pub const directive_mandatory = .{.attrs};
    pub const Builtins = struct {};
    pub const description =
        \\When placed at the beginning of a quote block, the quote block 
        \\becomes a generic container for elements that can be styled as 
        \\one wishes.
        \\
        \\Differently from Blocks, Boxes cannot be rendered independently 
        \\and can be nested.
    ;
};

pub const Image = struct {
    alt: ?[]const u8 = null,
    src: ?Src = null,
    caption: ?[]const u8 = null,
    linked: ?bool = null,

    pub const mandatory = .{.src};
    pub const directive_mandatory = .{};
    pub const description =
        \\An embedded image.
    ;
    pub const Builtins = struct {
        pub const alt = utils.directiveBuiltin("alt", .string,
            \\An alternative description for this image that accessibility
            \\tooling can access.
        );
        pub const caption = utils.directiveBuiltin("caption", .string,
            \\A caption for this image.
        );
        pub const linked = utils.directiveBuiltin("linked", .bool,
            \\Wraps the image in a link to itself.
        );

        pub const url = utils.SrcBuiltins.url;
        pub const asset = utils.SrcBuiltins.asset;
        pub const siteAsset = utils.SrcBuiltins.siteAsset;
        pub const buildAsset = utils.SrcBuiltins.buildAsset;
    };
};

pub const Video = struct {
    src: ?Src = null,
    loop: ?bool = null,
    muted: ?bool = null,
    autoplay: ?bool = null,
    controls: ?bool = null,
    pip: ?bool = null,

    pub const mandatory = .{.src};
    pub const directive_mandatory = .{};
    pub const description =
        \\An embedded video.
    ;
    pub const Builtins = struct {
        pub const loop = utils.directiveBuiltin("loop", .bool,
            \\If true, the video will seek back to the start upon reaching the 
            \\end.
        );
        pub const muted = utils.directiveBuiltin("muted", .bool,
            \\If true, the video will be silenced at start. 
        );
        pub const autoplay = utils.directiveBuiltin("autoplay", .bool,
            \\If true, the video will start playing automatically. 
        );
        pub const controls = utils.directiveBuiltin("controls", .bool,
            \\If true, the video will display controls (e.g. play/pause, volume). 
        );
        pub const pip = utils.directiveBuiltin("pip", .bool,
            \\If **false**, clients shouldn't try to display the video in a 
            \\Picture-in-Picture context.
        );

        pub const url = utils.SrcBuiltins.url;
        pub const asset = utils.SrcBuiltins.asset;
        pub const siteAsset = utils.SrcBuiltins.siteAsset;
        pub const buildAsset = utils.SrcBuiltins.buildAsset;
    };
};

pub const Link = struct {
    src: ?Src = null,
    ref: ?[]const u8 = null,
    target: ?[]const u8 = null,

    pub const description =
        \\A link.
    ;
    pub fn validate(_: Allocator, d: *Directive) !?Value {
        const self = &d.kind.link;
        if (self.ref != null) {
            if (self.src == null) {
                self.src = .self_page;
            }
        }

        if (self.src == null) {
            return .{
                .err = "missing call to 'url', 'asset', 'siteAsset', 'buildAsset'or 'page'",
            };
        }
        return null;
    }

    pub const Builtins = struct {
        pub const url = utils.SrcBuiltins.url;
        pub const asset = utils.SrcBuiltins.asset;
        pub const siteAsset = utils.SrcBuiltins.siteAsset;
        pub const buildAsset = utils.SrcBuiltins.buildAsset;
        pub const page = utils.SrcBuiltins.page;
        pub const target = utils.directiveBuiltin("target", .string,
            \\Sets the target HTML attribute of this link. 
        );

        pub const ref = struct {
            pub const signature: Signature = .{
                .params = &.{.str},
                .ret = .anydirective,
            };
            pub const description =
                \\Deep-links to a specific section of either the current
                \\page or a target page set with `page()`.
            ;

            pub fn call(
                self: *Link,
                d: *Directive,
                _: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{ .err = "expected 1 string argument" };

                if (args.len != 1) return bad_arg;

                const str = switch (args[0]) {
                    .string => |s| s,
                    else => return bad_arg,
                };

                if (self.ref != null) {
                    return .{ .err = "field already set" };
                }

                self.ref = str;
                return .{ .directive = d };
            }
        };
    };
};

pub const Code = struct {
    src: ?Src = null,
    language: ?[]const u8 = null,

    pub const mandatory = .{.src};
    pub const directive_mandatory = .{};
    pub const description =
        \\An embedded piece of code.
    ;
    pub const Builtins = struct {
        pub const asset = utils.SrcBuiltins.asset;
        pub const siteAsset = utils.SrcBuiltins.siteAsset;
        pub const buildAsset = utils.SrcBuiltins.buildAsset;
        pub const language = utils.directiveBuiltin("language", .string,
            \\Sets the language of this code snippet, which is also used for
            \\syntax highlighting.
        );
    };
};

pub const Src = union(enum) {
    // External link
    url: []const u8,
    self_page,
    page: struct { ref: []const u8, locale: ?[]const u8 },
    page_asset: []const u8,
    site_asset: []const u8,
    build_asset: []const u8,
};
