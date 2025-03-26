const StringTable = @This();

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

string_bytes: std.ArrayListUnmanaged(u8),
string_map: String.Map,

pub const empty: StringTable = .{
    .string_bytes = .empty,
    .string_map = .empty,
};

pub fn deinit(st: *const StringTable, gpa: Allocator) void {
    var sb = st.string_bytes;
    sb.deinit(gpa);

    var sm = st.string_map;
    sm.deinit(gpa);
}

pub fn get(st: *const StringTable, bytes: []const u8) ?String {
    return st.string_map.getKeyAdapted(
        @as([]const u8, bytes),
        @as(String.MapIndexAdapter, .{ .bytes = st.string_bytes.items }),
    );
}

pub fn intern(
    st: *StringTable,
    gpa: Allocator,
    bytes: []const u8,
) !String {
    const gop = try st.string_map.getOrPutContextAdapted(
        gpa,
        @as([]const u8, bytes),
        @as(String.MapIndexAdapter, .{ .bytes = st.string_bytes.items }),
        @as(String.MapContext, .{ .bytes = st.string_bytes.items }),
    );
    if (gop.found_existing) return gop.key_ptr.*;

    try st.string_bytes.ensureUnusedCapacity(gpa, bytes.len + 1);
    const new_off: String = @enumFromInt(st.string_bytes.items.len);

    st.string_bytes.appendSliceAssumeCapacity(bytes);
    st.string_bytes.appendAssumeCapacity(0);

    gop.key_ptr.* = new_off;

    return new_off;
}

pub fn ArrayHashMap(T: type) type {
    return std.AutoArrayHashMapUnmanaged(String, T);
}

pub fn HashMap(T: type) type {
    return std.AutoHashMapUnmanaged(String, T);
}

pub const String = enum(u32) {
    _,

    const Map = std.HashMapUnmanaged(
        String,
        void,
        MapContext,
        std.hash_map.default_max_load_percentage,
    );

    const MapContext = struct {
        bytes: []const u8,

        pub fn eql(_: @This(), a: String, b: String) bool {
            return a == b;
        }

        pub fn hash(ctx: @This(), key: String) u64 {
            return std.hash_map.hashString(mem.sliceTo(ctx.bytes[@intFromEnum(key)..], 0));
        }
    };

    const MapIndexAdapter = struct {
        bytes: []const u8,

        pub fn eql(ctx: @This(), a: []const u8, b: String) bool {
            return mem.eql(u8, a, mem.sliceTo(ctx.bytes[@intFromEnum(b)..], 0));
        }

        pub fn hash(_: @This(), adapted_key: []const u8) u64 {
            assert(mem.indexOfScalar(u8, adapted_key, 0) == null);
            return std.hash_map.hashString(adapted_key);
        }
    };

    pub fn slice(index: String, st: *const StringTable) [:0]const u8 {
        const start_slice = st.string_bytes.items[@intFromEnum(index)..];
        return start_slice[0..mem.indexOfScalar(u8, start_slice, 0).? :0];
    }
};

test StringTable {
    const gpa = std.testing.allocator;

    var string_table: StringTable = .empty;
    defer string_table.deinit(gpa);

    const banana = try string_table.intern(gpa, "banana");
    const apple = try string_table.intern(gpa, "apple");
    const melon = try string_table.intern(gpa, "melon");

    try std.testing.expectEqual(banana, string_table.get("banana").?);
    try std.testing.expectEqual(apple, string_table.get("apple").?);
    try std.testing.expectEqual(melon, string_table.get("melon").?);

    try std.testing.expectEqual(banana, try string_table.intern(gpa, "banana"));
    try std.testing.expectEqual(apple, try string_table.intern(gpa, "apple"));
    try std.testing.expectEqual(melon, try string_table.intern(gpa, "melon"));

    try std.testing.expect(banana != apple);
    try std.testing.expect(apple != melon);
    try std.testing.expect(melon != banana);

    try std.testing.expectEqual(null, string_table.get("strawberry"));
    try std.testing.expectEqual(null, string_table.get("coconut"));
    try std.testing.expectEqual(null, string_table.get("lemon"));
}

test HashMap {
    const gpa = std.testing.allocator;

    const Color = enum { yellow, red, orange };

    inline for (&.{ ArrayHashMap, HashMap }) |Map| {
        var fruit_color: Map(Color) = .empty;
        defer fruit_color.deinit(gpa);

        var string_table: StringTable = .empty;
        defer string_table.deinit(gpa);

        const banana = try string_table.intern(gpa, "banana");
        const apple = try string_table.intern(gpa, "apple");
        const melon = try string_table.intern(gpa, "melon");

        try fruit_color.put(gpa, banana, .yellow);
        try fruit_color.put(gpa, apple, .red);
        try fruit_color.put(gpa, melon, .orange);

        try std.testing.expectEqual(fruit_color.get(banana).?, .yellow);
        try std.testing.expectEqual(fruit_color.get(apple).?, .red);
        try std.testing.expectEqual(fruit_color.get(melon).?, .orange);
    }
}
