const std = @import("std");

pub fn defaultDot(
    comptime Context: type,
    comptime Value: type,
) fn (*Context, std.mem.Allocator, []const u8) error{OutOfMemory}!Value {
    return struct {
        pub fn dot(self: *Context, gpa: std.mem.Allocator, path: []const u8) !Value {
            const info = @typeInfo(Context).Struct;
            inline for (info.fields) |f| {
                if (f.name[0] == '_') continue;
                if (std.mem.eql(u8, f.name, path)) {
                    const by_ref = @typeInfo(f.type) == .Struct and @hasDecl(f.type, "PassByRef") and f.type.PassByRef;
                    if (by_ref) {
                        return Value.from(gpa, &@field(self, f.name));
                    } else {
                        return Value.from(gpa, @field(self, f.name));
                    }
                }
            }

            return .{ .err = "field not found" };
        }
    }.dot;
}

pub fn defaultCall(
    comptime Value: type,
) fn (Value, std.mem.Allocator, []const u8, []const Value) error{OutOfMemory}!Value {
    return struct {
        pub fn call(
            self: Value,
            gpa: std.mem.Allocator,
            fn_name: []const u8,
            args: []const Value,
        ) error{OutOfMemory}!Value {
            switch (self) {
                inline else => |v, tag| {
                    const Builtin = Value.builtinsFor(tag);
                    inline for (@typeInfo(Builtin).Struct.decls) |decl| {
                        if (decl.name[0] == '_') continue;
                        if (std.mem.eql(u8, decl.name, fn_name)) {
                            return @field(Builtin, decl.name)(v, gpa, args);
                        }
                    }

                    return .{ .err = "builtin not found" };
                },
            }
        }
    }.call;
}
