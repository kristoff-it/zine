const std = @import("std");
const json = std.json;

pub const Diagnostics = struct {
    line: usize = 0,
    col: usize = 0,

    const header =
        \\------------------- BAD FRONTMATTER -------------------
        \\A file has either a missing or a malformed frontmatter.
        \\ 
        \\
    ;

    const footer =
        \\
        \\[bad_frontmatter]
        \\{s}/{s}{s}
        \\
        \\
        \\
    ;

    pub fn fatal(
        self: Diagnostics,
        err: FrontMatterError,
        base_path: []const u8,
        sub_path: []const u8,
        name: []const u8,
    ) noreturn {
        switch (err) {
            error.Empty => @panic("error: fatal called on empty frontmatter"),
            error.OutOfMemory => std.debug.print("out of memory", .{}),
            error.IO => {
                const reason =
                    \\Got an I/O error while trying to read the file.
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    base_path,
                    sub_path,
                    name,
                });
            },
            error.Framing => {
                const reason =
                    \\Each markdown file in the content directory must start
                    \\with a JSON frontmatter framed by three dashes.
                    \\See the official documentation for more info.
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    base_path,
                    sub_path,
                    name,
                });
            },
            error.Syntax => {
                const reason =
                    \\The JSON contains a syntax error at line {} col {}.
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    self.line,
                    self.col,
                    base_path,
                    sub_path,
                    name,
                });
            },
            error.DuplicateField => {
                const reason =
                    \\The JSON contains a duplicate field at line {} col {}.
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    self.line,
                    self.col,
                    base_path,
                    sub_path,
                    name,
                });
            },
            error.UnknownField => {
                const reason =
                    \\The JSON contains a unknown field at line {} col {}.
                    \\Custom fields can only be put inside of "custom".
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    self.line,
                    self.col,
                    base_path,
                    sub_path,
                    name,
                });
            },
            error.MissingField => {
                const reason =
                    \\The JSON contains a missing field at line {} col {}.
                    \\See the Scripty reference for 'Page'.
                    \\
                ;
                std.debug.print(header ++ reason ++ footer, .{
                    self.line,
                    self.col,
                    base_path,
                    sub_path,
                    name,
                });
            },
        }
        std.process.exit(1);
    }
};

const FrontMatterError = error{
    IO,
    OutOfMemory,

    // emtpy file
    Empty,
    // missing ---
    Framing,

    //json
    DuplicateField,
    UnknownField,
    MissingField,
    Syntax,
};

pub fn parse(
    comptime Header: type,
    arena: std.mem.Allocator,
    reader: anytype,
    diag: ?*Diagnostics,
) FrontMatterError!Header {
    var json_string = std.ArrayList(u8).init(arena);

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var state: enum { start, body, end } = .start;

    while (true) : (fbs.reset()) {
        reader.streamUntilDelimiter(fbs.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                const data = std.mem.trim(u8, fbs.getWritten(), "\n\r ");
                if (data.len == 0) return error.Empty;
                return error.Framing;
            },
            else => return error.IO,
        };

        const maybe_trimmed_dashes = std.mem.trimRight(u8, fbs.getWritten(), " \r");
        switch (state) {
            .start => {
                if (maybe_trimmed_dashes.len == 0) continue;
                if (std.mem.eql(u8, maybe_trimmed_dashes, "---")) {
                    state = .body;
                } else {
                    return error.Framing;
                }
            },

            .body => {
                if (std.mem.eql(u8, maybe_trimmed_dashes, "---")) {
                    state = .end;
                    break;
                } else {
                    try json_string.appendSlice(maybe_trimmed_dashes);
                    try json_string.append('\n');
                }
            },
            .end => unreachable,
        }
    }

    if (state != .end) return error.Framing;

    var scanner = json.Scanner.initCompleteInput(arena, json_string.items);
    defer scanner.deinit();

    var json_diag: json.Diagnostics = .{};

    errdefer if (diag) |d| {
        d.line = json_diag.getLine();
        d.col = json_diag.getColumn();
    };

    if (diag) |_| scanner.enableDiagnostics(&json_diag);

    return json.parseFromTokenSourceLeaky(Header, arena, &scanner, .{}) catch |err| switch (err) {
        inline error.DuplicateField, error.UnknownField, error.MissingField => |e| e,
        else => error.Syntax,
    };
}
