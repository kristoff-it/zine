const PathTable = @This();

const std = @import("std");
const builtin = @import("builtin");
const StringTable = @import("StringTable.zig");
const String = StringTable.String;
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

path_components: std.ArrayListUnmanaged(String),
path_map: Path.Map,

pub const empty: PathTable = .{
    .path_components = .empty,
    .path_map = .empty,
};

pub fn deinit(pt: *const PathTable, gpa: Allocator) void {
    var pc = pt.path_components;
    pc.deinit(gpa);

    var pm = pt.path_map;
    pm.deinit(gpa);
}

pub const PathName = packed struct {
    path: Path,
    name: String,

    pub fn fmt(
        u: PathName,
        st: *const StringTable,
        pt: *const PathTable,
        prefix: ?[]const u8,
    ) PathName.Formatter {
        return .{ .u = u, .st = st, .pt = pt, .prefix = prefix };
    }

    pub const empty_name: String = @enumFromInt(0);
    pub const empty_path: Path = @enumFromInt(0);
    pub fn get(st: *const StringTable, pt: *const PathTable, src: []const u8) ?PathName {
        if (builtin.mode == .Debug) {
            assert(!std.mem.endsWith(u8, src, "/\\"));
            assert(st.get("") == empty_name);
            assert(pt.get(&.{}) == empty_path);
            assert(src.len > 0);
        }

        const base = std.fs.path.dirnamePosix(src) orelse {
            const name = st.get(src) orelse return null;
            return .{ .path = empty_path, .name = name };
        };

        const path = pt.getPathNoName(st, &.{}, base) orelse return null;
        const name = st.get(std.fs.path.basenamePosix(src[base.len..])) orelse return null;
        return .{ .path = path, .name = name };
    }

    pub const Formatter = struct {
        u: PathName,
        st: *const StringTable,
        pt: *const PathTable,
        prefix: ?[]const u8,

        pub fn format(
            f: PathName.Formatter,
            comptime maybe_sep: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            comptime assert(maybe_sep.len < 2);
            const sep = if (maybe_sep.len == 0) "/" else blk: {
                comptime assert(maybe_sep[0] == '/' or maybe_sep[0] == '\\');
                break :blk maybe_sep;
            };
            _ = options;

            if (f.prefix) |p| {
                if (p.len > 0) {
                    try writer.writeAll(p);
                    if (p[p.len - 1] != sep[0]) {
                        try writer.writeAll(sep);
                    }
                }
            }

            const path_slice = f.u.path.slice(f.pt);
            for (path_slice) |c| {
                try writer.writeAll(c.slice(f.st));
                try writer.writeAll(sep);
            }

            try writer.writeAll(f.u.name.slice(f.st));
        }
    };
};

pub fn getPathNoName(
    pt: *const PathTable,
    string_table: *const StringTable,
    /// Optional already computed prefix
    prefix: []const String,
    path: []const u8,
) ?Path {
    var it = std.mem.tokenizeScalar(u8, path, '/');
    const component_count = blk: {
        var count: u32 = 0;
        while (it.next() != null) count += 1;
        it.reset();
        break :blk count;
    } + prefix.len;

    var buf: [512]String = undefined;
    if (component_count > 512) {
        std.debug.print("error: a path has more than 512 components, PathTable needs to have its limits bumped up\nthe path: '{s}'\n", .{path});
        std.process.exit(1);
    }

    @memcpy(buf[0..prefix.len], prefix);

    const new_components = buf[prefix.len..component_count];
    for (new_components) |*cmp| {
        cmp.* = string_table.get(it.next().?) orelse return null;
    }

    return pt.path_map.getKeyAdapted(
        mem.sliceAsBytes(buf[0..component_count]),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
    );
}

pub fn get(pt: *const PathTable, components: []const String) ?Path {
    return pt.path_map.getKeyAdapted(
        mem.sliceAsBytes(components),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
    );
}

/// Interns a path that ends with a file name component, which will not be
/// interned as part of the path (just as a separate String).
pub fn internPathWithName(
    pt: *PathTable,
    gpa: Allocator,
    string_table: *StringTable,
    path_prefix: []const String,
    path: []const u8,
) !struct { Path, String } {
    assert(string_table.string_bytes.items.len > 0); // string_table must contain a zero elem
    assert(string_table.string_bytes.items[0] == 0); // the zero elem must be the empty string

    var it = std.mem.tokenizeScalar(u8, path, std.fs.path.sep);
    const component_count = blk: {
        var count: u32 = 0;
        while (it.next() != null) count += 1;
        it.reset();
        break :blk count;
    };

    // "buffer" the component slice into inactive memory of
    // path_table: if the path already exists, we don't do anything
    // and this memory will be overwritten eventually.
    // If the path is new, we then adjust len to "append" the new data.
    try pt.path_components.ensureUnusedCapacity(gpa, component_count + path_prefix.len); // we do not store an extra index for the null terminator because the name component will be used to store it instead.
    const old_len = pt.path_components.items.len;
    const components = pt.path_components.items[old_len..].ptr[0 .. component_count + path_prefix.len];

    @memcpy(components.ptr, path_prefix);
    for (components[path_prefix.len..]) |*cmp| cmp.* = try string_table.intern(gpa, it.next().?);

    const path_components = components[0 .. components.len - 1];
    const name = components[components.len - 1];

    const gop = try pt.path_map.getOrPutContextAdapted(
        gpa,
        std.mem.sliceAsBytes(path_components),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
        @as(Path.MapContext, .{ .components = pt.path_components.items }),
    );
    if (gop.found_existing) return .{ gop.key_ptr.*, name };

    pt.path_components.items.len += path_components.len;
    pt.path_components.appendAssumeCapacity(@enumFromInt(0));

    const new_off: Path = @enumFromInt(old_len);
    gop.key_ptr.* = new_off;

    return .{ new_off, name };
}

