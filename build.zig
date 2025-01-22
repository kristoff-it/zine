const zine = @This();
const std = @import("std");

// This file only contains definitions that are considered Zine's public
// interface. Zine's main build function is in another castle!
pub const build = @import("build/tools.zig").build;
