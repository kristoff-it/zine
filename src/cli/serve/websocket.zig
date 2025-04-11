const std = @import("std");

const log = std.log.scoped(.websockets);

pub const Connection = struct {
    stream: std.net.Stream,

    pub fn init(request: *std.http.Server.Request) !Connection {
        var it = request.iterateHeaders();
        const key = while (it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "sec-websocket-key")) {
                break header.value;
            }
        } else {
            // req.serveError("missing sec-websocket-key header", .bad_request);
            return error.MissingSecWebsocketKey;
        };

        const hash_byte_len = 20;
        var encoded_hash: [std.base64.standard.Encoder.calcSize(hash_byte_len)]u8 = undefined;
        {
            var hasher = std.crypto.hash.Sha1.init(.{});
            hasher.update(key);
            hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

            var h: [hash_byte_len]u8 = undefined;
            hasher.final(&h);

            const written = std.base64.standard.Encoder.encode(&encoded_hash, &h);
            std.debug.assert(written.len == encoded_hash.len);
        }

        var buffer: [4000]u8 = undefined;
        var response = request.respondStreaming(.{
            .send_buffer = &buffer,
            .respond_options = .{
                .status = .switching_protocols,
                .extra_headers = &.{
                    .{ .name = "Upgrade", .value = "websocket" },
                    .{ .name = "Connection", .value = "upgrade" },
                    .{ .name = "Sec-Websocket-Accept", .value = &encoded_hash },
                    .{ .name = "connection", .value = "close" },
                },
                .transfer_encoding = .none,
            },
        });

        try response.flush();

        return .{
            .stream = request.server.connection.stream,
        };
    }

    const MessageKind = enum {
        binary,
        text,
    };

    /// Thread safe, lock ensures one message sent at a time.
    pub fn writeMessage(
        conn: *const Connection,
        bytes: []const u8,
        kind: MessageKind,
    ) !void {
        // NOT named `write` because websockets is a message protocol, not a stream protocol.

        const op_code: Header.OpCode = switch (kind) {
            .binary => .binary,
            .text => .text,
        };

        const header: Header = .{
            .finish = true,
            .op_code = op_code,
            .payload_len = @intCast(bytes.len),
            .mask = null,
        };
        try conn.writeWithHeader(header, bytes);
    }

    fn writeWithHeader(
        conn: *const Connection,
        header: Header,
        payload: []const u8,
    ) !void {
        const writer = conn.stream.writer();

        try header.write(writer);
        try writer.writeAll(payload);
    }

    /// Not thread safe, must be only called by one thread at a time.
    pub fn readMessage(conn: *const Connection, buffer: []u8) ![]u8 {
        // NOT named `read` because websockets is a message protocol, not a stream protocol.

        const reader = conn.stream.reader();

        var current_length: u64 = 0;
        while (true) {
            const header = try Header.read(reader);
            if (current_length > 0 and (header.op_code == .binary or header.op_code == .text)) {
                return error.ExpectedContinuation;
            }
            const new_len = header.payload_len + current_length;
            if (new_len > buffer.len) {
                return error.NoSpaceLeft;
            }
            try reader.readNoEof(buffer[current_length..new_len]);

            if (header.mask) |mask| {
                for (0.., buffer[current_length..new_len]) |i, *b| {
                    b.* ^= mask[i % 4];
                }
            }
            current_length = new_len;

            switch (header.op_code) {
                .continuation, .text, .binary => {
                    if (header.finish) {
                        return buffer[0..current_length];
                    }
                },

                .close => {
                    return error.WebsocketClosed;
                },

                .ping => {
                    try conn.writeWithHeader(.{
                        .finish = true,
                        .op_code = .pong,
                        .payload_len = 0,
                        .mask = null,
                    }, &.{});
                },

                .pong => {},
            }
        }
    }

    pub fn close(conn: *const Connection) void {
        conn.stream.close();
    }
};

