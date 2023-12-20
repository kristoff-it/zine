const interpreter = @import("interpreter.zig");
const types = @import("types.zig");

pub const ScriptyVM = interpreter.ScriptyVM;
pub const Result = types.Result;
pub const Value = types.Value;

test {
    _ = interpreter;
}
