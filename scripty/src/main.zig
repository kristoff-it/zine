const interpreter = @import("interpreter.zig");

pub const ScriptyVM = interpreter.ScriptyVM;
pub const Value = interpreter.Value;
pub const ExternalValue = interpreter.ExternalValue;
pub const ScriptFunction = interpreter.ScriptFunction;
pub const ScriptResult = interpreter.ScriptResult;

test {
    _ = interpreter;
}
