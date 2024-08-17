const Template = @This();

const scripty = @import("scripty");
const ziggy = @import("ziggy");
const Site = @import("Site.zig");
const Build = @import("Build.zig");
const Page = @import("Page.zig");
const Value = @import("../context.zig").Value;

site: *const Site,
page: *const Page,
i18n: ziggy.dynamic.Value,
build: Build = .{},

// Globals specific to Super
loop: ?Value = null,
@"if": ?Value = null,
ctx: ?Value = null,

pub const dot = scripty.defaultDot(Template, Value, false);
pub const Builtins = struct {};
