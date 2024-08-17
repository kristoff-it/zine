const Ast = @This();

const std = @import("std");
const scripty = @import("scripty");
const supermd = @import("root.zig");
const c = supermd.c;
const Node = @import("Node.zig");
const Span = supermd.Span;
const Range = supermd.Range;
const Value = supermd.Value;
const Content = supermd.Content;
const Directive = supermd.Directive;
const Allocator = std.mem.Allocator;
const ScriptyVM = scripty.VM(Content, Value);

md: CMarkAst,
errors: []const Error,
sections: std.StringArrayHashMapUnmanaged(Node) = .{},
arena: std.heap.ArenaAllocator.State,

pub const Error = struct {
    main: Range,
    kind: Kind,

    pub const Kind = union(enum) {
        html_is_forbidden,
        block_outside_heading,
        scripty: struct {
            span: Span,
            err: []const u8,
        },
    };
};

pub fn deinit(a: Ast, gpa: Allocator) void {
    // TODO: stop leaking the cmark ast
    a.arena.promote(gpa).deinit();
}

pub fn init(gpa: Allocator, src: []const u8) !Ast {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_impl.allocator();

    var p: Parser = .{ .gpa = arena };
    const ast = cmark(src);
    var current = ast.root.firstChild();
    while (current) |n| : (current = n.nextSibling()) switch (n.nodeType()) {
        .BLOCK_QUOTE => try p.analyzeBlockQuote(n),
        .LIST => try p.analyzeList(n),
        .ITEM => try p.analyzeItem(n),
        .CODE_BLOCK => try p.analyzeCodeBlock(n),
        .HTML_BLOCK => try p.addError(n.range(), .html_is_forbidden),
        .CUSTOM_BLOCK => try p.analyzeCustomBlock(n),
        .PARAGRAPH => try p.analyzeParagraph(n),
        .HEADING => try p.analyzeHeading(n),
        .THEMATIC_BREAK => {},
        .FOOTNOTE_DEFINITION => @panic("TODO: footnotes"),
        else => {},
    };

    return .{
        .md = ast,
        .errors = try p.errors.toOwnedSlice(gpa),
        .sections = p.sections,
        .arena = arena_impl.state,
    };
}

