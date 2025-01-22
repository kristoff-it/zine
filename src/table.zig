const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

pub const StringTable = Table(u8, u32);
pub const PathTable = Table(u32, u32);

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

    const nil: ?StringTable.Element = null;
    try std.testing.expectEqual(string_table.get("strawberry"), nil);
    try std.testing.expectEqual(string_table.get("coconut"), nil);
    try std.testing.expectEqual(string_table.get("lemon"), nil);
}

test "hash maps" {
    const gpa = std.testing.allocator;

    const Color = enum { yellow, red, orange };

    inline for (&.{ StringTable.ArrayHashMap, StringTable.HashMap }) |Map| {
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

// Interned storage of []E, exposes also TableArrayHashMap and TableHashMap.
// E is expected to be an integer type.
// Asserts the zero value of T is never added as it's used for slice termination.
pub fn Table(E: type, Size: type) type {
    if (@typeInfo(E) != .int) @compileError("E must be an integer type, like u8 o u32");
    switch (Size) {
        u16, u32, u64, usize => {},
        else => {
            @compileError("Size is expected to be u16, u32, u64 or usize");
        },
    }

    return struct {
        elements: ArrayList(E),
        element_map: Element.Map,

        const Self = @This();
        pub const empty: Self = .{
            .elements = .empty,
            .element_map = .empty,
        };

        pub fn deinit(st: *Self, gpa: Allocator) void {
            st.elements.deinit(gpa);
            st.element_map.deinit(gpa);
        }

        pub fn get(st: *Self, elements: []const E) ?Element {
            return st.element_map.getKeyAdapted(
                @as([]const E, elements),
                @as(Element.MapIndexAdapter, .{ .elements = st.elements.items }),
            );
        }

        pub fn intern(
            st: *Self,
            gpa: Allocator,
            elements: []const E,
        ) !Element {
            try st.elements.ensureUnusedCapacity(gpa, elements.len + 1);

            const gop = try st.element_map.getOrPutContextAdapted(
                gpa,
                std.mem.sliceAsBytes(elements),
                @as(Element.MapIndexAdapter, .{ .elements = st.elements.items }),
                @as(Element.MapContext, .{ .elements = st.elements.items }),
            );
            if (gop.found_existing) return gop.key_ptr.*;

            const new_off: Element = @enumFromInt(st.elements.items.len);

            st.elements.appendSliceAssumeCapacity(elements);
            st.elements.appendAssumeCapacity(0);

            gop.key_ptr.* = new_off;

            return new_off;
        }

        pub fn ArrayHashMap(V: type) type {
            return std.AutoArrayHashMapUnmanaged(Element, V);
        }

        pub fn HashMap(V: type) type {
            return std.AutoHashMapUnmanaged(Element, V);
        }

        pub const Element = enum(Size) {
            _,

            const Map = std.HashMapUnmanaged(
                Element,
                void,
                MapContext,
                std.hash_map.default_max_load_percentage,
            );

            pub const MapContext = struct {
                elements: []const E,

                pub fn eql(_: @This(), a: Element, b: Element) bool {
                    return a == b;
                }

                pub fn hash(ctx: @This(), key: Element) u64 {
                    switch (E) {
                        u8 => return std.hash_map.hashString(
                            mem.sliceTo(ctx.elements[@intFromEnum(key)..], 0),
                        ),

                        else => return std.hash_map.hashString(
                            mem.sliceAsBytes(mem.sliceTo(ctx.elements[@intFromEnum(key)..], 0)),
                        ),
                    }
                }
            };

            pub const MapIndexAdapter = struct {
                elements: []const E,

                pub fn eql(ctx: @This(), a: []const u8, b: Element) bool {
                    return mem.eql(
                        E,
                        @alignCast(mem.bytesAsSlice(E, a)),
                        mem.sliceTo(ctx.elements[@intFromEnum(b)..], 0),
                    );
                }

                pub fn hash(_: @This(), adapted_key: []const u8) u64 {
                    assert(mem.indexOfScalar(E, @alignCast(mem.bytesAsSlice(E, adapted_key)), 0) == null);
                    return std.hash_map.hashString(adapted_key);
                }
            };

            pub fn slice(index: Element, table: *const Self) [:0]const E {
                const start_slice = table.elements.items[@intFromEnum(index)..];
                return start_slice[0..mem.indexOfScalar(E, start_slice, 0).? :0];
            }
        };
    };
}
