const Iterator = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const superhtml = @import("superhtml");
const scripty = @import("scripty");
const context = @import("../context.zig");
const doctypes = @import("doctypes.zig");
const Signature = doctypes.Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Template = context.Template;
const Site = context.Site;
const Page = context.Page;
const Map = context.Map;
const Array = context.Array;

it: Value = undefined,
idx: usize = 0,
first: bool = undefined,
last: bool = undefined,
len: usize,

_superhtml_context: superhtml.utils.IteratorContext(Value, Template) = .{},
_impl: Impl,

pub const Impl = union(enum) {
    page_it: PageIterator,
    // page_slice_it: SliceIterator(*const Page),
    translation_it: TranslationIterator,
    map_it: MapIterator,
    // dynamic_it: SliceIterator(ziggy.dynamic.Value),
    value_it: SliceIterator(Value),

    pub fn len(impl: Impl) usize {
        switch (impl) {
            inline else => |v| return v.len(),
        }
    }
};

pub fn init(gpa: Allocator, impl: Impl) !*Iterator {
    const res = try gpa.create(Iterator);
    res.* = .{ ._impl = impl, .len = impl.len() };
    return res;
}

pub fn deinit(iter: *const Iterator, gpa: Allocator) void {
    gpa.destroy(iter);
}

pub fn next(iter: *Iterator, gpa: Allocator) !bool {
    switch (iter._impl) {
        inline else => |*v| {
            const item = try v.next(gpa);
            iter.it = try Value.from(gpa, item orelse return false);
            iter.idx += 1;
            iter.first = iter.idx == 1;
            iter.last = iter.idx == iter.len;
            return true;
        },
    }
}

pub fn fromArray(gpa: Allocator, arr: Array) !*Iterator {
    return init(gpa, .{
        .value_it = .{ .items = arr._items },
    });
}

pub const dot = scripty.defaultDot(Iterator, Value, false);
pub const description = "An iterator.";
pub const Fields = struct {
    pub const it =
        \\The current iteration variable.
    ;
    pub const idx =
        \\The current iteration index.
    ;
    pub const len =
        \\The length of the sequence being iterated.
    ;
    pub const first =
        \\True on the first iteration loop.
    ;
    pub const last =
        \\True on the last iteration loop.
    ;
};
pub const Builtins = struct {
    pub const up = struct {
        pub const signature: Signature = .{ .ret = .Iterator };
        pub const description =
            \\In nested loops, accesses the upper `$loop`
            \\
        ;
        pub const examples =
            \\$loop.up().it
        ;
        pub fn call(
            it: *Iterator,
            _: Allocator,
            args: []const Value,
        ) !Value {
            const bad_arg = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;
            return it._superhtml_context.up();
        }
    };
    // pub const len = struct {
    //     pub const signature: Signature = .{ .ret = .int };
    //     pub const description =
    //         \\Returns the total number of elements in this loop.
    //     ;
    //     pub const examples =
    //         \\$loop.len()
    //     ;

    //     pub fn call(
    //         it: Iterator,
    //         _: Allocator,
    //         args: []const Value,
    //     ) !Value {
    //         const bad_arg = .{ .err = "expected 0 arguments" };
    //         if (args.len != 0) return bad_arg;
    //         const l = it._len orelse return .{
    //             .err = "this iterator doesn't know its total length",
    //         };
    //         return Value.from(l);
    //     }
    // };
    // pub const @"len?" = struct {
    //     pub const signature: Signature = .{ .ret = .{ .opt = .int } };
    //     pub const description =
    //         \\Returns the total number of elements in this loop.
    //         \\
    //     ;
    //     pub const examples =
    //         \\$loop.len?()
    //     ;

    //     pub fn call(
    //         it: Iterator,
    //         _: Allocator,
    //         args: []const Value,
    //     ) !Value {
    //         const bad_arg = .{ .err = "expected 0 arguments" };
    //         if (args.len != 0) return bad_arg;
    //         return Value.from(it._len);
    //     }
    // };
};

fn SliceIterator(comptime Element: type) type {
    return struct {
        idx: usize = 0,
        items: []const Element,

        pub fn len(self: @This()) usize {
            return self.items.len;
        }

        pub fn next(self: *@This(), gpa: Allocator) !?Element {
            _ = gpa;
            if (self.idx == self.items.len) return null;
            defer self.idx += 1;
            return self.items[self.idx];
        }
    };
}

pub const PageIterator = struct {
    idx: usize = 0,

    site: *const Site,
    parent_section_path: ?[]const u8,
    list: std.mem.TokenIterator(u8, .scalar),
    _len: usize,

    pub fn init(
        site: *const Site,
        parent_section_path: ?[]const u8,
        src: []const u8,
    ) PageIterator {
        return .{
            .site = site,
            .parent_section_path = parent_section_path,
            .list = std.mem.tokenizeScalar(u8, src, '\n'),
            ._len = std.mem.count(u8, src, "\n"),
        };
    }

    pub fn len(it: PageIterator) usize {
        return it._len;
    }

    pub fn next(it: *PageIterator, gpa: Allocator) !?*const Page {
        _ = gpa;

        const next_page = it.list.next() orelse return null;
        defer it.idx += 1;

        const page = context.pageGet(
            it.site,
            next_page,
            it.parent_section_path,
            it.idx,
            false,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PageLoad => @panic("TODO: report page load errors"),
        };

        return page;
    }
};

pub const TranslationIterator = struct {
    idx: usize = 0,
    page: *const Page,
    _len: usize,

    pub fn init(
        page: *const Page,
    ) TranslationIterator {
        return .{
            .page = page,
            ._len = if (page.translation_key == null)
                context.allSites().len
            else
                page._meta.key_variants.len,
        };
    }

    pub fn len(it: TranslationIterator) usize {
        return it._len;
    }

    pub fn next(it: *TranslationIterator, gpa: Allocator) !?*const Page {
        _ = gpa;
        if (it.idx >= it._len) return null;

        defer it.idx += 1;

        const t: Page.Translation = if (it.page.translation_key == null) .{
            .site = &context.allSites()[it.idx],
            .md_rel_path = it.page._meta.md_rel_path,
        } else it.page._meta.key_variants[it.idx];

        const page = context.pageGet(
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

pub const MapIterator = struct {
    idx: usize = 0,
    it: std.StringArrayHashMap(ziggy.dynamic.Value).Iterator,
    _len: usize,
    filter: ?[]const u8 = null,

    pub fn init(
        it: std.StringArrayHashMap(ziggy.dynamic.Value).Iterator,
        filter: ?[]const u8,
    ) MapIterator {
        const f = filter orelse return .{ .it = it, ._len = it.len };
        var filter_it = it;
        var count: usize = 0;
        while (filter_it.next()) |elem| {
            if (std.mem.indexOf(u8, elem.key_ptr.*, f) != null) count += 1;
        }
        return .{ .it = it, ._len = count, .filter = f };
    }

    pub fn len(it: MapIterator) usize {
        return it._len;
    }

    pub fn next(it: *MapIterator, _: Allocator) !?Map.KV {
        if (it.idx >= it._len) return null;

        while (it.it.next()) |elem| {
            const f = it.filter orelse {
                it.idx += 1;
                return .{
                    .key = elem.key_ptr.*,
                    .value = elem.value_ptr.*,
                };
            };
            if (std.mem.indexOf(u8, elem.key_ptr.*, f) != null) {
                it.idx += 1;
                return .{
                    .key = elem.key_ptr.*,
                    .value = elem.value_ptr.*,
                };
            }
        }

        unreachable;
    }
};
