const std = @import("std");
const scripty = @import("scripty");
const super = @import("superhtml");
const ziggy = @import("ziggy");
const docgen = @import("context/docgen.zig");
const utils = @import("context/utils.zig");
const Allocator = std.mem.Allocator;
const HostExtern = utils.HostExtern;

pub const ScriptyParam = docgen.ScriptyParam;
pub const Signature = docgen.Signature;

pub const Resources = utils.Resources;

pub const AssetKindUnion = union(Asset.Kind) {
    site,
    // path to the page
    page: []const u8,
    // defined install path for a build asset as defined in the user's
    // build.zig
    build: ?[]const u8,
};
pub const AssetExtern = HostExtern(struct {
    // the user-provided asset reference
    ref: []const u8,
    kind: AssetKindUnion,
});

pub const AssetCollectorExtern = HostExtern(struct {
    // the user-provided asset reference
    ref: []const u8,
    // full path to the asset
    path: []const u8,
    kind: AssetKindUnion,
});

pub const PageExtern = HostExtern(struct {
    // used by hasNext, hasPrev to simply return a boolean value
    just_check: bool = false,
    md_rel_path: []const u8,
    parent_section_path: []const u8,
    url_path_prefix: []const u8,
    kind: union(enum) {
        next: usize,
        prev: usize,
        // md rel path
        subpages,
        // parent section
        // TODO: requires creating site-wide section index
    },
});

pub const PageLoaderExtern = HostExtern(struct {
    md_rel_path: []const u8,
    parent_section_path: []const u8,
    url_path_prefix: []const u8,
    index_in_section: usize,
});

pub const Template = @import("context/Template.zig");
pub const Site = @import("context/Site.zig");
pub const Page = @import("context/Page.zig");
pub const Build = @import("context/Build.zig");
pub const Asset = @import("context/Asset.zig");
pub const DateTime = @import("context/DateTime.zig");

pub const Value = union(enum) {
    template: *Template,
    site: *Site,
    page: *Page,
    translation: *Page.Translation,
    alternative: *Page.Alternative,
    build: *Build,
    asset: Asset,
    dynamic: ziggy.dynamic.Value,
    iterator: Iterator,
    iterator_element: IterElement,
    optional: ?Optional,
    string: []const u8,
    date: DateTime,
    bool: bool,
    int: i64,
    float: f64,
    err: []const u8,

    pub fn errFmt(gpa: Allocator, comptime fmt: []const u8, args: anytype) !Value {
        const err_msg = try std.fmt.allocPrint(gpa, fmt, args);
        return .{ .err = err_msg };
    }

    pub fn renderForError(v: Value, arena: Allocator, w: anytype) !void {
        _ = arena;

        w.print(
            \\Scripty evaluated to type: {s}  
            \\
        , .{@tagName(v)}) catch return error.ErrIO;

        if (v == .err) {
            w.print(
                \\Error message: '{s}'  
                \\
            , .{v.err}) catch return error.ErrIO;
        }

        w.print("\n", .{}) catch return error.ErrIO;
    }

    pub const call = scripty.defaultCall(
        Value,
        utils.SuperHTMLResource,
    );

    pub const Optional = union(enum) {
        iter_elem: IterElement,
        page: *Page,
        bool: bool,
        int: i64,
        string: []const u8,
    };

    pub const Iterator = union(enum) {
        string_it: SliceIterator([]const u8),
        page_it: PageIterator,
        translation_it: SliceIterator(Page.Translation),
        alt_it: SliceIterator(Page.Alternative),

        pub fn len(self: Iterator) usize {
            const l: usize = switch (self) {
                inline else => |v| v.len(),
            };

            return l;
        }
        pub fn next(self: *Iterator, gpa: Allocator) ?Optional {
            switch (self.*) {
                inline else => |*v| {
                    const n = v.next(gpa) orelse return null;
                    const l = self.len();

                    const elem_type = @typeInfo(@TypeOf(n)).Pointer.child;
                    const by_ref = @typeInfo(elem_type) == .Struct and @hasDecl(elem_type, "PassByRef") and elem_type.PassByRef;
                    const it = if (by_ref)
                        IterElement.IterValue.from(n)
                    else
                        IterElement.IterValue.from(n.*);
                    return .{
                        .iter_elem = .{
                            .it = it,
                            .idx = v.idx,
                            .first = v.idx == 0,
                            .last = v.idx == l - 1,
                        },
                    };
                },
            }
        }

        pub fn dot(self: Iterator, gpa: Allocator, path: []const u8) Value {
            _ = path;
            _ = gpa;
            _ = self;
            return .{ .err = "field access on an iterator value" };
        }
    };

    pub const IterElement = struct {
        it: IterValue,
        idx: usize,
        first: bool,
        last: bool,
        // set by super as needed
        _up_idx: u32 = undefined,

        const IterValue = union(enum) {
            string: []const u8,
            page: *Page,
            translation: *Page.Translation,
            alternative: *Page.Alternative,

            pub fn from(v: anytype) IterValue {
                return switch (@TypeOf(v)) {
                    []const u8 => .{ .string = v },
                    *Page => .{ .page = v },
                    *Page.Translation => .{ .translation = v },
                    *Page.Alternative => .{ .alternative = v },
                    else => @compileError("TODO: implement IterElement.IterValue.from for " ++ @typeName(@TypeOf(v))),
                };
            }
        };

        pub const dot = scripty.defaultDot(IterElement, Value);
    };

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

    pub fn from(gpa: Allocator, v: anytype) Value {
        _ = gpa;
        return switch (@TypeOf(v)) {
            *Template => .{ .template = v },
            *Site => .{ .site = v },
            *Page => .{ .page = v },
            *Page.Alternative => .{ .alternative = v },
            *Page.Translation => .{ .translation = v },
            []const Page.Alternative => .{ .iterator = .{ .alt_it = .{ .items = v } } },
            *Build => .{ .build = v },
            Asset => .{ .asset = v },
            // IterElement => .{ .iteration_element = v },
            DateTime => .{ .date = v },
            []const u8 => .{ .string = v },
            bool => .{ .bool = v },
            i64, usize => .{ .int = @intCast(v) },
            ?Value => if (v) |o| o else .{ .err = "trying to access nil value" },
            *Value => v.*,
            IterElement.IterValue => switch (v) {
                .string => |s| .{ .string = s },
                .page => |p| .{ .page = p },
                .translation => |t| .{ .translation = t },
                .alternative => |p| .{ .alternative = p },
            },
            Optional => switch (v) {
                .iter_elem => |ie| .{ .iterator_element = ie },
                .page => |p| .{ .page = p },
                .bool => |b| .{ .bool = b },
                .string => |s| .{ .string = s },
                .int => |i| .{ .int = i },
            },

            ?Optional => .{ .optional = v orelse @panic("TODO: null optional reached Value.from") },
            ziggy.dynamic.Value => .{ .dynamic = v },
            []const []const u8 => .{ .iterator = .{ .string_it = .{ .items = v } } },
            else => @compileError("TODO: implement Value.from for " ++ @typeName(@TypeOf(v))),
        };
    }
    pub fn dot(
        self: *Value,
        gpa: Allocator,
        path: []const u8,
    ) error{OutOfMemory}!Value {
        switch (self.*) {
            .string,
            .bool,
            .int,
            .float,
            .err,
            .date,
            => return .{ .err = "field access on primitive value" },
            .dynamic => return .{ .err = "field access on dynamic value" },
            .optional => return .{ .err = "field access on optional value" },
            .asset => return .{ .err = "field access on asset value" },
            // .iteration_element => return
            .iterator_element => |*v| return v.dot(gpa, path),
            inline else => |v| return v.dot(gpa, path),
        }
    }

    pub fn builtinsFor(comptime tag: @typeInfo(Value).Union.tag_type.?) type {
        const IterElementBuiltins = struct {
            pub const up = struct {
                pub const signature: Signature = .{ .ret = .dyn };
                pub const description =
                    \\In nested loops, accesses the upper `$loop`
                    \\
                ;
                pub const examples =
                    \\$loop.up().it
                ;
                pub const call = super.utils.loopUpFunction(
                    Value,
                    utils.SuperHTMLResource,
                );
            };
        };

        return switch (tag) {
            .string => @import("context/primitive_builtins/String.zig"),
            .int => @import("context/primitive_builtins/Int.zig"),
            .bool => @import("context/primitive_builtins/Bool.zig"),
            .dynamic => @import("context/primitive_builtins/Dynamic.zig"),
            .iterator_element => IterElementBuiltins,
            else => {
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
            },
        };
    }
};

