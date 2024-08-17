const std = @import("std");
const scripty = @import("scripty");
const superhtml = @import("superhtml");
const ziggy = @import("ziggy");
const docgen = @import("context/docgen.zig");
const Allocator = std.mem.Allocator;

pub const AssetKindUnion = union(Asset.Kind) {
    site,
    page: *const Page,
    // defined install path for a build asset as defined in the user's
    // build.zig
    build: ?[]const u8,
};

pub var assetFind: *const fn (
    ref: []const u8,
    kind: AssetKindUnion,
) error{OutOfMemory}!Value = undefined;

pub var assetCollect: *const fn (
    ref: []const u8,
    path: []const u8,
    kind: AssetKindUnion,
) error{OutOfMemory}![]const u8 = undefined;

pub const PageSearchStrategy = union(enum) {
    ref: struct {
        path: []const u8,
        site: *const Site,
    },
    next: *const Page,
    prev: *const Page,
    subpages: *const Page,
};
pub var pageFind: *const fn (
    search: PageSearchStrategy,
) error{OutOfMemory}!Value = undefined;

pub var pageGet: *const fn (
    site: *const Site,
    md_rel_path: []const u8,
    parent_section_path: ?[]const u8,
    index_in_section: ?usize,
    is_root: bool,
) error{ OutOfMemory, PageLoad }!*const Page = undefined;
pub var pageGetRoot: *const fn () *const Page = undefined;

pub var siteGet: *const fn (
    code: []const u8,
) ?*const Site = undefined;

pub var allSites: *const fn () []const Site = undefined;

pub const ScriptyParam = docgen.ScriptyParam;
pub const Signature = docgen.Signature;

pub const md = @import("context/markdown.zig");

pub const Template = @import("context/Template.zig");
pub const Site = @import("context/Site.zig");
pub const Page = @import("context/Page.zig");
pub const Build = @import("context/Build.zig");
pub const Asset = @import("context/Asset.zig");
pub const DateTime = @import("context/DateTime.zig");

