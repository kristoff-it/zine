const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

it: Tokenizer = .{},
state: State = .start,
call_depth: usize = 0, // 0 = not in a call

const State = enum {
    start,
    global,
    extend_path,
    call_begin,
    call_arg,
    extend_call,
    call_end,
    after_call,

    // Error state
    syntax,
};

pub const Node = struct {
    tag: Tag,
    loc: Tokenizer.Token.Loc,

    pub const Tag = enum {
        path,
        apply,
        true,
        false,
        string,
        number,
        syntax_error,
    };
};

pub fn next(self: *Parser, code: []const u8) ?Node {
    var path: Node = .{
        .tag = .path,
        .loc = undefined,
    };

    var global = false;
    var path_segments: usize = 0;

    // log.err("next ({s}) (d={}): `{s}`", .{
    //     @tagName(self.state),
    //     self.call_depth,
    //     code[self.it.idx..],
    // });

    while (self.it.next(code)) |tok| switch (self.state) {
        .syntax => unreachable,
        .start => switch (tok.tag) {
            .dollar => {
                self.state = .global;
                path.loc = tok.loc;
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
        .global => switch (tok.tag) {
            .identifier => {
                self.state = .extend_path;
                global = true;
                path.loc.end = tok.loc.end;
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
        .extend_path => switch (tok.tag) {
            .dot => {
                const id_tok = self.it.next(code);
                if (id_tok == null or id_tok.?.tag != .identifier) {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                }

                path_segments += 1;
                if (path_segments == 1 and !global) {
                    path.loc = id_tok.?.loc;
                } else {
                    path.loc.end = id_tok.?.loc.end;
                }
            },
            .lparen => {
                self.state = .call_begin;
                // roll back to get a lparen token next
                self.it.idx -= 1;
                if (path_segments == 0) {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                }
                // include the '(' into the token
                path.loc.end = tok.loc.end;
                return path;
            },
            .rparen => {
                self.state = .call_end;
                // roll back to get a rparen token next
                self.it.idx -= 1;
                if (path_segments == 0) {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                }
                return path;
            },
            .comma => {
                self.state = .call_arg;
                if (path_segments == 0) {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                }
                return path;
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
        .call_begin => {
            self.call_depth += 1;
            switch (tok.tag) {
                .lparen => self.state = .call_arg,
                else => {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                },
            }
        },
        .call_arg => switch (tok.tag) {
            .dollar => self.state = .global,
            .rparen => {
                // rollback to get a rparen next
                self.it.idx -= 1;
                self.state = .call_end;
            },
            .identifier => {
                self.state = .extend_call;
                const src = tok.src(code);
                if (std.mem.eql(u8, "true", src)) {
                    return .{ .tag = .true, .loc = tok.loc };
                } else if (std.mem.eql(u8, "false", src)) {
                    return .{ .tag = .false, .loc = tok.loc };
                } else {
                    self.state = .syntax;
                    return .{ .tag = .syntax_error, .loc = tok.loc };
                }
            },
            .string => {
                self.state = .extend_call;
                return .{ .tag = .string, .loc = tok.loc };
            },
            .number => {
                self.state = .extend_call;
                return .{ .tag = .number, .loc = tok.loc };
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
        .extend_call => switch (tok.tag) {
            .comma => self.state = .call_arg,
            .rparen => {
                // rewind to get a .rparen next call
                self.it.idx -= 1;
                self.state = .call_end;
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
        .call_end => {
            if (self.call_depth == 0) {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            }
            self.call_depth -= 1;
            self.state = .after_call;
            return .{ .tag = .apply, .loc = tok.loc };
        },
        .after_call => switch (tok.tag) {
            .dot => {
                // rewind to get a .dot next
                self.it.idx -= 1;
                self.state = .extend_path;
            },
            .comma => {
                self.state = .call_arg;
            },
            .rparen => {
                // rewind to get a .rparen next
                self.it.idx -= 1;
                self.state = .call_end;
            },
            else => {
                self.state = .syntax;
                return .{ .tag = .syntax_error, .loc = tok.loc };
            },
        },
    };

    const not_good_state = (self.state != .after_call and
        self.state != .extend_path);

    if (self.call_depth > 0 or not_good_state) {
        self.state = .syntax;
        return .{
            .tag = .syntax_error,
            .loc = .{ .start = code.len - 1, .end = code.len },
        };
    }

    if (!global and path_segments == 0) return null;
    path.loc.end = code.len;
    return path;
}

test "basics" {
    const case = "$page.has('a', $page.title.slice(0, 4), 'b').foo.not()";
    const expected: []const Node.Tag = &.{
        .path,
        .string,
        .path,
        .number,
        .number,
        .apply,
        .string,
        .apply,
        .path,
        .apply,
    };

    var p: Parser = .{};

    for (expected) |ex| {
        const actual = p.next(case).?;
        try std.testing.expectEqual(ex, actual.tag);
    }
    try std.testing.expectEqual(@as(?Node, null), p.next(case));
}

test "basics 2" {
    const case = "$page.call('banana')";
    const expected: []const Node.Tag = &.{
        .path,
        .string,
        .apply,
    };

    var p: Parser = .{};

    for (expected) |ex| {
        try std.testing.expectEqual(ex, p.next(case).?.tag);
    }
    try std.testing.expectEqual(@as(?Node, null), p.next(case));
}