pub fn SliceIterator(comptime Element: type) type {
    return struct {
        items: []const Element,
        idx: usize = 0,

        pub fn len(self: @This()) usize {
            return self.items.len;
        }
        pub fn index(self: @This()) usize {
            return self.items.idx;
        }

        pub fn next(self: *@This(), gpa: Allocator) ?*Element {
            _ = gpa;
            if (self.idx == self.items.len) return null;
            const result: ?*Element = @constCast(&self.items[self.idx]);
            self.idx += 1;
            return result;
        }
    };
}

pub const PageIterator = struct {
    idx: usize = 0,

    _parent_section_path: []const u8,
    _url_path_prefix: []const u8,
    _page_loader: *const PageLoaderExtern,
    _list: std.mem.TokenIterator(u8, .scalar),
    _len: usize,

    pub fn init(
        parent_section_path: []const u8,
        url_path_prefix: []const u8,
        src: []const u8,
        page_loader: *const PageLoaderExtern,
    ) PageIterator {
        return .{
            ._parent_section_path = parent_section_path,
            ._url_path_prefix = url_path_prefix,
            ._list = std.mem.tokenizeScalar(u8, src, '\n'),
            ._page_loader = page_loader,
            ._len = std.mem.count(u8, src, "\n"),
        };
    }

    pub fn len(it: PageIterator) usize {
        return it._len;
    }
    pub fn index(it: PageIterator) usize {
        return it.idx;
    }

    pub fn next(it: *PageIterator, gpa: Allocator) ?*Page {
        const next_page = it._list.next() orelse return null;
        defer it.idx += 1;

        const value = it._page_loader.call(gpa, .{
            .index_in_section = it.idx,
            .parent_section_path = it._parent_section_path,
            .url_path_prefix = it._url_path_prefix,
            .md_rel_path = next_page,
            // TODO: give iterators the ability to error out
        }) catch @panic("error while fetching next page");

        return value.page;
    }
};
