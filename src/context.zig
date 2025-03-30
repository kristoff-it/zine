const context = @This();

const std = @import("std");
const scripty = @import("scripty");
const superhtml = @import("superhtml");
const ziggy = @import("ziggy");
const root = @import("root.zig");
const doctypes = @import("context/doctypes.zig");
const Variant = @import("Variant.zig");
const Allocator = std.mem.Allocator;
const Ctx = superhtml.utils.Ctx;

pub const AssetKindUnion = union(Asset.Kind) {
    site,
    page: u32, // variant_id
    build,
};

pub const ScriptyParam = doctypes.ScriptyParam;
pub const Signature = doctypes.Signature;

pub const md = @import("context/markdown.zig");

pub const Template = @import("context/Template.zig");
pub const Site = @import("context/Site.zig");
pub const Page = @import("context/Page.zig");
pub const Build = @import("context/Build.zig");
pub const Git = @import("context/Git.zig");
pub const Asset = @import("context/Asset.zig");
pub const DateTime = @import("context/DateTime.zig");
pub const String = @import("context/String.zig");
pub const Bool = @import("context/Bool.zig");
pub const Int = @import("context/Int.zig");
pub const Float = @import("context/Float.zig");
pub const Map = @import("context/Map.zig");
// pub const Slice = @import("context/Slice.zig");
pub const Optional = @import("context/Optional.zig");
pub const Iterator = @import("context/Iterator.zig");
pub const Array = @import("context/Array.zig");

pub const Value = union(enum) {
    template: *const Template,
    site: *const Site,
    page: *const Page,
    ctx: Ctx(Value),
    alternative: Page.Alternative,
    content_section: Page.ContentSection,
    footnote: Page.Footnote,
    build: *const Build,
    git: Git,
    asset: Asset,
    map: Map,
    // slice: Slice,
    optional: ?*const context.Optional,
    string: String,
    date: DateTime,
    bool: context.Bool,
    int: Int,
    float: Float,
    iterator: *context.Iterator,
    array: Array,
    map_kv: Map.KV,
    err: []const u8,

    pub const Bool = context.Bool;
    pub const Optional = context.Optional;
    pub const Iterator = context.Iterator;

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

    pub fn fromStringLiteral(s: []const u8) Value {
        return .{ .string = .{ .value = s } };
    }

    pub fn fromNumberLiteral(bytes: []const u8) Value {
        const num = std.fmt.parseInt(i64, bytes, 10) catch {
            return .{ .err = "error parsing numeric literal" };
        };
        return .{ .int = .{ .value = num } };
    }

    pub fn fromBooleanLiteral(b: bool) Value {
        return .{ .bool = .{ .value = b } };
    }

    pub fn fromZiggy(gpa: Allocator, value: ziggy.dynamic.Value) !Value {
        switch (value) {
            .null => return .{ .optional = null },
            .bool => |b| return .{ .bool = .{ .value = b } },
            .integer => |i| return .{ .int = .{ .value = i } },
            .bytes => |s| return .{ .string = .{ .value = s } },
            .array => |a| return .{
                .iterator = try Value.Iterator.fromArray(
                    gpa,
                    (try Array.init(gpa, ziggy.dynamic.Value, a)).array,
                ),
            },
            .tag => |t| {
                std.debug.assert(std.mem.eql(u8, t.name, "date"));
                const date = DateTime.init(t.bytes) catch {
                    return .{ .err = "error parsing date" };
                };
                return Value.from(gpa, date);
            },
            .kv => |kv| return .{ .map = .{ .value = kv } },
            inline else => |_, t| @panic("TODO: implement" ++ @tagName(t) ++ "support in dynamic data"),
        }
    }

    pub fn from(gpa: Allocator, v: anytype) !Value {
        return switch (@TypeOf(v)) {
            *Template => .{ .template = v },
            *const Template => .{ .template = v },
            *const Site => .{ .site = v },
            *const Page, *Page => .{ .page = v },
            Page.Alternative => .{ .alternative = v },
            Page.ContentSection => .{ .content_section = v },
            Page.Footnote => .{ .footnote = v },
            *const Build => .{ .build = v },
            Git => .{ .git = v },
            Ctx(Value) => .{ .ctx = v },
            Asset => .{ .asset = v },
            DateTime => .{ .date = v },
            []const u8, []u8 => .{ .string = .{ .value = v } },
            bool => .{ .bool = .{ .value = v } },
            i64, usize => .{ .int = .{ .value = @intCast(v) } },
            ziggy.dynamic.Value => try fromZiggy(gpa, v),
            Map.ZiggyMap => .{ .map = .{ .value = v } },
            Map.KV => .{ .map_kv = v },
            *const context.Optional => .{ .optional = v },
            ?*const context.Optional => if (v) |opt|
                opt.value
            else
                .{ .err = "$if is not set" },
            ?[]const u8 => if (v) |opt|
                try context.Optional.init(gpa, opt)
            else
                context.Optional.Null,
            Value => v,
            ?Value => if (v) |opt|
                try context.Optional.init(gpa, opt)
            else
                context.Optional.Null,
            ?*context.Iterator => if (v) |opt| .{
                .iterator = opt,
            } else .{ .err = "$loop is not set" },
            *context.Iterator => .{ .iterator = v },
            []const []const u8 => try Array.init(gpa, []const u8, v),

            // .{
            //     .iterator = try context.Iterator.init(gpa, .{
            //         .string_it = .{ .items = v },
            //     }),
            // },

            []const Page.Alternative => try Array.init(gpa, Page.Alternative, v),
            []Page.ContentSection => try Array.init(gpa, Page.ContentSection, v),
            []Page.Footnote => try Array.init(gpa, Page.Footnote, v),
            else => @compileError("TODO: implement Value.from for " ++ @typeName(@TypeOf(v))),
        };
    }

    pub const call = scripty.defaultCall(Value, Template);
    pub fn dot(
        self: *Value,
        gpa: Allocator,
        path: []const u8,
    ) error{OutOfMemory}!Value {
        switch (self.*) {
            // .map_kv,
            .string,
            .bool,
            .int,
            .float,
            .err,
            .date,
            .optional,
            => return .{ .err = "field access on primitive value" },
            // .optional => return .{ .err = "field access on optional value" },
            .asset => return .{ .err = "field access on asset value" },
            // .iteration_element => return
            // .iterator_element => |*v| return v.dot(gpa, path),
            inline else => |v| return v.dot(gpa, path),
        }
    }
};

pub fn stripTrailingSlash(path: []const u8) []const u8 {
    if (path[path.len - 1] == '/') return path[0 .. path.len - 1];
    return path;
}
