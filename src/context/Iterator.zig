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
            _: *const context.Template,
            args: []const Value,
        ) !Value {
            const bad_arg: Value = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;
            return it._superhtml_context.up();
        }
    };
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
