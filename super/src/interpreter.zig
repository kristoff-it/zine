const std = @import("std");
const scripty = @import("scripty");
const errors = @import("errors.zig");
const template = @import("template.zig");

const SuperTemplate = template.SuperTemplate;
const SuperTree = @import("SuperTree.zig");
const SuperNode = SuperTree.SuperNode;
const ScriptyVM = scripty.ScriptyVM;

pub const Exception = error{
    Done,
    Quota,
    OutOfMemory,
    WantTemplate,
    WantSnippet,

    // Unrecoverable errors
    Fatal,
    ErrIO,
    OutIO,
};

pub fn SuperVM(comptime Context: type, comptime Value: type) type {
    return struct {
        arena: std.mem.Allocator,
        content_name: []const u8,
        out: OutWriter,
        err: ErrWriter,

        state: State,
        quota: usize = 100,
        templates: std.ArrayListUnmanaged(Template) = .{},
        ctx: *Context,
        scripty_vm: ScriptyVM(Context, Value) = .{},

        // discovering templates state
        seen_templates: std.StringHashMapUnmanaged(struct {
            extend: *SuperNode,
            idx: usize,
        }) = .{},

        const OutWriter = std.io.BufferedWriter(4096, std.fs.File.Writer).Writer;
        const ErrWriter = errors.ErrWriter;

        pub const Template = SuperTemplate(Context, Value, OutWriter);
        pub const State = union(enum) {
            init: TemplateCartridge,
            discovering_templates,
            running,
            done,
            fatal,
            want_template: []const u8, // template name
            loaded_template: TemplateCartridge,
            want_snippet: []const u8, // snippet name

        };

        pub const TemplateCartridge = struct {
            name: []const u8,
            path: []const u8,
            html: []const u8,
        };

        pub fn init(
            arena: std.mem.Allocator,
            context: *Context,
            layout_name: []const u8,
            layout_path: []const u8,
            layout_html: []const u8,
            content_name: []const u8,
            out_writer: OutWriter,
            err_writer: ErrWriter,
        ) @This() {
            return .{
                .arena = arena,
                .content_name = content_name,
                .ctx = context,
                .out = out_writer,
                .err = err_writer,
                .state = .{
                    .init = .{
                        .name = layout_name,
                        .path = layout_path,
                        .html = layout_html,
                    },
                },
            };
        }

        // When state is `WantTemplate`, call this function
        // to get the name of the wanted template.
        pub fn wantedTemplateName(self: @This()) []const u8 {
            return self.state.want_template;
        }

        // When state is `WantTemplate`, call this function to prepare the VM
        // for loading the requested template.
        pub fn insertTemplate(self: *@This(), path: []const u8, html: []const u8) void {
            const name = self.state.want_template;
            self.state = .{ .loaded_template = .{
                .name = name,
                .path = path,
                .html = html,
            } };
        }

        pub fn setQuota(self: *@This(), q: usize) void {
            self.quota = q;
        }

        // Call this function to report an evaluation trace when the caller
        // failed to fetch a requested resource (eg templates, snippets, ...)
        pub fn resourceFetchError(self: *@This(), err: anyerror) void {
            assert(@src(), self.state == .want_template);
            self.state = .fatal;
            std.debug.panic(
                "TODO: error reporting in resourceFetchError: {s}",
                .{@errorName(err)},
            );
        }

        pub fn run(self: *@This()) Exception!void {
            if (self.state == .fatal) return error.Fatal;

            // This is where we catch unhandled errors and move the machine
            // state to .fatal
            self.runInternal() catch |err| {
                switch (err) {
                    error.OutOfMemory,
                    error.Fatal,
                    error.OutIO,
                    error.ErrIO,
                    => self.state = .fatal,
                    error.WantTemplate,
                    error.WantSnippet,
                    error.Quota,
                    error.Done,
                    => {},
                }
                return err;
            };
        }

        fn runInternal(self: *@This()) Exception!void {
            while (true) switch (self.state) {
                .done, .want_template, .want_snippet, .fatal => unreachable,
                .running => break,
                .init => self.loadLayout() catch {
                    // NOTE: this code assumes:
                    //       - erroring loadLayout doesn't change state
                    //       - fatalTrace only reads name and path
                    var fakeTemplate: Template = undefined;
                    fakeTemplate.name = self.state.init.name;
                    fakeTemplate.path = self.state.init.path;
                    return fatalTrace(self.content_name, &.{fakeTemplate}, self.err);
                },
                .discovering_templates => try self.discoverTemplates(),
                .loaded_template => try self.loadTemplate(),
            };

            // current template index
            var idx: usize = self.templates.items.len - 1;
            while (self.quota > 0) : (self.quota -= 1) {
                const t = &self.templates.items[idx];

                const continuation = t.eval(&self.scripty_vm, self.ctx, self.out, self.err) catch |err| switch (err) {
                    error.OutOfMemory,
                    error.OutIO,
                    error.ErrIO,
                    => |e| return e,
                    error.Fatal,
                    error.FatalShowInterface,
                    => {
                        if (err == error.FatalShowInterface) {
                            try self.templates.items[idx + 1].showInterface(self.err);
                        }
                        return fatalTrace(self.content_name, self.templates.items[0 .. idx + 1], self.err);
                    },
                };

                switch (continuation) {
                    .super => |s| {
                        if (idx == 0) {
                            @panic("programming error: layout acting like it has <super/> in it");
                        }
                        idx -= 1;

                        const super_template = &self.templates.items[idx];
                        super_template.activateBlock(
                            &self.scripty_vm,
                            self.ctx,
                            s.superBlock().id_value.unquote(t.html),
                            self.out,
                            self.err,
                        ) catch {
                            @panic("TODO: error reporting");
                        };
                    },
                    .end => {
                        if (t.extends == null) break;
                        idx += 1;
                        assert(@src(), idx < self.templates.items.len);
                    },
                }
            } else {
                try errors.header(self.err, "INFINITE LOOP",
                    \\Super encountered a condition that caused an infinite loop.
                    \\This should not have happened, please report this error to 
                    \\the maintainers.
                );
                return error.Fatal;
            }

            for (self.templates.items) |l| l.finalCheck();
            return error.Done;
        }

        fn loadLayout(self: *@This()) errors.FatalOOM!void {
            const cartridge = self.state.init;
            const layout_tree = try SuperTree.init(
                self.arena,
                self.err,
                cartridge.name,
                cartridge.path,
                cartridge.html,
            );
            const layout = try Template.init(
                self.arena,
                layout_tree,
                .layout,
            );

            try self.templates.append(self.arena, layout);
            self.state = .discovering_templates;
        }

        const DiscoverException = error{ OutOfMemory, WantTemplate } || errors.Fatal;
        fn discoverTemplates(self: *@This()) DiscoverException!void {
            var current_idx = self.templates.items.len - 1;
            while (self.templates.items[current_idx].extends) |ext| : ({
                current_idx = self.templates.items.len - 1;
            }) {
                const current = &self.templates.items[current_idx];
                _ = current.eval_frame.pop();
                const template_value = ext.templateValue();
                const template_name = template_value.unquote(current.html);

                const gop = try self.seen_templates.getOrPut(self.arena, template_name);
                if (gop.found_existing) {
                    current.reportError(
                        self.err,
                        template_value.node,
                        "infinite_loop",
                        "EXTENSION LOOP DETECTED",
                        "We were trying to load the same template twice!",
                    ) catch {};

                    const ctx = gop.value_ptr;
                    try self.templates.items[ctx.idx].diagnostic(
                        self.err,
                        "note: the template was previously found here:",
                        ctx.extend.templateValue().node,
                    );

                    return fatalTrace(
                        self.content_name,
                        self.templates.items[0 .. current_idx + 1],
                        self.err,
                    );
                }

                gop.value_ptr.* = .{ .extend = ext, .idx = current_idx };

                self.state = .{ .want_template = template_name };
                return error.WantTemplate;
            }

            try self.validateInterfaces();
            self.state = .running;
        }

        fn loadTemplate(self: *@This()) !void {
            const cartridge = self.state.loaded_template;
            const tree = try SuperTree.init(
                self.arena,
                self.err,
                cartridge.name,
                cartridge.path,
                cartridge.html,
            );

            const t = try Template.init(
                self.arena,
                tree,
                .template,
            );

            try self.templates.append(self.arena, t);

            self.state = .discovering_templates;
        }

        fn validateInterfaces(self: @This()) !void {
            const templates = self.templates.items;
            assert(@src(), templates.len > 0);
            if (templates.len == 1) return;
            var idx = templates.len - 1;
            while (idx > 0) : (idx -= 1) {
                const extended = templates[idx];
                const super = templates[idx - 1];

                var it = extended.interface.iterator();
                var blocks = try super.blocks.clone(self.arena);
                defer blocks.deinit(self.arena);
                while (it.next()) |kv| {
                    const block = blocks.fetchRemove(kv.key_ptr.*) orelse {
                        try errors.header(self.err, "MISSING BLOCK",
                            \\Missing block in super template.
                            \\All <super/> blocks from the parent template must be defined. 
                        );
                        try super.showBlocks(self.err);

                        const super_tag_name = kv.value_ptr.*.elem.startTag().name();
                        const extended_block_id = kv.value_ptr.*.superBlock().id_value;
                        try extended.diagnostic(
                            self.err,
                            "note: extendend template super tag:",
                            super_tag_name,
                        );
                        try extended.diagnostic(
                            self.err,
                            "note: extended block defined here:",
                            extended_block_id.node,
                        );
                        try extended.showInterface(self.err);
                        return fatalTrace(
                            self.content_name,
                            templates[0..idx],
                            self.err,
                        );
                    };

                    const block_tag = kv.value_ptr.*.superBlock().elem.startTag().name();
                    const block_tag_string = block_tag.string(extended.html);

                    const super_block_tag = block.value.elem.startTag().name();
                    const super_block_tag_string = super_block_tag.string(super.html);

                    if (!is(super_block_tag_string, block_tag_string)) {
                        try errors.header(self.err, "MISMATCHED BLOCK TAG",
                            \\The super template defines a block that has the wrong tag.
                            \\Both tags and ids must match in order to avoid confusion
                            \\about where the block contents are going to be placed in 
                            \\the extended template.
                        );

                        try super.diagnostic(
                            self.err,
                            "note: super template block tag:",
                            super_block_tag,
                        );

                        try extended.diagnostic(
                            self.err,
                            "note: extended template block defined here:",
                            block_tag,
                        );

                        return fatalTrace(
                            self.content_name,
                            templates[0..idx],
                            self.err,
                        );
                    }
                }

                var unbound_it = blocks.iterator();
                var unbound_idx: usize = 0;
                while (unbound_it.next()) |kv| : (unbound_idx += 1) {
                    const bad = kv.value_ptr.*.elem.node.childAt(0).?.childAt(0).?;
                    if (unbound_idx == 0) {
                        super.reportError(self.err, bad, "unbound_block", "UNBOUND BLOCK",
                            \\Found an unbound block, i.e. the extended template doesn't declare 
                            \\a corresponding super block. Either remove it from the current
                            \\template, or add a <super/> in the extended template. 
                        ) catch {};
                    } else {
                        try super.diagnostic(
                            self.err,
                            "error: another unbound block is here:",
                            bad,
                        );
                    }
                }
                if (unbound_idx > 0) return fatalTrace(
                    self.content_name,
                    templates[0 .. idx - 1],
                    self.err,
                );

                // Should already been validated by the parser.
                const layout = templates[0];
                assert(@src(), layout.interface.count() == 0);
            }
        }

        fn fatalTrace(
            content_name: []const u8,
            items: []const Template,
            err_writer: errors.ErrWriter,
        ) errors.Fatal {
            err_writer.print("trace:\n", .{}) catch return error.ErrIO;
            var cursor = items.len - 1;
            while (cursor > 0) : (cursor -= 1) {
                err_writer.print("    template `{s}`,\n", .{
                    items[cursor].name,
                }) catch return error.ErrIO;
            }

            if (items.len > 0) err_writer.print("    layout `{s}`,\n", .{items[0].name}) catch return error.ErrIO;

            err_writer.print("    content `{s}`.", .{content_name}) catch return error.ErrIO;

            return error.Fatal;
        }
    };
}

// TODO: get rid of this once stack traces on arm64 work again
fn assert(loc: std.builtin.SourceLocation, condition: bool) void {
    if (!condition) {
        std.debug.print("assertion error in {s} at {s}:{}:{}\n", .{
            loc.fn_name,
            loc.file,
            loc.line,
            loc.column,
        });
        std.process.exit(1);
    }
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}
