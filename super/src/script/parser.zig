const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;


const Context = sruct {
    title: []const u8,
    draft: bool,
    content: []const u8,
};

pub const Interpreter = struct {
    it: Tokenizer,
    ctx: Context,

    pub fn init(code: [:0]const u8, ctx: Context) Interpreter {
        return .{
            .it = .{ .code = code },
            .ctx = ctx,
        };
    }

    const State = enum () {
        
    };
    pub fn run() void {
        var state 
        while(self.it.next()) |t| {
            
        }
    }
};


