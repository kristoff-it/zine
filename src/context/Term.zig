const Term = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const scripty = @import("scripty");
const context = @import("../context.zig");
const Value = context.Value;
const String = context.String;
const Int = context.Int;
const Array = context.Array;
const Signature = @import("doctypes.zig").Signature;

pub const dot = scripty.defaultDot(Term, Value, false);

name: []const u8,
slug: []const u8,
_meta: struct {
    variant_id: u32,
    taxonomy_idx: u32,
},

pub const docs_description =
    \\A term within a taxonomy (e.g., "rust" within the "tags" taxonomy).
    \\
    \\Each term has a name, a URL-safe slug, and a list of pages
    \\that have this term.
;

pub const Fields = struct {
    pub const name =
        \\The display name of the term.
    ;
    pub const slug =
        \\The URL-safe slug of the term.
    ;
};

pub const Builtins = struct {
    pub const pages = struct {
        pub const signature: Signature = .{
            .ret = .{ .Many = .Page },
        };
        pub const docs_description =
            \\Returns all pages that have this term, sorted by date (newest first).
        ;
        pub const examples =
            \\<ul :loop="$page.taxonomyTerm?().pages()">
            \\  <li :text="$loop.it.title"></li>
            \\</ul>
        ;
        pub fn call(
            t: Term,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const v = &ctx._meta.build.variants[t._meta.variant_id];
            const ti = &v.taxonomy_indices[t._meta.taxonomy_idx];
            const td = ti.terms.getPtr(t.slug) orelse return .{
                .err = "term not found",
            };

            const page_values = try gpa.alloc(Value, td.pages.items.len);
            for (td.pages.items, 0..) |page_idx, i| {
                page_values[i] = .{ .page = &v.pages.items[page_idx] };
            }

            return Array.init(gpa, Value, page_values);
        }
    };

    pub const count = struct {
        pub const signature: Signature = .{
            .ret = .Int,
        };
        pub const docs_description =
            \\Returns the number of pages that have this term.
        ;
        pub const examples =
            \\<span :text="$loop.it.count()"></span>
        ;
        pub fn call(
            t: Term,
            _: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const v = &ctx._meta.build.variants[t._meta.variant_id];
            const ti = &v.taxonomy_indices[t._meta.taxonomy_idx];
            const td = ti.terms.getPtr(t.slug) orelse return .{
                .err = "term not found",
            };

            return .{ .int = .{ .value = @intCast(td.pages.items.len) } };
        }
    };

    pub const link = struct {
        pub const signature: Signature = .{
            .ret = .String,
        };
        pub const docs_description =
            \\Returns the URL of the term page.
        ;
        pub const examples =
            \\<a href="$loop.it.link()" :text="$loop.it.name"></a>
        ;
        pub fn call(
            t: Term,
            gpa: Allocator,
            ctx: *const context.Template,
            args: []const Value,
        ) context.CallError!Value {
            if (args.len != 0) return .{ .err = "expected 0 arguments" };

            const v = &ctx._meta.build.variants[t._meta.variant_id];
            const ti = &v.taxonomy_indices[t._meta.taxonomy_idx];

            var aw: Writer.Allocating = .init(gpa);
            ctx.printLinkPrefix(
                &aw.writer,
                t._meta.variant_id,
                false,
            ) catch return error.OutOfMemory;
            aw.writer.print("{s}/{s}/", .{
                ti.name,
                t.slug,
            }) catch return error.OutOfMemory;
            return String.init(aw.written());
        }
    };
};
