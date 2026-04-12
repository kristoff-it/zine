const Taxonomy = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const scripty = @import("scripty");
const context = @import("../context.zig");
const Value = context.Value;
const String = context.String;
const Array = context.Array;
const Signature = @import("doctypes.zig").Signature;

pub const dot = scripty.defaultDot(Taxonomy, Value, false);
pub const PassByRef = true;

name: []const u8,
_meta: struct {
    variant_id: u32,
    taxonomy_idx: u32,
},

pub const docs_description =
    \\A taxonomy defined in the site configuration (e.g., "tags").
    \\
    \\Taxonomies organize pages by terms. For example, a "tags" taxonomy
    \\groups pages by their tags.
;

pub const Fields = struct {
    pub const name =
        \\The name of the taxonomy as defined in the site configuration.
    ;
};

pub const Builtins = struct {
    pub const terms = struct {
        pub const signature: Signature = .{
            .ret = .{ .Many = .Term },
        };
        pub const docs_description =
            \\Returns all terms in this taxonomy, sorted alphabetically by name.
        ;
        pub const examples =
            \\<ul :loop="$page.taxonomy?().terms()">
            \\  <li :text="$loop.it.name"></li>
            \\</ul>
        ;
        pub fn call(
            t: *const Taxonomy,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const v = &ctx._meta.build.variants[t._meta.variant_id];
            const ti = &v.taxonomy_indices[t._meta.taxonomy_idx];

            const term_values = try gpa.alloc(Value, ti.terms.count());
            for (ti.terms.values(), 0..) |td, i| {
                term_values[i] = .{
                    .term = .{
                        .name = td.display_name,
                        .slug = td.slug,
                        ._meta = .{
                            .variant_id = t._meta.variant_id,
                            .taxonomy_idx = t._meta.taxonomy_idx,
                        },
                    },
                };
            }

            // Sort alphabetically by name
            std.mem.sort(Value, term_values, {}, struct {
                pub fn lessThan(_: void, a: Value, b: Value) bool {
                    return std.ascii.orderIgnoreCase(a.term.name, b.term.name) == .lt;
                }
            }.lessThan);

            return Array.init(gpa, Value, term_values);
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{
            .ret = .String,
        };
        pub const docs_description =
            \\Returns the URL of the taxonomy list page.
        ;
        pub const examples =
            \\<a href="$site.taxonomy('tags').link()">All Tags</a>
        ;
        pub fn call(
            t: *const Taxonomy,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            var aw: Writer.Allocating = .init(gpa);
            ctx.printLinkPrefix(
                &aw.writer,
                t._meta.variant_id,
                false,
            ) catch return error.OutOfMemory;
            aw.writer.print("{s}/", .{t.name}) catch return error.OutOfMemory;
            return String.init(aw.written());
        }
    };
};