pub const Value = union(enum) {
    template: *const Template,
    site: *const Site,
    page: *const Page,
    alternative: *const Page.Alternative,
    build: *const Build,
    asset: Asset,
    dynamic: ziggy.dynamic.Value,
    iterator: Iterator,
    iterator_element: IterElement,
    map_kv: MapKV,
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

    pub const call = scripty.defaultCall(Value);

    pub const Optional = union(enum) {
        iter_elem: IterElement,
        page: *const Page,
        bool: bool,
        int: i64,
        string: []const u8,
        dynamic: ziggy.dynamic.Value,
    };

    pub const Iterator = union(enum) {
        string_it: SliceIterator([]const u8),
        page_it: PageIterator,
        translation_it: TranslationIterator,
        alt_it: SliceIterator(Page.Alternative),
        map_it: MapIterator,

        pub fn len(self: Iterator) usize {
            const l: usize = switch (self) {
                inline else => |v| v.len(),
            };

            return l;
        }
        pub fn next(self: *Iterator, gpa: Allocator) !?Optional {
            switch (self.*) {
                inline else => |*v| {
                    const n = try v.next(gpa) orelse return null;
                    const l = self.len();

                    const elem_type = switch (@typeInfo(@TypeOf(n))) {
                        .Pointer => |p| p.child,
                        else => @TypeOf(n),
                    };
                    const by_ref = @typeInfo(elem_type) == .Struct and @hasDecl(elem_type, "PassByRef") and elem_type.PassByRef;
                    const it = if (by_ref)
                        IterElement.IterValue.from(n)
                    else
                        IterElement.IterValue.from(n.*);
                    return .{
                        .iter_elem = .{
                            .it = it,
                            .idx = v.idx,
                            .first = v.idx == 1,
                            .last = v.idx == l,
                            .len = self.len(),
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
        len: usize,
        // set by super as needed
        _up_idx: u32 = 0,
        _up_tpl: *const anyopaque = undefined,

        const IterValue = union(enum) {
            string: []const u8,
            page: *const Page,
            alternative: *const Page.Alternative,
            map_kv: MapKV,

            pub fn from(v: anytype) IterValue {
                return switch (@TypeOf(v)) {
                    []const u8 => .{ .string = v },
                    *const Page => .{ .page = v },
                    *const Page.Alternative => .{ .alternative = v },
                    MapKV => .{ .map_kv = v },
                    else => @compileError("TODO: implement IterElement.IterValue.from for " ++ @typeName(@TypeOf(v))),
                };
            }
        };

        pub const dot = scripty.defaultDot(IterElement, Value, false);
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
            *const Template => .{ .template = v },
            *const Site => .{ .site = v },
            *const Page => .{ .page = v },
            *const Page.Alternative => .{ .alternative = v },
            []const Page.Alternative => .{ .iterator = .{ .alt_it = .{ .items = v } } },
            *const Build => .{ .build = v },
            Asset => .{ .asset = v },
            // IterElement => .{ .iteration_element = v },
            DateTime => .{ .date = v },
            []const u8 => .{ .string = v },
            ?[]const u8 => .{
                .optional = .{
                    .string = v orelse @panic("TODO: null optional reached Value.from"),
                },
            },
            bool => .{ .bool = v },
            i64, usize => .{ .int = @intCast(v) },
            ?Value => if (v) |o| o else .{ .err = "trying to access nil value" },
            *Value => v.*,
            IterElement.IterValue => switch (v) {
                .string => |s| .{ .string = s },
                .page => |p| .{ .page = p },
                .alternative => |p| .{ .alternative = p },
                .map_kv => |kv| .{ .map_kv = kv },
            },
            Optional => switch (v) {
                .iter_elem => |ie| .{ .iterator_element = ie },
                .page => |p| .{ .page = p },
                .bool => |b| .{ .bool = b },
                .string => |s| .{ .string = s },
                .int => |i| .{ .int = i },
                .dynamic => |d| .{ .dynamic = d },
            },

            ?Optional => .{ .optional = v orelse @panic("TODO: null optional reached Value.from") },
            ziggy.dynamic.Value => .{ .dynamic = v },
            MapKV => .{ .map_kv = v },
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
            .map_kv,
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
                pub const call = superhtml.utils.loopUpFunction(
                    Value,
                    superhtml.VM(Template, Value).Template,
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

        pub fn next(self: *@This(), gpa: Allocator) !?*const Element {
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

    _site: *const Site,
    _parent_section_path: ?[]const u8,
    _list: std.mem.TokenIterator(u8, .scalar),
    _len: usize,

    pub fn init(
        site: *const Site,
        parent_section_path: ?[]const u8,
        src: []const u8,
    ) PageIterator {
        return .{
            ._site = site,
            ._parent_section_path = parent_section_path,
            ._list = std.mem.tokenizeScalar(u8, src, '\n'),
            ._len = std.mem.count(u8, src, "\n"),
        };
    }

    pub fn len(it: PageIterator) usize {
        return it._len;
    }
    pub fn index(it: PageIterator) usize {
        return it.idx;
    }

    pub fn next(it: *PageIterator, gpa: Allocator) !?*const Page {
        _ = gpa;

        const next_page = it._list.next() orelse return null;
        defer it.idx += 1;

        const page = pageGet(
            it._site,
            next_page,
            it._parent_section_path,
            it.idx,
            false,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PageLoad => @panic("TODO: report page load errors"),
        };

        return page;

        // const value = it._page_loader.call(gpa, .{
        //     .index_in_section = it.idx,
        //     .parent_section_path = it._parent_section_path,
        //     .url_path_prefix = it._url_path_prefix,
        //     .md_rel_path = next_page,
        //     // TODO: give iterators the ability to error out
        // }) catch @panic("error while fetching next page");

        // return value.page;
    }
};

pub const TranslationIterator = struct {
    idx: usize = 0,
    _page: *const Page,
    _len: usize,

    pub fn init(
        page: *const Page,
    ) TranslationIterator {
        return .{
            ._page = page,

            ._len = if (page.translation_key == null)
                allSites().len
            else
                page._meta.key_variants.len,
        };
    }

    pub fn len(it: TranslationIterator) usize {
        return it._len;
    }
    pub fn index(it: TranslationIterator) usize {
        return it.idx;
    }

    pub fn next(it: *TranslationIterator, gpa: Allocator) !?*const Page {
        _ = gpa;
        if (it.idx >= it._len) return null;

        defer it.idx += 1;

        const t: Page.Translation = if (it._page.translation_key == null) .{
            .site = &allSites()[it.idx],
            .md_rel_path = it._page._meta.md_rel_path,
        } else it._page._meta.key_variants[it.idx];

        const page = pageGet(
            t.site,
            t.md_rel_path,
            null,
            null,
            false,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PageLoad => @panic("trying to access a non-existent localized variant of a page is an error for now, sorry! give the same translation key to all variants of this page and you won't see this error anymore."),
        };

        return page;
    }
};

pub const MapKV = struct {
    _key: []const u8,
    _value: ziggy.dynamic.Value,

    // pub const dot = scripty.defaultDot(MapKV, Value);
    pub const PassByRef = true;
    pub const Builtins = struct {
        pub const key = struct {
            pub const signature: Signature = .{ .ret = .str };
            pub const description =
                \\Returns the key of a key-value pair.
            ;
            pub const examples =
                \\$loop.it.key()
            ;
            pub fn call(
                kv: MapKV,
                _: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{ .err = "expected 0 arguments" };
                if (args.len != 0) return bad_arg;
                return .{ .string = kv._key };
            }
        };
        pub const value = struct {
            pub const signature: Signature = .{ .ret = .dyn };
            pub const description =
                \\Returns the value of a key-value pair.
            ;
            pub const examples =
                \\$loop.it.value()
            ;
            pub fn call(
                kv: MapKV,
                _: Allocator,
                args: []const Value,
            ) !Value {
                const bad_arg = .{ .err = "expected 0 arguments" };
                if (args.len != 0) return bad_arg;
                return switch (kv._value) {
                    .kv => .{ .dynamic = kv._value },
                    .bytes => |b| .{ .string = b },
                    .tag => |t| .{ .string = t.bytes },
                    .integer => |i| .{ .int = i },
                    .float => |f| .{ .float = f },
                    .bool => |b| .{ .bool = b },
                    .null => @panic("TODO: implement support for Ziggy null values in scripty"),
                };
            }
        };
    };
};
pub const MapIterator = struct {
    idx: usize = 0,
    _it: std.StringArrayHashMap(ziggy.dynamic.Value).Iterator,
    _len: usize,
    _filter: ?[]const u8 = null,

    pub fn init(
        it: std.StringArrayHashMap(ziggy.dynamic.Value).Iterator,
        filter: ?[]const u8,
    ) MapIterator {
        const f = filter orelse return .{ ._it = it, ._len = it.len };
        var filter_it = it;
        var count: usize = 0;
        while (filter_it.next()) |elem| {
            if (std.mem.indexOf(u8, elem.key_ptr.*, f) != null) count += 1;
        }
        return .{ ._it = it, ._len = count, ._filter = f };
    }

    pub fn len(it: MapIterator) usize {
        return it._len;
    }
    pub fn index(it: MapIterator) usize {
        return it.idx;
    }

    pub fn next(it: *MapIterator, _: Allocator) !?MapKV {
        if (it.idx >= it._len) return null;

        while (it._it.next()) |elem| {
            const f = it._filter orelse {
                it.idx += 1;
                return .{
                    ._key = elem.key_ptr.*,
                    ._value = elem.value_ptr.*,
                };
            };
            if (std.mem.indexOf(u8, elem.key_ptr.*, f) != null) {
                it.idx += 1;
                return .{
                    ._key = elem.key_ptr.*,
                    ._value = elem.value_ptr.*,
                };
            }
        }

        unreachable;
    }
};
