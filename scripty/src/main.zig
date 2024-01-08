const interpreter = @import("interpreter.zig");
const types = @import("types.zig");

pub const ScriptyVM = interpreter.ScriptyVM;
pub const defaultDot = types.defaultDot;
pub const defaultCall = types.defaultCall;

test {
    _ = interpreter;
}