const Parser = struct {
    gpa: Allocator,
    errors: std.ArrayListUnmanaged(Error) = .{},
    sections: std.StringArrayHashMapUnmanaged(Node) = .{},
    vm: ScriptyVM = .{},

    pub fn analyzeHeading(p: *Parser, h: Node) !void {
        const link = h.firstChild() orelse return;

        block: {
            if (link.nodeType() != .LINK) break :block;
            if (link.nextSibling() != null) break :block;
            const src = link.link() orelse break :block;
            if (!std.mem.startsWith(u8, src, "$")) break :block;

            // Heading has this structure:
            // # [Title]($block.id('foo'))

            const directive = try p.runScript(link, src) orelse break :block;

            if (directive.kind == .block) {
                if (directive.id) |id| {
                    try p.sections.put(p.gpa, id, h);
                }
            }
            _ = try h.setDirective(p.gpa, directive);
        }

        try p.analyzeSiblings(link.nextSibling(), h);
    }

    pub fn analyzeParagraph(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeCodeBlock(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeList(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeCustomBlock(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeBlockQuote(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeItem(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }

    pub fn analyzeSiblings(p: *Parser, start: ?Node, stop: Node) !void {
        var current = start;
        while (current) |n| : (current = n.next(stop)) switch (n.nodeType()) {
            .LINK => {
                const src = n.link() orelse return;
                if (!std.mem.startsWith(u8, src, "$")) return;
                const directive = try p.runScript(n, src) orelse return;
                if (directive.kind == .block) {
                    try p.addError(n.range(), .block_outside_heading);
                }
            },
            else => continue,
        };
    }
    // If the script results in anything other than a Directive,
    // an error is appended and the function will return null.
    pub fn runScript(p: *Parser, n: Node, src: []const u8) !?*Directive {
        var ctx: Content = .{};
        const res = p.vm.run(p.gpa, &ctx, src, .{}) catch |err| {
            std.debug.panic("md scripty err: {}", .{err});
        };
        switch (res.value) {
            .directive => |d| {
                // NOTE: we're returning a pointer to the copy
                return n.setDirective(p.gpa, d);
            },
            .err => |msg| {
                try p.addError(n.range(), .{
                    .scripty = .{
                        .span = .{
                            .start = res.loc.start,
                            .end = res.loc.end,
                        },
                        .err = msg,
                    },
                });
                return null;
            },
            else => unreachable,
        }
    }

    pub fn addError(p: *Parser, range: Range, kind: Error.Kind) !void {
        try p.errors.append(p.gpa, .{ .main = range, .kind = kind });
    }
};

// pub fn foo() void {
//     if (maybe_dep_writer) |dep_writer| while (it.next()) |ev| {
//         if (ev.dir == .exit) continue;
//         const node = ev.node;
//         if (node.isLink()) {
//             const src = node.link() orelse continue;
//             if (!std.mem.startsWith(u8, src, "$")) continue;
//             var ctx: md.Content = .{};
//             const res = vm.run(arena, &ctx, src, .{}) catch |err| {
//                 std.debug.panic("md scripty err: {}", .{err});
//             };
//             switch (res.value) {
//                 else => @panic("bad scripty result"),
//                 .directive => |d| {
//                     switch (d.elem) {
//                         else => @panic("bad scripty result"),
//                         .section => {
//                             const p = node.parent() orelse {
//                                 @panic("section must be used in a heading");
//                             };

//                             if (!p.isHeading()) {
//                                 @panic("section must be used in a heading");
//                             }

//                             // TODO: no siblings allowed

//                             try p.setData(arena, d);
//                             try node.replaceWithChild();
//                         },
//                     }
//                 },
//             }
//         } else if (node.isImage()) {
//             const link = node.link() orelse {
//                 @panic("TODO: explain that an image without url was found in the markdown file");
//             };

//             // Skip non-local images
//             if (std.mem.startsWith(u8, link, "http")) continue;

//             const asset_path =
//                 try std.fs.path.join(arena, &.{
//                 md_asset_dir_path,
//                 link,
//             });
//             const offset = md_asset_dir_path.len - md_asset_dir_rel_path.len;
//             const asset_rel_path = asset_path[offset..asset_path.len];

//             std.fs.cwd().access(asset_path, .{}) catch |err| {
//                 std.debug.panic("while parsing page '{s}', unable to find asset '{s}': {s}\n{s}", .{
//                     md_rel_path,
//                     asset_rel_path,
//                     @errorName(err),
//                     if (is_section) "" else
//                     \\NOTE: assets for this page must be placed under a subdirectory that shares the same name with the corresponding markdown file!
//                     ,
//                 });
//             };

//             log.debug("markdown dep: '{s}'", .{asset_path});
//             dep_writer.print("{s} ", .{asset_path}) catch {
//                 std.debug.panic(
//                     "error while writing to dep file file: '{s}'",
//                     .{asset_path},
//                 );
//             };

//             _ = try asset_collector.collect(arena, .{
//                 .kind = .{ .page = md_asset_dir_rel_path },
//                 .ref = link,
//                 .path = asset_path,
//             });
//         }
//     };
// }

pub const Iter = struct {
    it: *c.cmark_iter,

    pub fn init(n: Node) Iter {
        return .{ .it = c.cmark_iter_new(n.n).? };
    }

    pub fn deinit(self: Iter) void {
        c.cmark_iter_free(self.it);
    }

    pub fn reset(self: Iter, current: Node, dir: Event.Dir) void {
        c.cmark_iter_reset(
            self.it,
            current.n,
            switch (dir) {
                .enter => c.CMARK_EVENT_ENTER,
                .exit => c.CMARK_EVENT_EXIT,
            },
        );
    }

    pub const Event = struct {
        dir: Dir,
        node: Node,
        pub const Dir = enum { enter, exit };
    };
    pub fn next(self: Iter) ?Event {
        var exited = false;
        while (true) switch (c.cmark_iter_next(self.it)) {
            c.CMARK_EVENT_DONE => return null,
            c.CMARK_EVENT_EXIT => {
                exited = true;
                break;
            },
            c.CMARK_EVENT_ENTER => break,
            else => unreachable,
        };

        return .{
            .dir = if (exited) .exit else .enter,
            .node = .{ .n = c.cmark_iter_get_node(self.it).? },
        };
    }

    pub fn exit(self: Iter, node: Node) void {
        c.cmark_iter_reset(self.it, node.n, c.CMARK_EVENT_EXIT);
    }
};

const CMarkAst = struct {
    root: Node,
    extensions: [*c]c.cmark_llist,
};

fn cmark(src: []const u8) CMarkAst {
    c.cmark_gfm_core_extensions_ensure_registered();
    const extensions = supermd.cmark_list_syntax_extensions(c.cmark_get_arena_mem_allocator());
    const options = c.CMARK_OPT_DEFAULT | c.CMARK_OPT_SAFE;
    const parser = c.cmark_parser_new(options);
    defer c.cmark_parser_free(parser);

    _ = c.cmark_parser_attach_syntax_extension(
        parser,
        c.cmark_find_syntax_extension("table"),
    );
    c.cmark_parser_feed(parser, src.ptr, src.len);
    const root = c.cmark_parser_finish(parser).?;
    return .{
        .root = .{ .n = root },
        .extensions = extensions,
    };
}

pub fn format(
    a: Ast,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    w: anytype,
) !void {
    _ = fmt;
    _ = options;
    for (a.errors, 0..) |e, i| {
        try w.print("errors[{}] = '{s}' {s} \n", .{
            i, @tagName(e.kind), switch (e.kind) {
                .scripty => |s| s.err,
                else => "",
            },
        });
    }
    var it = a.sections.iterator();
    while (it.next()) |kv| {
        const range = kv.value_ptr.range();
        try w.print("sections[{}:{}] = '{s}'\n", .{
            range.start.row,
            range.start.col,
            kv.key_ptr.*,
        });
    }

    var current: ?Node = a.md.root.firstChild();
    while (current) |n| : (current = n.next(a.md.root)) {
        const directive = n.getDirective() orelse continue;
        const range = n.range();
        try w.print("directive[{}:{}] = '{s}' #{s}\n", .{
            range.start.row,
            range.start.col,
            @tagName(directive.kind),
            directive.id orelse "",
        });
    }
}

test "basics" {
    const case =
        \\# [Title]($block.id('foo'))
    ;
    const expected =
        \\sections[1:1] = 'foo'
        \\directive[1:3] = 'block' #foo
        \\
    ;

    const ast = try Ast.init(std.testing.allocator, case);
    defer ast.deinit(std.testing.allocator);
    try std.testing.expectFmt(expected, "{}", .{ast});
}

test "image" {
    const case =
        \\This is an inline image [alt text]($image.asset('foo.jpg'))
        \\
        \\[this is a block image]($image.asset('bar.jpg'))
        \\
    ;

    const expected =
        \\directive[1:25] = 'image' #
        \\directive[3:1] = 'image' #
        \\
    ;

    const ast = try Ast.init(std.testing.allocator, case);
    defer ast.deinit(std.testing.allocator);
    try std.testing.expectFmt(expected, "{}", .{ast});
}
