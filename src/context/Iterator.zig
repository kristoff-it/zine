const Iterator = @This();

const std = @import("std");
const assert = std.debug.assert;
const ziggy = @import("ziggy");
const superhtml = @import("superhtml");
const scripty = @import("scripty");
const zeit = @import("zeit");
const context = @import("../context.zig");
const doctypes = @import("doctypes.zig");
const Signature = doctypes.Signature;
const Allocator = std.mem.Allocator;
const Value = context.Value;
const Root = context.Root;
const Site = context.Site;
const Page = context.Page;
const Map = context.Map;
const Array = context.Array;

it: Value = undefined,
idx: usize = 0,
first: bool = undefined,
last: bool = undefined,
len: usize,

_superhtml_context: superhtml.utils.IteratorContext(Value) = .{},
_impl: Impl,

pub const Impl = union(enum) {
    slice_it: SliceIterator(Value),
    leaves_it: LeavesIterator,

    pub fn len(impl: Impl) usize {
        switch (impl) {
            inline else => |v| return v.len(),
        }
    }
};

pub fn init(gpa: Allocator, impl: Impl) !*Iterator {
    const res = try gpa.create(Iterator);
    res.* = .{ ._impl = impl, .len = impl.len() };
    res.last = 0 == res.len;
    return res;
}

pub fn deinit(iter: *const Iterator, gpa: Allocator) void {
    gpa.destroy(iter);
}

pub fn next(iter: *Iterator, gpa: Allocator) !bool {
    if (iter.last) return false;

    switch (iter._impl) {
        inline else => |*v| {
            const item = try v.next(iter.idx, gpa);
            iter.it = try Value.from(gpa, item);
        },
    }

    iter.idx += 1;
    iter.first = iter.idx == 1;
    iter.last = iter.idx >= iter.len;
    return true;
}

pub fn fromArray(gpa: Allocator, arr: Array) !*Iterator {
    return init(gpa, .{
        .slice_it = .{ .items = arr._items },
    });
}

pub const Dot = true;
pub const docs_description = "An iterator.";
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
        pub const docs_description =
            \\In nested loops, accesses the upper `$loop`
            \\
        ;
        pub const examples =
            \\$loop.up().it
        ;
        pub fn call(
            it: *Iterator,
            _: Allocator,
            _: *const Root,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;
            return it._superhtml_context.up();
        }
    };
};

fn SliceIterator(comptime Element: type) type {
    return struct {
        items: []const Element,

        pub fn len(self: @This()) usize {
            return self.items.len;
        }

        pub fn next(self: *@This(), idx: usize, gpa: Allocator) !Element {
            _ = gpa;
            return self.items[idx];
        }
    };
}

pub const LeavesIterator = struct {
    limit: u32,
    sections: []Section,
    pages: []Page,

    pub const Section = struct {
        idx: u32 = 0, // cursor into `page_indexes`
        page_indexes: []const u32, // index into pages
    };

    pub fn init(limit: u32, sections: []Section, pages: []Page) LeavesIterator {
        return .{
            .limit = limit,
            .sections = sections,
            .pages = pages,
        };
    }

    pub fn len(lit: *const LeavesIterator) usize {
        return lit.limit;
    }

    pub fn next(lit: *LeavesIterator, idx: usize, gpa: Allocator) !*context.Page {
        assert(idx < lit.limit);
        _ = gpa;

        var next_page_date = context.DateTime.epoch;
        var next_page: *context.Page = undefined;
        var next_section_idx: usize = undefined;

        for (lit.sections, 0..) |*s, section_idx| {
            if (s.idx == s.page_indexes.len) continue;

            while (true) {
                const page_idx = s.page_indexes[s.idx];
                const page = &lit.pages[page_idx];
                if (!page._parse.active) {
                    s.idx += 1;
                    continue;
                }

                if (page.date._inst.timestamp >= next_page_date.timestamp) {
                    next_page_date = page.date._inst;
                    next_page = page;
                    next_section_idx = section_idx;
                }

                break;
            }
        }

        lit.sections[next_section_idx].idx += 1;
        return next_page;
    }
};
