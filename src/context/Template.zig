const Template = @This();

const superhtml = @import("superhtml");
const scripty = @import("scripty");
const ziggy = @import("ziggy");
const Value = @import("../context.zig").Value;
const Site = @import("Site.zig");
const Build = @import("Build.zig");
const Page = @import("Page.zig");
const Ctx = superhtml.utils.Ctx;

site: *const Site,
page: *const Page,
i18n: ziggy.dynamic.Value,
build: Build = .{},

// Globals specific to SuperHTML
loop: ?Value = null,
@"if": ?Value = null,
ctx: Ctx(Value) = .{},

pub const dot = scripty.defaultDot(Template, Value, false);
pub const Builtins = struct {};
