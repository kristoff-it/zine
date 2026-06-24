const Union = @This();

const std = @import("std");
const ziggy = @import("ziggy");
const Signature = @import("doctypes.zig").Signature;
const context = @import("../context.zig");
const Value = context.Value;
const Allocator = std.mem.Allocator;

value: ziggy.Dynamic,

pub const PassByRef = false;
pub const docs_description =
    \\A tagged union.
    \\
    \\Supports retrieving the active tag and tentatively accessing the
    \\active case (see `case?`). In situations where you know statically
    \\which is going to be the active case, use normal path syntax to
    \\access the value.
    \\
    \\When you don't know for sure the active case:
    \\   `$myunion.case?('foo')`
    \\
    \\When you do know statically:
    \\   `$myunion.foo`
    \\
    \\Tagged unions are not a common data type in Zine. For example page
    \\dates are expressed as tagged unions in the frontmatter but they have
    \\a dedicated type when accessed through Scripty. That said, tagged
    \\union support is important to be able to navigate all possible Ziggy
    \\Document values.
;
/// Used for syntax that asserts the active case.
pub fn dynamicDot(
    un: *const @This(),
    gpa: std.mem.Allocator,
    path: []const u8,
) !Value {
    const wrong = try Value.errFmt(gpa, "wrong tag, active case is '{s}'", .{un.value.@"union".tag});
    if (std.mem.eql(u8, path, un.value.@"union".tag)) {
        return Value.fromZiggy(gpa, un.value.@"union".value.*);
    } else {
        return wrong;
    }
}

pub const Builtins = struct {
    pub const tag = struct {
        pub const signature: Signature = .{ .params = &.{}, .ret = .String };
        pub const docs_description =
            \\Returns the current active tag of this union.
            \\
        ;
        pub const examples =
            \\$page.custom.get('myunion').tag()
        ;
        pub fn call(
            un: Union,
            _: Allocator,
            _: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{ .err = "expected 0 arguments" };
            if (args.len != 0) return bad_arg;
            return context.String.init(un.value.@"union".tag);
        }
    };

    pub const @"case?" = struct {
        pub const signature: Signature = .{
            .params = &.{.String},
            .ret = .any,
        };
        pub const docs_description =
            \\Checks if the active union case matches the one provided as argument
            \\and on success returns the value, otherwise returns null.
            \\
            \\To be used in conjunction with `:if` attributes.
        ;
        pub const examples =
            \\<ctx :if="$page.custom.get('myunion').case?('foo')"></ctx>
        ;
        pub fn call(
            un: Union,
            gpa: Allocator,
            _: *const context.Root,
            args: []const Value,
        ) context.CallError!Value {
            const bad_arg: Value = .{ .err = "expected 1 string argument" };
            if (args.len != 1) return bad_arg;

            const case = switch (args[0]) {
                .string => |s| s.value,
                else => return bad_arg,
            };

            if (std.mem.eql(u8, case, un.value.@"union".tag)) {
                return context.Optional.init(gpa, try Value.fromZiggy(gpa, un.value.@"union".value.*));
            } else {
                return context.Optional.Null;
            }
        }
    };
};
