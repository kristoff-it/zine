const Template = @This();

const superhtml = @import("superhtml");
const scripty = @import("scripty");
const ziggy = @import("ziggy");
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

// Globals specific to SuperHTML
ctx: Ctx(Value) = .{},
loop: ?*Iterator = null,
@"if": ?*const Optional = null,

pub const dot = scripty.defaultDot(Template, Value, false);
pub const description = "";
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
