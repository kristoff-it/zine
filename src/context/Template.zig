const Template = @This();

const std = @import("std");
const superhtml = @import("superhtml");
const scripty = @import("scripty");
const ziggy = @import("ziggy");
const ZineBuild = @import("../Build.zig");
const context = @import("../context.zig");
const Value = context.Value;
const Site = context.Site;
const Page = context.Page;
const Build = context.Build;
const Map = context.Map;
const Iterator = context.Iterator;
const Optional = context.Optional;
const Ctx = superhtml.utils.Ctx;

site: *const Site,
page: *const Page,
build: Build,
i18n: Map.ZiggyMap,

_meta: struct {
    build: *const ZineBuild,
    // Indexed by language code, empty when building a simple site
    // Get by key when you have a language code, get by idx when you
    // have a variant_id.
    sites: *const std.StringArrayHashMapUnmanaged(Site),
},

// Globals specific to SuperHTML
ctx: Ctx(Value) = .{},
loop: ?*Iterator = null,
@"if": ?*const Optional = null,

pub fn printLinkPrefix(
    ctx: *const Template,
    w: anytype,
    other_variant_id: u32,
    /// When set to true the full host url will be always printed
    /// otherwise it will only be added in multilingual websites when
    /// linking to content across variants that have different host url
    /// overrides.
    force_host_url: bool,
) error{OutOfMemory}!void {
    const other_site = ctx._meta.sites.entries.items(.value)[other_variant_id];
    switch (other_site._meta.kind) {
        .simple => |url_path_prefix| {
            if (force_host_url) try w.print("{s}", .{
                ctx._meta.build.cfg.Site.host_url,
            });
            if (url_path_prefix.len > 0) {
                try w.print("/{s}/", .{url_path_prefix});
            } else {
                try w.writeAll("/");
            }
        },
        .multi => |loc| {
            const our_variant_id = ctx.page._scan.variant_id;
            if (other_variant_id != our_variant_id) {
                const sites = ctx._meta.sites.entries.items(.value);
                const our_host_url = sites[our_variant_id].host_url;
                const other_host_url = sites[other_variant_id].host_url;
                if (force_host_url or our_host_url.ptr != other_host_url.ptr) {
                    try w.print("{s}", .{other_host_url});
                }
            }
            try w.writeAll("/");
            const path_prefix = loc.output_prefix_override orelse loc.code;
            if (path_prefix.len > 0) try w.print("{s}/", .{path_prefix});
        },
    }
}

pub const dot = scripty.defaultDot(Template, Value, false);
pub const docs_description = "";
pub const Fields = struct {
    pub const site =
        \\The current website. In a multilingual website,
        \\each locale will have its own separate instance of $site
    ;

    pub const page =
        \\The page being currently rendered.
    ;

    pub const i18n =
        \\In a multilingual website it contains the translations 
        \\defined in the corresponding i18n file.
        \\
        \\See the i18n docs for more info.
    ;

    pub const build =
        \\Gives you access to build-time assets (i.e. assets built
        \\ via the Zig build system) alongside other information
        \\relative to the current build.
    ;

    pub const ctx =
        \\A key-value mapping that contains data defined in `<ctx>`
        \\nodes.
    ;

    pub const loop =
        \\The current iterator, only available within elements
        \\that have a `loop` attribute.
    ;

    pub const @"if" =
        \\The current branching variable, only available within elements
        \\that have an `if` attribute used to unwrap an optional value.
    ;
};
pub const Builtins = struct {};
