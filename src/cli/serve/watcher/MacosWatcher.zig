const MacosWatcher = @This();

const std = @import("std");
const fatal = @import("../../../fatal.zig");
const Debouncer = @import("../../serve.zig").Debouncer;

const c = @cImport({
    @cInclude("CoreServices/CoreServices.h");
});

const log = std.log.scoped(.watcher);

gpa: std.mem.Allocator,
debouncer: *Debouncer,
dir_paths: []const []const u8,

pub fn init(
    gpa: std.mem.Allocator,
    debouncer: *Debouncer,
    dir_paths: []const []const u8,
) MacosWatcher {
    return .{
        .gpa = gpa,
        .debouncer = debouncer,
        .dir_paths = dir_paths,
    };
}

pub fn start(watcher: *MacosWatcher) !void {
    const t = try std.Thread.spawn(.{}, MacosWatcher.listen, .{watcher});
    t.detach();
}

pub fn listen(watcher: *MacosWatcher) void {
    errdefer |err| switch (err) {
        error.OutOfMemory => fatal.oom(),
    };

    const macos_paths = try watcher.gpa.alloc(
        c.CFStringRef,
        watcher.dir_paths.len,
    );
    defer watcher.gpa.free(macos_paths);

    for (watcher.dir_paths, macos_paths) |str, *ref| {
        ref.* = c.CFStringCreateWithCString(
            null,
            str.ptr,
            c.kCFStringEncodingUTF8,
        );
    }

    const paths_to_watch: c.CFArrayRef = c.CFArrayCreate(
        null,
        @ptrCast(macos_paths.ptr),
        @intCast(macos_paths.len),
        null,
    );

    var stream_context: c.FSEventStreamContext = .{ .info = watcher };
    const stream: c.FSEventStreamRef = c.FSEventStreamCreate(
        null,
        &macosCallback,
        &stream_context,
        paths_to_watch,
        c.kFSEventStreamEventIdSinceNow,
        0.05,
        c.kFSEventStreamCreateFlagFileEvents,
    );

    c.FSEventStreamScheduleWithRunLoop(
        stream,
        c.CFRunLoopGetCurrent(),
        c.kCFRunLoopDefaultMode,
    );

    if (c.FSEventStreamStart(stream) == 0) {
        fatal.msg("error: macos watcher FSEventStreamStart failed", .{});
    }

    c.CFRunLoopRun();

    c.FSEventStreamStop(stream);
    c.FSEventStreamInvalidate(stream);
    c.FSEventStreamRelease(stream);

    c.CFRelease(paths_to_watch);
}

pub fn macosCallback(
    streamRef: c.ConstFSEventStreamRef,
    clientCallBackInfo: ?*anyopaque,
    numEvents: usize,
    eventPaths: ?*anyopaque,
    eventFlags: ?[*]const c.FSEventStreamEventFlags,
    eventIds: ?[*]const c.FSEventStreamEventId,
) callconv(.C) void {
    _ = eventIds;
    _ = eventFlags;
    _ = streamRef;
    const watcher: *MacosWatcher = @alignCast(@ptrCast(clientCallBackInfo));

    const paths: [*][*:0]u8 = @alignCast(@ptrCast(eventPaths));
    for (paths[0..numEvents]) |p| {
        const path = std.mem.span(p);
        log.debug("Changed: {s}\n", .{path});

        // const basename = std.fs.path.basename(path);
        // var base_path = path[0 .. path.len - basename.len];
        // if (std.mem.endsWith(u8, base_path, "/"))
        //     base_path = base_path[0 .. base_path.len - 1];
        watcher.debouncer.newEvent();
    }
}
