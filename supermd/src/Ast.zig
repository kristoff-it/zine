const Ast = @This();

const std = @import("std");
const scripty = @import("scripty");
const superhtml = @import("superhtml");
const supermd = @import("root.zig");
const html = superhtml.html;
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
ids: std.StringArrayHashMapUnmanaged(Node) = .{},
arena: std.heap.ArenaAllocator.State,

pub const Error = struct {
    main: Range,
    kind: Kind,

    pub const Kind = union(enum) {
        html_is_forbidden,
        nested_section_directive,
        section_must_not_have_text,

        end_section_in_heading,
        must_be_first_under_blockquote,
        must_be_first_under_heading,
        must_have_id,
        invalid_ref,

        expression_in_image_syntax,
        empty_expression,

        scripty: struct {
            span: Span,
            err: []const u8,
        },

        html: html.Ast.Error,
    };
};

pub fn deinit(a: Ast, gpa: Allocator) void {
    // TODO: stop leaking the cmark ast
    a.arena.promote(gpa).deinit();
}

pub fn init(gpa: Allocator, src: []const u8) error{OutOfMemory}!Ast {
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

    for (p.referenced_ids.keys()) |k| {
        if (!p.ids.contains(k)) {
            try p.errors.append(arena, .{
                .main = p.referenced_ids.get(k).?.range(),
                .kind = .invalid_ref,
            });
        }
    }

    return .{
        .md = ast,
        .errors = try p.errors.toOwnedSlice(gpa),
        .ids = p.ids,
        .arena = arena_impl.state,
    };
}

