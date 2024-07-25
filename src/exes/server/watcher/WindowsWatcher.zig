const WindowsWatcher = @This();

const std = @import("std");
const windows = std.os.windows;
const Reloader = @import("../Reloader.zig");

const log = std.log.scoped(.watcher);

const Error = error{ InvalidHandle, QueueFailed, WaitFailed };

const CompletionKey = usize;
/// Values should be a multiple of `ReadBufferEntrySize`
const ReadBufferIndex = u32;
const ReadBufferEntrySize = 1024;

const WatchEntry = struct {
    kind: Kind,

    dir_path: [:0]const u8,
    dir_handle: windows.HANDLE,

    overlap: windows.OVERLAPPED = std.mem.zeroes(windows.OVERLAPPED),
    buf_idx: ReadBufferIndex,

    pub const Kind = enum { input, output };
};

iocp_port: windows.HANDLE,
entries: std.AutoHashMap(CompletionKey, WatchEntry),
read_buffer: []u8,

pub fn init(
    gpa: std.mem.Allocator,
    out_dir_path: []const u8,
    in_dir_paths: []const []const u8,
) !WindowsWatcher {
    var watcher = WindowsWatcher{
        .iocp_port = windows.INVALID_HANDLE_VALUE,
        .entries = std.AutoHashMap(CompletionKey, WatchEntry).init(gpa),
        .read_buffer = undefined,
    };
    errdefer {
        var iter = watcher.entries.valueIterator();
        while (iter.next()) |entry| {
            windows.CloseHandle(entry.dir_handle);
            gpa.free(entry.dir_path);
        }
        watcher.entries.deinit();
    }

    // Doubles as the number of WatchEntries
    var comp_key: CompletionKey = 0;

    {
        const out_path = try gpa.dupeZ(u8, out_dir_path);
        try watcher.entries.putNoClobber(
            comp_key,
            try addPath(out_path, comp_key, .output, &watcher.iocp_port),
        );
        comp_key += 1;
    }

    for (in_dir_paths) |path| {
        const in_path = try gpa.dupeZ(u8, path);
        try watcher.entries.putNoClobber(
            comp_key,
            try addPath(in_path, comp_key, .input, &watcher.iocp_port),
        );
        comp_key += 1;
    }

    watcher.read_buffer = try gpa.alloc(u8, ReadBufferEntrySize * comp_key);

    // Here we need pointers to both the read_buffer and entry overlapped structs,
    // which we can only do after setting up everything else.
    watcher.entries.lockPointers();
    for (0..comp_key) |key| {
        const entry = watcher.entries.getPtr(key).?;
        if (windows.kernel32.ReadDirectoryChangesW(
            entry.dir_handle,
            @ptrCast(@alignCast(&watcher.read_buffer[entry.buf_idx])),
            ReadBufferEntrySize,
            @intFromBool(true),
            windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME | windows.FILE_NOTIFY_CHANGE_DIR_NAME,
            null,
            &entry.overlap,
            null,
        ) == 0) {
            log.err("ReadDirectoryChanges error: {s}", .{@tagName(windows.kernel32.GetLastError())});
            return Error.QueueFailed;
        }
    }
    return watcher;
}

fn addPath(
    path: [:0]const u8,
    /// Assumed to increment by 1 after each invocation, starting at 0.
    key: CompletionKey,
    io: WatchEntry.Kind,
    port: *windows.HANDLE,
) !WatchEntry {
    const dir_handle = CreateFileA(
        path,
        windows.GENERIC_READ, // FILE_LIST_DIRECTORY,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_FLAG_BACKUP_SEMANTICS | windows.FILE_FLAG_OVERLAPPED,
        null,
    );
    if (dir_handle == windows.INVALID_HANDLE_VALUE) {
        log.err(
            "Unable to open directory {s}: {s}",
            .{ path, @tagName(windows.kernel32.GetLastError()) },
        );
        return Error.InvalidHandle;
    }

    if (port.* == windows.INVALID_HANDLE_VALUE) {
        port.* = try windows.CreateIoCompletionPort(dir_handle, null, key, 0);
    } else {
        _ = try windows.CreateIoCompletionPort(dir_handle, port.*, key, 0);
    }

    return .{
        .kind = io,
        .dir_path = path,
        .dir_handle = dir_handle,
        .buf_idx = @intCast(ReadBufferEntrySize * key),
    };
}