const Header = struct {
    finish: bool,
    op_code: OpCode,
    payload_len: u64,
    mask: ?[4]u8,

    const OpCode = enum(u4) {
        continuation = 0,
        text = 1,
        binary = 2,
        close = 8,
        ping = 9,
        pong = 10,
    };

    const Partial = packed struct(u16) {
        payload_len: enum(u7) {
            u16_len = 126,
            u64_len = 127,
            _,
        },
        masked: bool,
        op_code: u4,
        reserved: u3,
        fin: bool,
    };
    fn read(reader: anytype) !Header {
        const partial: Partial = @bitCast(try reader.readInt(u16, .big));
        var r: Header = undefined;
        r.finish = partial.fin;

        inline for (std.meta.fields(OpCode)) |field| {
            if (field.value == partial.op_code) {
                r.op_code = @field(OpCode, field.name);
                break;
            }
        } else {
            return error.InvalidHeader;
        }

        r.payload_len = switch (partial.payload_len) {
            .u16_len => try reader.readInt(u16, .big),
            .u64_len => try reader.readInt(u64, .big),
            else => |v| @intFromEnum(v),
        };

        if (partial.masked) {
            r.mask = try reader.readBytesNoEof(4);
        } else {
            r.mask = null;
        }

        return r;
    }

    fn write(h: Header, writer: anytype) !void {
        var p: Partial = .{
            .payload_len = undefined,
            .masked = if (h.mask) |_| true else false,
            .op_code = @intFromEnum(h.op_code),
            .reserved = 0,
            .fin = h.finish,
        };

        if (h.payload_len < 126) {
            p.payload_len = @enumFromInt(h.payload_len);
        } else if (h.payload_len <= std.math.maxInt(u16)) {
            p.payload_len = .u16_len;
        } else {
            p.payload_len = .u64_len;
        }

        try writer.writeInt(u16, @bitCast(p), .big);
        switch (p.payload_len) {
            .u16_len => try writer.writeInt(u16, @intCast(h.payload_len), .big),
            .u64_len => try writer.writeInt(u64, h.payload_len, .big),
            else => {},
        }
        if (h.mask) |mask| {
            try writer.writeAll(&mask);
        }
    }
};

fn testHeader(header_truth: Header, buffer_truth: []const u8) !void {
    {
        var stream = std.io.fixedBufferStream(buffer_truth);
        const header_result = Header.read(stream.reader());
        try std.testing.expectEqualDeep(header_truth, header_result);
        try std.testing.expectEqual(buffer_truth.len, stream.getPos()); // consumed whole header
    }
    {
        var b: [20]u8 = undefined;
        var stream = std.io.fixedBufferStream(&b);
        try header_truth.write(stream.writer());
        try std.testing.expectEqualSlices(u8, buffer_truth, stream.getWritten());
    }
}

test Header {
    // Finish
    try testHeader(.{ .finish = true, .op_code = .continuation, .payload_len = 0, .mask = null }, &[_]u8{ 1 << 7, 0 });
    // Op code
    try testHeader(.{ .finish = false, .op_code = .text, .payload_len = 0, .mask = null }, &[_]u8{ 1, 0 });
    // Payload len
    try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 125, .mask = null }, &[_]u8{ 0, 125 });
    try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 126, .mask = null }, &[_]u8{ 0, 126, 0, 126 });
    try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 65_535, .mask = null }, &[_]u8{ 0, 126, 255, 255 });
    try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 65_536, .mask = null }, &[_]u8{ 0, 127, 0, 0, 0, 0, 0, 1, 0, 0 });
    // Mask
    try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 0, .mask = .{ 1, 2, 3, 4 } }, &[_]u8{ 0, 1 << 7, 1, 2, 3, 4 });
    // Bit of everthing
    try testHeader(.{ .finish = true, .op_code = .binary, .payload_len = 126, .mask = .{ 1, 2, 3, 4 } }, &[_]u8{ (1 << 7) | 2, 1 << 7 | 126, 0, 126, 1, 2, 3, 4 });
}