const Parser = struct {
    gpa: Allocator,
    errors: std.ArrayListUnmanaged(Error) = .{},
    ids: std.StringArrayHashMapUnmanaged(Node) = .{},
    referenced_ids: std.StringArrayHashMapUnmanaged(Node) = .{},
    vm: ScriptyVM = .{},

    pub fn analyzeHeading(p: *Parser, h: Node) !void {
        const link = h.firstChild() orelse return;

        var next: ?Node = link;
        blk: {
            if (link.nodeType() != .LINK) break :blk;
            next = link.nextSibling();
            const src = link.link() orelse break :blk;
            const directive = try p.runScript(link, src) orelse break :blk;
            switch (directive.kind) {
                else => break :blk,
                .block => {
                    try p.addError(
                        link.range(),
                        .must_be_first_under_blockquote,
                    );
                    return;
                },
                .heading => {
                    if (directive.id) |id| try p.ids.put(p.gpa, id, h);
                    _ = try h.setDirective(p.gpa, directive, false);
                },
                .section => |sect| {
                    if (sect.end != null) {
                        try p.addError(link.range(), .end_section_in_heading);
                        return;
                    }

                    const id = directive.id orelse {
                        try p.addError(link.range(), .must_have_id);
                        return;
                    };

                    try p.ids.put(p.gpa, id, h);

                    // Copies the directive.
                    _ = try h.setDirective(p.gpa, directive, true);

                    // We mutate the original one to a link to the
                    // block, useful both for sticky headings and
                    // for generally making it easier for users to
                    // deep link the content.
                    directive.id = null;
                    directive.attrs = &.{};
                    directive.kind = .{
                        .link = .{
                            .src = .{ .url = "" },
                            .ref = id,
                        },
                    };
                },
            }
        }

        try p.analyzeSiblings(next, h);
    }

    pub fn analyzeParagraph(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeCodeBlock(p: *Parser, block: Node) !void {
        const fence = block.fenceInfo() orelse return;
        if (std.mem.startsWith(u8, fence, "=html")) {
            const src = block.literal() orelse return;
            const ast = try html.Ast.init(p.gpa, src, .html);
            defer ast.deinit(p.gpa);
            for (ast.errors) |err| {
                const md_range = block.range();
                const html_range = err.main_location.range(src);

                try p.errors.append(p.gpa, .{
                    .main = .{
                        .start = .{
                            .row = md_range.start.row + 1 + html_range.start.row,
                            .col = 1 + html_range.start.col,
                        },
                        .end = .{
                            .row = md_range.start.row + 1 + html_range.end.row,
                            .col = 1 + html_range.end.col,
                        },
                    },
                    .kind = .{ .html = err },
                });
            }
        }
        // try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeList(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeCustomBlock(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }
    pub fn analyzeBlockQuote(p: *Parser, quote: Node) !void {
        const para_or_h = quote.firstChild() orelse return;
        std.debug.assert(para_or_h.nodeType() == .PARAGRAPH or
            para_or_h.nodeType() == .HEADING);
        const link = para_or_h.firstChild() orelse return;
        var next: ?Node = link;
        blk: {
            if (link.nodeType() != .LINK) break :blk;
            next = link.nextSibling() orelse para_or_h.nextSibling();
            const src = link.link() orelse break :blk;
            const directive = try p.runScript(link, src) orelse break :blk;
            switch (directive.kind) {
                else => break :blk,
                .block => {
                    _ = try quote.setDirective(p.gpa, directive, false);
                    if (directive.id) |id| try p.ids.put(p.gpa, id, quote);

                    // link.unlink();
                    // const h1 = try Node.create(.HEADING);
                    // try h1.prependChild(link);
                    // try quote.prependChild(h1);
                },
            }
        }

        try p.analyzeSiblings(next, quote);
    }
    pub fn analyzeItem(p: *Parser, block: Node) !void {
        try p.analyzeSiblings(block.firstChild(), block);
    }

    pub fn analyzeSiblings(p: *Parser, start: ?Node, stop: Node) error{OutOfMemory}!void {
        var current = start;
        while (current) |n| {
            const kind = n.nodeType();
            if (kind == .IMAGE or kind == .LINK) {
                current = n.next(stop);
            } else {
                current = n.nextSibling();
            }
            switch (kind) {
                .BLOCK_QUOTE => try p.analyzeBlockQuote(n),
                .LIST => try p.analyzeList(n),
                .ITEM => try p.analyzeItem(n),
                .CODE_BLOCK => try p.analyzeCodeBlock(n),
                .HTML_BLOCK => try p.addError(n.range(), .html_is_forbidden),
                .CUSTOM_BLOCK => try p.analyzeCustomBlock(n),
                .PARAGRAPH => try p.analyzeParagraph(n),
                .HEADING => try p.analyzeHeading(n),
                .IMAGE => {
                    const src = n.link() orelse return;
                    switch (src[0]) {
                        '$' => {
                            try p.addError(n.range(), .expression_in_image_syntax);
                            continue;
                        },
                        '/' => {
                            var d: Directive = .{
                                .kind = .{
                                    .image = .{
                                        .src = .{ .site_asset = src[1..] },
                                    },
                                },
                            };
                            _ = try n.setDirective(p.gpa, &d, true);
                        },
                        else => {
                            if (std.mem.indexOf(u8, src, "://") != null) {
                                _ = std.Uri.parse(src) catch {
                                    try p.addError(n.range(), .{
                                        .scripty = .{
                                            .span = .{
                                                .start = 0,
                                                .end = @intCast(src.len),
                                            },
                                            .err = "invalid URL",
                                        },
                                    });
                                    continue;
                                };
                                var d: Directive = .{
                                    .kind = .{
                                        .image = .{
                                            .src = .{ .url = src },
                                        },
                                    },
                                };
                                _ = try n.setDirective(p.gpa, &d, true);
                            }

                            var d: Directive = .{
                                .kind = .{
                                    .image = .{
                                        .src = .{
                                            .page_asset = src,
                                        },
                                    },
                                },
                            };
                            _ = try n.setDirective(p.gpa, &d, true);
                        },
                    }
                },
                .LINK => {
                    const src = n.link() orelse return;
                    const directive = try p.runScript(n, src) orelse return;
                    switch (directive.kind) {
                        else => continue,
                        .heading => {
                            try p.addError(n.range(), .must_be_first_under_heading);
                            continue;
                        },
                        .section => {
                            // A section directive must be the first element in a
                            // markdown paragraph.
                            if (n.prevSibling()) |prev| {
                                _ = prev;
                                try p.addError(n.range(), .nested_section_directive);
                                continue;
                            }

                            // Must not have text inside of it
                            if (n.firstChild()) |child| {
                                try p.addError(
                                    child.range(),
                                    .section_must_not_have_text,
                                );
                            }

                            const parent = n.parent().?;
                            if (parent.nodeType() != .PARAGRAPH) {
                                try p.addError(n.range(), .nested_section_directive);
                                continue;
                            }

                            _ = try parent.setDirective(p.gpa, directive, false);

                            if (directive.id) |id| {
                                try p.ids.put(p.gpa, id, parent);
                            }
                        },
                    }
                },
                else => continue,
            }
        }
    }
    // If the script results in anything other than a Directive,
    // an error is appended and the function will return null.
    pub fn runScript(p: *Parser, n: Node, src: []const u8) !?*Directive {
        if (src.len == 0) {
            try p.addError(n.range(), .empty_expression);
            return null;
        }
        switch (src[0]) {
            '$' => {},
            '#' => {
                var d: Directive = .{
                    .kind = .{
                        .link = .{
                            .ref = src[1..],
                            .src = .self_page,
                        },
                    },
                };
                return n.setDirective(p.gpa, &d, true);
            },
            '/' => {
                var d: Directive = .{
                    .kind = .{
                        .link = .{
                            .src = .{
                                .page = .{ .ref = src[1..], .kind = .absolute },
                            },
                        },
                    },
                };
                return n.setDirective(p.gpa, &d, true);
            },
            '.' => {
                var d: Directive = .{
                    .kind = .{
                        .link = .{
                            .src = .{
                                .page = .{ .ref = src[1..], .kind = .sub },
                            },
                        },
                    },
                };
                return n.setDirective(p.gpa, &d, true);
            },
            else => {
                if (std.mem.indexOf(u8, src, "://") != null) {
                    _ = std.Uri.parse(src) catch {
                        try p.addError(n.range(), .{
                            .scripty = .{
                                .span = .{
                                    .start = 0,
                                    .end = @intCast(src.len),
                                },
                                .err = "invalid URL",
                            },
                        });
                        return null;
                    };
                    var d: Directive = .{
                        .kind = .{
                            .link = .{
                                .src = .{ .url = src },
                                .new = true,
                            },
                        },
                    };
                    return n.setDirective(p.gpa, &d, true);
                }

                var d: Directive = .{
                    .kind = .{
                        .link = .{
                            .src = .{
                                .page = .{ .ref = src, .kind = .sibling },
                            },
                        },
                    },
                };
                return n.setDirective(p.gpa, &d, true);
            },
        }

        var ctx: Content = .{};
        const res = p.vm.run(p.gpa, &ctx, src, .{}) catch |err| {
            std.debug.panic("md scripty err: {}", .{err});
        };
        switch (res.value) {
            .directive => |d| {
                // NOTE: we're returning a pointer to the copy
                if (try d.validate(p.gpa, n)) |err| {
                    try p.addError(n.range(), .{
                        .scripty = .{
                            .span = .{ .start = 0, .end = @intCast(src.len) },
                            .err = err.err,
                        },
                    });
                }

                switch (d.kind) {
                    else => {},
                    .link => |lnk| switch (lnk.src.?) {
                        else => {},
                        .self_page => {
                            const hash = lnk.ref.?;
                            try p.referenced_ids.put(p.gpa, hash, n);
                        },
                    },
                }
                return n.setDirective(p.gpa, d, true);
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
    var it = a.ids.iterator();
    while (it.next()) |kv| {
        const range = kv.value_ptr.range();
        try w.print("ids[{}:{}] = '{s}'\n", .{
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
        \\# [Title]($section.id('foo'))
    ;
    const expected =
        \\ids[1:1] = 'foo'
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