pub fn listen(
    self: *WindowsWatcher,
    gpa: std.mem.Allocator,
    reloader: *Reloader,
) !void {
    _ = gpa;

    var dont_care: struct {
        bytes_transferred: windows.DWORD = undefined,
        overlap: ?*windows.OVERLAPPED = undefined,
    } = .{};

    var key: CompletionKey = undefined;
    while (true) {
        // Waits here until any of the directory handles associated with the iocp port
        // have been updated.
        const wait_result = windows.GetQueuedCompletionStatus(
            self.iocp_port,
            &dont_care.bytes_transferred,
            &key,
            &dont_care.overlap,
            windows.INFINITE,
        );
        if (wait_result != .Normal) {
            log.err("GetQueuedCompletionStatus error: {s}", .{@tagName(wait_result)});
            return Error.WaitFailed;
        }

        const entry = self.entries.getPtr(key) orelse @panic("Invalid CompletionKey");

        var info_iter = windows.FileInformationIterator(FILE_NOTIFY_INFORMATION){
            .buf = self.read_buffer[entry.buf_idx..][0..ReadBufferEntrySize],
        };
        var path_buf: [windows.MAX_PATH]u8 = undefined;
        while (info_iter.next()) |info| {
            const filename: []const u8 = blk: {
                const n = try std.unicode.utf16LeToUtf8(
                    &path_buf,
                    @as([*]u16, @ptrCast(&info.FileName))[0 .. info.FileNameLength / 2],
                );
                break :blk path_buf[0..n];
            };

            const args = .{ @tagName(entry.kind), entry.dir_path, filename };
            switch (info.Action) {
                windows.FILE_ACTION_ADDED => log.debug("added ({s}) {s}/{s}", args),
                windows.FILE_ACTION_REMOVED => log.debug("removed ({s}) {s}/{s}", args),
                windows.FILE_ACTION_MODIFIED => log.debug("modified ({s}) {s}/{s}", args),
                windows.FILE_ACTION_RENAMED_OLD_NAME => log.debug("renamed_old_name ({s}) {s}/{s}", args),
                windows.FILE_ACTION_RENAMED_NEW_NAME => log.debug("renamed_new_name ({s}) {s}/{s}", args),
                else => log.debug("Unknown Action ({s}) {s}/{s}", args),
            }

            switch (entry.kind) {
                .input => reloader.onInputChange(entry.dir_path, filename),
                .output => reloader.onOutputChange(entry.dir_path, filename),
            }
        }

        // Re-queue the directory entry
        if (windows.kernel32.ReadDirectoryChangesW(
            entry.dir_handle,
            @ptrCast(@alignCast(&self.read_buffer[entry.buf_idx])),
            ReadBufferEntrySize,
            @intFromBool(true),
            windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME | windows.FILE_NOTIFY_CHANGE_DIR_NAME,
            null,
            &entry.overlap,
            null,
        ) == 0) {
            log.err("ReadDirectoryChanges error: {s}", .{@tagName(windows.kernel32.GetLastError())});
            return Error.QueueFailed;
        }
    }
}

const FILE_NOTIFY_INFORMATION = extern struct {
    NextEntryOffset: windows.DWORD,
    Action: windows.DWORD,
    FileNameLength: windows.DWORD,
    /// Flexible array member
    FileName: windows.WCHAR,
};

extern "kernel32" fn CreateFileA(
    lpFileName: windows.LPCSTR,
    dwDesiredAccess: windows.DWORD,
    dwShareMode: windows.DWORD,
    lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: windows.DWORD,
    dwFlagsAndAttributes: windows.DWORD,
    hTemplateFile: ?windows.HANDLE,
) callconv(windows.WINAPI) windows.HANDLE;
