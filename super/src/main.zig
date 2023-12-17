const interpreter = @import("interpreter.zig");

pub const frontmatter = @import("frontmatter");
pub const SuperVM = interpreter.SuperVM;
pub const Exception = interpreter.Exception;

test {
    _ = @import("template.zig");
    _ = @import("SuperTree.zig");
}
