const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const WaitGroup = @This();

const is_waiting: usize = 1 << 0;
const one_pending: usize = 1 << 1;

io: Io,
state: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
event: Io.Event = .unset,

pub fn start(self: *WaitGroup) void {
    const state = self.state.fetchAdd(one_pending, .monotonic);
    assert((state / one_pending) < (std.math.maxInt(usize) / one_pending));
}

pub fn startMany(self: *WaitGroup, n: usize) void {
    const state = self.state.fetchAdd(one_pending * n, .monotonic);
    assert((state / one_pending) < (std.math.maxInt(usize) / one_pending));
}

pub fn finish(self: *WaitGroup) void {
    const state = self.state.fetchSub(one_pending, .acq_rel);
    assert((state / one_pending) > 0);

    if (state == (one_pending | is_waiting)) {
        self.event.set(self.io);
    }
}

pub fn wait(self: *WaitGroup) void {
    const state = self.state.fetchAdd(is_waiting, .acquire);
    assert(state & is_waiting == 0);

    if ((state / one_pending) > 0) {
        self.event.wait(self.io) catch unreachable;
    }
}

pub fn reset(self: *WaitGroup) void {
    self.state.store(0, .monotonic);
    self.event.reset();
}

pub fn isDone(wg: *WaitGroup) bool {
    const state = wg.state.load(.acquire);
    assert(state & is_waiting == 0);

    return (state / one_pending) == 0;
}

// Spawns a new thread for the task. This is appropriate when the callee
// delegates all work.
pub fn spawnManager(
    wg: *WaitGroup,
    comptime func: anytype,
    args: anytype,
) void {
    if (builtin.single_threaded) {
        @call(.auto, func, args);
        return;
    }
    const Manager = struct {
        fn run(wg_inner: *WaitGroup, args_inner: @TypeOf(args)) void {
            defer wg_inner.finish();
            @call(.auto, func, args_inner);
        }
    };
    wg.start();
    const t = std.Thread.spawn(.{}, Manager.run, .{ wg, args }) catch return Manager.run(wg, args);
    t.detach();
}
