const MacosWatcher = @This();

const std = @import("std");
const Reloader = @import("../Reloader.zig");
const c = @cImport({
    @cInclude("CoreServices/CoreServices.h");
});

const log = std.log.scoped(.watcher);

out_dir_path: []const u8,
in_dir_paths: []const []const u8,

pub fn init(
    gpa: std.mem.Allocator,
    out_dir_path: []const u8,
    in_dir_paths: []const []const u8,
) !MacosWatcher {
    _ = gpa;
    return .{
        .out_dir_path = out_dir_path,
        .in_dir_paths = in_dir_paths,
    };
}

pub fn callback(
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
    const ctx: *Context = @alignCast(@ptrCast(clientCallBackInfo));

    const paths: [*][*:0]u8 = @alignCast(@ptrCast(eventPaths));
    for (paths[0..numEvents]) |p| {
        const path = std.mem.span(p);
        log.debug("Changed: {s}\n", .{path});

        const basename = std.fs.path.basename(path);
        var base_path = path[0 .. path.len - basename.len];
        if (std.mem.endsWith(u8, base_path, "/"))
            base_path = base_path[0 .. base_path.len - 1];

        const is_out = std.mem.startsWith(u8, path, ctx.out_dir_path);
        if (is_out) {
            ctx.reloader.onOutputChange(base_path, basename);
        } else {
            ctx.reloader.onInputChange(base_path, basename);
        }
    }
}

const Context = struct {
    reloader: *Reloader,
    out_dir_path: []const u8,
};
pub fn listen(
    self: *MacosWatcher,
    gpa: std.mem.Allocator,
    reloader: *Reloader,
) !void {
    var macos_paths = try gpa.alloc(c.CFStringRef, self.in_dir_paths.len + 1);
    defer gpa.free(macos_paths);

    macos_paths[0] = c.CFStringCreateWithCString(
        null,
        self.out_dir_path.ptr,
        c.kCFStringEncodingUTF8,
    );

    for (self.in_dir_paths, macos_paths[1..]) |str, *ref| {
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

    var ctx: Context = .{
        .reloader = reloader,
        .out_dir_path = self.out_dir_path,
    };

    var stream_context: c.FSEventStreamContext = .{ .info = &ctx };
    const stream: c.FSEventStreamRef = c.FSEventStreamCreate(
        null,
        &callback,
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
        @panic("failed to start the event stream");
    }

    c.CFRunLoopRun();

    c.FSEventStreamStop(stream);
    c.FSEventStreamInvalidate(stream);
    c.FSEventStreamRelease(stream);

    c.CFRelease(paths_to_watch);
}
