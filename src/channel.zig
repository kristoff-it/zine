const std = @import("std");

pub fn Channel(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        fifo: Fifo,
        writeable: std.Thread.Condition = .{},
        readable: std.Thread.Condition = .{},

        const Fifo = std.fifo.LinearFifo(T, .Slice);
        const Self = @This();

        pub fn init(buffer: []T) Self {
            return Self{ .fifo = Fifo.init(buffer) };
        }

        pub fn put(self: *Self, item: T) void {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.readable.signal();
            }

            while (true) return self.fifo.writeItem(item) catch {
                self.writeable.wait(&self.lock);
                continue;
            };
        }

        pub fn tryPut(self: *Self, item: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            try self.fifo.writeItem(item);

            // only signal on success
            self.readable.signal();
        }

        pub fn get(self: *Self) T {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.writeable.signal();
            }

            while (true) return self.fifo.readItem() orelse {
                self.readable.wait(&self.lock);
                continue;
            };
        }

        pub fn getOrNull(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.fifo.readItem()) |item| return item;

            // signal on empty queue
            self.writeable.signal();
        }
    };
}
