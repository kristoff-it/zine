const std = @import("std");
const mem = std.mem;
const print = std.debug.print;

pub fn highlightZigCode(raw_src: [:0]const u8, allocator: std.mem.Allocator, out: anytype) !void {
    const src = try allocator.dupeZ(u8, mem.trim(u8, raw_src, " \n"));
    defer allocator.free(src);

    try out.writeAll("<pre><code class=\"zig\">");
    var tokenizer = std.zig.Tokenizer.init(src);
    var index: usize = 0;
    var next_tok_is_fn = false;
    while (true) {
        const prev_tok_was_fn = next_tok_is_fn;
        next_tok_is_fn = false;

        const token = tokenizer.next();
        try writeEscaped(out, src[index..token.loc.start]);
        switch (token.tag) {
            .eof => break,

            .keyword_addrspace,
            .keyword_align,
            .keyword_and,
            .keyword_asm,
            .keyword_async,
            .keyword_await,
            .keyword_break,
            .keyword_catch,
            .keyword_comptime,
            .keyword_const,
            .keyword_continue,
            .keyword_defer,
            .keyword_else,
            .keyword_enum,
            .keyword_errdefer,
            .keyword_error,
            .keyword_export,
            .keyword_extern,
            .keyword_for,
            .keyword_if,
            .keyword_inline,
            .keyword_noalias,
            .keyword_noinline,
            .keyword_nosuspend,
            .keyword_opaque,
            .keyword_or,
            .keyword_orelse,
            .keyword_packed,
            .keyword_anyframe,
            .keyword_pub,
            .keyword_resume,
            .keyword_return,
            .keyword_linksection,
            .keyword_callconv,
            .keyword_struct,
            .keyword_suspend,
            .keyword_switch,
            .keyword_test,
            .keyword_threadlocal,
            .keyword_try,
            .keyword_union,
            .keyword_unreachable,
            .keyword_usingnamespace,
            .keyword_var,
            .keyword_volatile,
            .keyword_allowzero,
            .keyword_while,
            .keyword_anytype,
            => {
                try out.writeAll("<span class=\"tok tok-kw\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },

            .keyword_fn => {
                try out.writeAll("<span class=\"tok tok-kw\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
                next_tok_is_fn = true;
            },

            .string_literal,
            .multiline_string_literal_line,
            .char_literal,
            => {
                try out.writeAll("<span class=\"tok tok-str\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },

            .builtin => {
                try out.writeAll("<span class=\"tok tok-builtin\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },

            .doc_comment,
            .container_doc_comment,
            => {
                try out.writeAll("<span class=\"tok tok-comment\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },

            .identifier => {
                if (prev_tok_was_fn) {
                    try out.writeAll("<span class=\"tok tok-fn\">");
                    try writeEscaped(out, src[token.loc.start..token.loc.end]);
                    try out.writeAll("</span>");
                } else {
                    const is_int = blk: {
                        if (src[token.loc.start] != 'i' and src[token.loc.start] != 'u')
                            break :blk false;
                        var i = token.loc.start + 1;
                        if (i == token.loc.end)
                            break :blk false;
                        while (i != token.loc.end) : (i += 1) {
                            if (src[i] < '0' or src[i] > '9')
                                break :blk false;
                        }
                        break :blk true;
                    };
                    if (is_int or isType(src[token.loc.start..token.loc.end])) {
                        try out.writeAll("<span class=\"tok tok-type\">");
                        try writeEscaped(out, src[token.loc.start..token.loc.end]);
                        try out.writeAll("</span>");
                    } else {
                        try out.writeAll("<span class=\"tok\">");
                        try writeEscaped(out, src[token.loc.start..token.loc.end]);
                        try out.writeAll("</span>");
                    }
                }
            },

            .number_literal => {
                try out.writeAll("<span class=\"tok tok-number\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },

            .bang,
            .pipe,
            .pipe_pipe,
            .pipe_equal,
            .equal,
            .equal_equal,
            .equal_angle_bracket_right,
            .bang_equal,
            .l_paren,
            .r_paren,
            .semicolon,
            .percent,
            .percent_equal,
            .l_brace,
            .r_brace,
            .l_bracket,
            .r_bracket,
            .period,
            .period_asterisk,
            .ellipsis2,
            .ellipsis3,
            .caret,
            .caret_equal,
            .plus,
            .plus_plus,
            .plus_equal,
            .plus_percent,
            .plus_percent_equal,
            .minus,
            .minus_equal,
            .minus_percent,
            .minus_percent_equal,
            .asterisk,
            .asterisk_equal,
            .asterisk_asterisk,
            .asterisk_percent,
            .asterisk_percent_equal,
            .arrow,
            .colon,
            .slash,
            .slash_equal,
            .comma,
            .ampersand,
            .ampersand_equal,
            .question_mark,
            .angle_bracket_left,
            .angle_bracket_left_equal,
            .angle_bracket_angle_bracket_left,
            .angle_bracket_angle_bracket_left_equal,
            .angle_bracket_right,
            .angle_bracket_right_equal,
            .angle_bracket_angle_bracket_right,
            .angle_bracket_angle_bracket_right_equal,
            .tilde,
            .plus_pipe,
            .plus_pipe_equal,
            .minus_pipe,
            .minus_pipe_equal,
            .asterisk_pipe,
            .asterisk_pipe_equal,
            .angle_bracket_angle_bracket_left_pipe,
            .angle_bracket_angle_bracket_left_pipe_equal,
            => {
                try out.writeAll("<span class=\"tok tok-symbol\">");
                try writeEscaped(out, src[token.loc.start..token.loc.end]);
                try out.writeAll("</span>");
            },
            .invalid, .invalid_periodasterisks => return parseError(
                src,
                token,
                "syntax error",
                .{},
            ),
        }
        index = token.loc.end;
    }
    try out.writeAll("</code></pre>");
}

fn parseError(src: []const u8, token: std.zig.Token, comptime fmt: []const u8, args: anytype) error{ParseError} {
    const loc = getTokenLocation(src, token);
    // const args_prefix = .{ tokenizer.source_file_name, loc.line + 1, loc.column + 1 };
    // print("{s}:{d}:{d}: error: " ++ fmt ++ "\n", args_prefix ++ args);

    const args_prefix = .{ loc.line + 1, loc.column + 1 };
    print("{d}:{d}: error: " ++ fmt ++ "\n", args_prefix ++ args);
    if (loc.line_start <= loc.line_end) {
        print("{s}\n", .{src[loc.line_start..loc.line_end]});
        {
            var i: usize = 0;
            while (i < loc.column) : (i += 1) {
                print(" ", .{});
            }
        }
        {
            const caret_count = token.loc.end - token.loc.start;
            var i: usize = 0;
            while (i < caret_count) : (i += 1) {
                print("~", .{});
            }
        }
        print("\n", .{});
    }
    return error.ParseError;
}

const builtin_types = [_][]const u8{
    "f16",         "f32",      "f64",    "f128",     "c_longdouble", "c_short",
    "c_ushort",    "c_int",    "c_uint", "c_long",   "c_ulong",      "c_longlong",
    "c_ulonglong", "c_char",   "c_void", "void",     "bool",         "isize",
    "usize",       "noreturn", "type",   "anyerror", "comptime_int", "comptime_float",
};

fn isType(name: []const u8) bool {
    for (builtin_types) |t| {
        if (mem.eql(u8, t, name))
            return true;
    }
    return false;
}

const Location = struct {
    line: usize,
    column: usize,
    line_start: usize,
    line_end: usize,
};
fn getTokenLocation(src: []const u8, token: std.zig.Token) Location {
    var loc = Location{
        .line = 0,
        .column = 0,
        .line_start = 0,
        .line_end = 0,
    };
    for (src, 0..) |c, i| {
        if (i == token.loc.start) {
            loc.line_end = i;
            while (loc.line_end < src.len and src[loc.line_end] != '\n') : (loc.line_end += 1) {}
            return loc;
        }
        if (c == '\n') {
            loc.line += 1;
            loc.column = 0;
            loc.line_start = i + 1;
        } else {
            loc.column += 1;
        }
    }
    return loc;
}
pub fn writeEscaped(out: anytype, input: []const u8) !void {
    for (input) |c| {
        try switch (c) {
            '&' => out.writeAll("&amp;"),
            '<' => out.writeAll("&lt;"),
            '>' => out.writeAll("&gt;"),
            '"' => out.writeAll("&quot;"),
            else => out.writeByte(c),
        };
    }
}