pub fn internPath(
    pt: *PathTable,
    gpa: Allocator,
    string_table: *StringTable,
    path: []const u8,
) !Path {
    assert(string_table.string_bytes.items.len > 0); // string_table must contain a zero elem
    assert(string_table.string_bytes.items[0] == 0); // the zero elem must be the empty string
    var it = std.mem.tokenizeScalar(u8, path, std.fs.path.sep);
    const component_count = blk: {
        var count: u32 = 0;
        while (it.next() != null) count += 1;
        it.reset();
        break :blk count;
    };

    // "buffer" the component slice into inactive memory of
    // path_table: if the path already exists, we don't do anything
    // and this memory will be overwritten eventually.
    // If the path is new, we then adjust len to "append" the new data.
    try pt.path_components.ensureUnusedCapacity(gpa, component_count + 1);
    const old_len = pt.path_components.items.len;
    const components = pt.path_components.items[old_len..].ptr[0..component_count];
    for (components) |*cmp| cmp.* = try string_table.intern(gpa, it.next().?);

    const gop = try pt.path_map.getOrPutContextAdapted(
        gpa,
        std.mem.sliceAsBytes(components),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
        @as(Path.MapContext, .{ .components = pt.path_components.items }),
    );
    if (gop.found_existing) return gop.key_ptr.*;

    pt.path_components.items.len += component_count;
    pt.path_components.appendAssumeCapacity(@enumFromInt(0));

    const new_off: Path = @enumFromInt(old_len);
    gop.key_ptr.* = new_off;

    return new_off;
}

pub fn intern(pt: *PathTable, gpa: Allocator, components: []const String) !Path {
    const gop = try pt.path_map.getOrPutContextAdapted(
        gpa,
        mem.sliceAsBytes(components),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
        @as(Path.MapContext, .{ .components = pt.path_components.items }),
    );
    if (gop.found_existing) return gop.key_ptr.*;

    try pt.path_components.ensureUnusedCapacity(gpa, components.len + 1);
    const new_off: Path = @enumFromInt(pt.path_components.items.len);

    pt.path_components.appendSliceAssumeCapacity(components);
    pt.path_components.appendAssumeCapacity(@enumFromInt(0));

    gop.key_ptr.* = new_off;

    return new_off;
}

pub fn internExtend(
    pt: *PathTable,
    gpa: Allocator,
    prefix_path: Path,
    new_component: String,
) !Path {
    // NOTE: this needs to be recalculated again after ensuring capacity
    // in case that the memory got reallocated
    const components_len = prefix_path.slice(pt).len;
    try pt.path_components.ensureUnusedCapacity(gpa, components_len + 2);
    const components = prefix_path.slice(pt);

    const old_len = pt.path_components.items.len;
    const new = pt.path_components.items[old_len..].ptr[0 .. components_len + 1];
    for (components, new[0..components_len]) |c, *n| n.* = c;
    new[components_len] = new_component;

    const gop = try pt.path_map.getOrPutContextAdapted(
        gpa,
        mem.sliceAsBytes(new),
        @as(Path.MapIndexAdapter, .{ .components = pt.path_components.items }),
        @as(Path.MapContext, .{ .components = pt.path_components.items }),
    );
    if (gop.found_existing) return gop.key_ptr.*;

    const new_off: Path = @enumFromInt(pt.path_components.items.len);

    pt.path_components.items.len += new.len;
    pt.path_components.appendAssumeCapacity(@enumFromInt(0));

    gop.key_ptr.* = new_off;

    return new_off;
}

pub fn ArrayHashMap(T: type) type {
    return std.AutoArrayHashMapUnmanaged(Path, T);
}

pub fn HashMap(T: type) type {
    return std.AutoHashMapUnmanaged(Path, T);
}

