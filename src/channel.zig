const std = @import("std");
const Io = std.Io;

pub fn Channel(comptime T: type) type {
    return struct {
        lock: Io.Mutex = .init,
        fifo: Fifo,
        writeable: Io.Condition = .init,
        readable: Io.Condition = .init,

        const Fifo = std.ArrayList(T);
        const Self = @This();

        pub fn init(buffer: []T) Self {
            return .{ .fifo = Fifo.initBuffer(buffer) };
        }

        pub fn put(self: *Self, io: Io, item: T) !void {
            try self.lock.lock(io);
            defer {
                self.lock.unlock(io);
                self.readable.signal(io);
            }

            while (true) return self.fifo.appendBounded(item) catch {
                try self.writeable.wait(io, &self.lock);
                continue;
            };
        }

        pub fn tryPut(self: *Self, io: Io, item: T) !void {
            try self.lock.lock(io);
            defer self.lock.unlock(io);

            try self.fifo.appendBounded(item);

            // only signal on success
            self.readable.signal(io);
        }

        pub fn get(self: *Self, io: Io) !T {
            try self.lock.lock(io);
            defer {
                self.lock.unlock(io);
                self.writeable.signal(io);
            }

            while (true) return self.fifo.pop() orelse {
                try self.readable.wait(io, &self.lock);
                continue;
            };
        }

        pub fn getOrNull(self: *Self, io: Io) !?T {
            try self.lock.lock(io);
            defer self.lock.unlock(io);

            if (self.fifo.pop()) |item| return item;

            // signal on empty queue
            self.writeable.signal(io);
        }
    };
}