pub const Path = enum(u32) {
    _,

    const Map = std.HashMapUnmanaged(
        Path,
        void,
        MapContext,
        std.hash_map.default_max_load_percentage,
    );

    const MapContext = struct {
        components: []const String,

        pub fn eql(_: @This(), a: Path, b: Path) bool {
            return a == b;
        }

        pub fn hash(ctx: @This(), key: Path) u64 {
            return std.hash_map.hashString(
                mem.sliceAsBytes(mem.sliceTo(
                    ctx.components[@intFromEnum(key)..],
                    @enumFromInt(0),
                )),
            );
        }
    };

    const MapIndexAdapter = struct {
        components: []const String,

        pub fn eql(ctx: @This(), a: []const u8, b: Path) bool {
            return mem.eql(u8, a, mem.sliceAsBytes(
                mem.sliceTo(
                    ctx.components[@intFromEnum(b)..],
                    @enumFromInt(0),
                ),
            ));
        }

        pub fn hash(_: @This(), adapted_key: []const u8) u64 {
            assert(mem.indexOfScalar(
                String,
                @alignCast(mem.bytesAsSlice(String, adapted_key)),
                @enumFromInt(0),
            ) == null);
            return std.hash_map.hashString(adapted_key);
        }
    };

    pub fn slice(index: Path, pt: *const PathTable) []const String {
        const start_slice = pt.path_components.items[@intFromEnum(index)..];
        return start_slice[0..mem.indexOfScalar(String, start_slice, @enumFromInt(0)).?];
    }

    // pub fn bytesSlice(
    //     index: Path,
    //     st: *const StringTable,
    //     pt: *const PathTable,
    //     buf: []u8,
    //     sep: u8,
    //     // extra path component to add at the end
    //     name: ?StringTable.String,
    // ) usize {
    //     var out = std.ArrayListUnmanaged(u8).initBuffer(buf);
    //     const components = index.slice(pt);
    //     for (components) |c| {
    //         const bytes = c.slice(st);
    //         out.appendSliceAssumeCapacity(bytes);
    //         out.appendAssumeCapacity(sep);
    //     }

    //     if (name) |n| out.appendSliceAssumeCapacity(n.slice(st));
    //     return out.items.len;
    // }

    pub fn fmt(
        p: Path,
        st: *const StringTable,
        pt: *const PathTable,
        prefix: ?[]const u8,
        trailing_slash: bool,
    ) Path.Formatter {
        return .{
            .p = p,
            .st = st,
            .pt = pt,
            .prefix = prefix,
            .slash = trailing_slash,
        };
    }

    pub const Formatter = struct {
        p: Path,
        st: *const StringTable,
        pt: *const PathTable,
        prefix: ?[]const u8,
        slash: bool,

        pub fn format(
            f: Path.Formatter,
            comptime arg: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            if (arg.len > 0) @compileError("path.fmt wants no format specifier");

            _ = options;

            if (f.prefix) |p| {
                if (p.len > 0) {
                    try writer.writeAll(p);
                    if (p[p.len - 1] != '/') {
                        try writer.writeAll("/");
                    }
                }
            }

            const path_slice = f.p.slice(f.pt);
            for (path_slice, 0..) |c, idx| {
                try writer.writeAll(c.slice(f.st));
                if (f.slash or idx < path_slice.len - 1) {
                    try writer.writeAll("/");
                }
            }
        }
    };
};

test PathTable {
    const gpa = std.testing.allocator;

    var string_table: StringTable = .empty;
    defer string_table.deinit(gpa);

    // required by path_table
    _ = try string_table.intern(gpa, "");

    var path_table: PathTable = .empty;
    defer path_table.deinit(gpa);

    const s1 = "a/b/c/d";
    try std.testing.expectEqual(null, path_table.getPath(&string_table, s1));
    const p1 = try path_table.internPath(gpa, &string_table, s1);
    try std.testing.expectEqual(path_table.getPath(&string_table, s1), p1);

    const s2 = "1/2/3/4/";
    try std.testing.expectEqual(null, path_table.getPath(&string_table, s2));
    const p2 = try path_table.internPath(gpa, &string_table, s2);
    try std.testing.expectEqual(p2, path_table.getPath(&string_table, s2));
    try std.testing.expect(p1 != p2);

    const s3 = "1/2/3/4";
    try std.testing.expectEqual(p2, path_table.getPath(&string_table, s3));
    const p3 = try path_table.internPath(gpa, &string_table, s3);
    try std.testing.expectEqual(p3, path_table.getPath(&string_table, s3));
    try std.testing.expectEqual(p2, p3);
}

// test StringTableHashMap {
//     const gpa = std.testing.allocator;

//     const Color = enum { yellow, red, orange };

//     inline for (&.{ StringTableArrayHashMap, StringTableHashMap }) |Map| {
//         var fruit_color: Map(Color) = .empty;
//         defer fruit_color.deinit(gpa);

//         var string_table: PathTable = .empty;
//         defer string_table.deinit(gpa);

//         const banana = try string_table.intern(gpa, "banana");
//         const apple = try string_table.intern(gpa, "apple");
//         const melon = try string_table.intern(gpa, "melon");

//         try fruit_color.put(gpa, banana, .yellow);
//         try fruit_color.put(gpa, apple, .red);
//         try fruit_color.put(gpa, melon, .orange);

//         try std.testing.expectEqual(fruit_color.get(banana).?, .yellow);
//         try std.testing.expectEqual(fruit_color.get(apple).?, .red);
//         try std.testing.expectEqual(fruit_color.get(melon).?, .orange);
//     }
// }
