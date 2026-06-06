const WindowsWatcher = @This();

const std = @import("std");
const Io = std.Io;
const windows = std.os.windows;
const fatal = @import("../../../fatal.zig");
const Debouncer = @import("../../serve.zig").Debouncer;

const log = std.log.scoped(.watcher);

// Types removed from std.os.windows in zig-0.16.
const OVERLAPPED = extern struct {
    Internal: windows.ULONG_PTR = 0,
    InternalHigh: windows.ULONG_PTR = 0,
    Offset: windows.DWORD = 0,
    OffsetHigh: windows.DWORD = 0,
    hEvent: ?windows.HANDLE = null,
};

// Constants removed from std.os.windows in zig-0.16.
const GENERIC_READ: windows.DWORD = 0x80000000;
const FILE_SHARE_READ: windows.DWORD = 0x00000001;
const FILE_SHARE_WRITE: windows.DWORD = 0x00000002;
const FILE_SHARE_DELETE: windows.DWORD = 0x00000004;
const OPEN_EXISTING: windows.DWORD = 3;
const INFINITE: windows.DWORD = 0xFFFFFFFF;

const FILE_ACTION_ADDED: windows.DWORD = 1;
const FILE_ACTION_REMOVED: windows.DWORD = 2;
const FILE_ACTION_MODIFIED: windows.DWORD = 3;
const FILE_ACTION_RENAMED_OLD_NAME: windows.DWORD = 4;
const FILE_ACTION_RENAMED_NEW_NAME: windows.DWORD = 5;
const win32 = struct {
    pub extern "kernel32" fn CloseHandle(hObject: windows.HANDLE) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn ReadDirectoryChangesW(
        hDirectory: windows.HANDLE,
        lpBuffer: *anyopaque,
        nBufferLength: windows.DWORD,
        bWatchSubtree: windows.BOOL,
        dwNotifyFilter: windows.DWORD,
        lpBytesReturned: ?*windows.DWORD,
        lpOverlapped: ?*OVERLAPPED,
        lpCompletionRoutine: ?*anyopaque,
    ) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn GetQueuedCompletionStatus(
        CompletionPort: windows.HANDLE,
        lpNumberOfBytesTransferred: *windows.DWORD,
        lpCompletionKey: *windows.ULONG_PTR,
        lpOverlapped: *?*OVERLAPPED,
        dwMilliseconds: windows.DWORD,
    ) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn CreateFileW(
        lpFileName: [*:0]const windows.WCHAR,
        dwDesiredAccess: windows.DWORD,
        dwShareMode: windows.DWORD,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: windows.DWORD,
        dwFlagsAndAttributes: windows.DWORD,
        hTemplateFile: ?windows.HANDLE,
    ) callconv(.winapi) windows.HANDLE;
    pub extern "kernel32" fn PostQueuedCompletionStatus(
        CompletionPort: windows.HANDLE,
        dwNumberOfBytesTransferred: windows.DWORD,
        dwCompletionKey: windows.ULONG_PTR,
        lpOverlapped: ?*OVERLAPPED,
    ) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn GetFileAttributesW(lpFileName: [*:0]const windows.WCHAR) callconv(.winapi) windows.DWORD;
    pub extern "kernel32" fn CreateIoCompletionPort(
        FileHandle: windows.HANDLE,
        ExistingCompletionPort: ?windows.HANDLE,
        CompletionKey: windows.ULONG_PTR,
        NumberOfConcurrentThreads: windows.DWORD,
    ) callconv(.winapi) ?windows.HANDLE;
};

const notify_filter: windows.DWORD =
    0x00000001 | // FILE_NOTIFY_CHANGE_FILE_NAME
    0x00000002 | // FILE_NOTIFY_CHANGE_DIR_NAME
    0x00000008 | // FILE_NOTIFY_CHANGE_SIZE
    0x00000010 | // FILE_NOTIFY_CHANGE_LAST_WRITE
    0x00000040; //  FILE_NOTIFY_CHANGE_CREATION

// const notify_filter = windows.FileNotifyChangeFilter{
//     .file_name = true,
//     .dir_name = true,
//     .attributes = false,
//     .size = false,
//     .last_write = true,
//     .last_access = false,
//     .creation = false,
//     .security = false,
// };

const CompletionKey = usize;
/// Values should be a multiple of `ReadBufferEntrySize`
const ReadBufferIndex = u32;
const ReadBufferEntrySize = 1024;

const WatchEntry = struct {
    dir_path: [:0]const u8,
    dir_handle: windows.HANDLE,

    overlap: OVERLAPPED = std.mem.zeroes(OVERLAPPED),
    buf_idx: ReadBufferIndex,
};

io: Io,
debouncer: *Debouncer,
iocp_port: windows.HANDLE,
entries: std.AutoHashMap(CompletionKey, WatchEntry),
read_buffer: []u8,

pub fn init(
    io: Io,
    gpa: std.mem.Allocator,
    debouncer: *Debouncer,
    dir_paths: []const []const u8,
) WindowsWatcher {
    return initInner(io, gpa, debouncer, dir_paths) catch |err| fatal.msg("error: unable to start the file watcher: {s}", .{
        @errorName(err),
    });
}

pub fn initInner(
    io: Io,
    gpa: std.mem.Allocator,
    debouncer: *Debouncer,
    dir_paths: []const []const u8,
) !WindowsWatcher {
    var watcher = WindowsWatcher{
        .io = io,
        .debouncer = debouncer,
        .iocp_port = windows.INVALID_HANDLE_VALUE,
        .entries = std.AutoHashMap(CompletionKey, WatchEntry).init(gpa),
        .read_buffer = undefined,
    };
    errdefer {
        var iter = watcher.entries.valueIterator();
        while (iter.next()) |entry| {
            _ = win32.CloseHandle(entry.dir_handle);
            gpa.free(entry.dir_path);
        }
        watcher.entries.deinit();
    }

    // Doubles as the number of WatchEntries
    var comp_key: CompletionKey = 0;

    for (dir_paths) |path| {
        const in_path = try gpa.dupeSentinel(u8, path, 0);
        try watcher.entries.putNoClobber(
            comp_key,
            try addPath(in_path, comp_key, &watcher.iocp_port),
        );
        comp_key += 1;
    }

    watcher.read_buffer = try gpa.alloc(u8, ReadBufferEntrySize * comp_key);

    // Here we need pointers to both the read_buffer and entry overlapped structs,
    // which we can only do after setting up everything else.
    watcher.entries.lockPointers();
    for (0..comp_key) |key| {
        const entry = watcher.entries.getPtr(key).?;
        if (win32.ReadDirectoryChangesW(
            entry.dir_handle,
            @ptrCast(@alignCast(&watcher.read_buffer[entry.buf_idx])),
            ReadBufferEntrySize,
            .TRUE,
            notify_filter,
            null,
            &entry.overlap,
            null,
        ) == .FALSE) {
            log.err("ReadDirectoryChanges error", .{});
            return error.QueueFailed;
        }
    }
    return watcher;
}

fn addPath(
    path: [:0]const u8,
    /// Assumed to increment by 1 after each invocation, starting at 0.
    key: CompletionKey,
    port: *windows.HANDLE,
) !WatchEntry {
    const dir_handle = CreateFileA(
        path,
        GENERIC_READ, // FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        null,
        OPEN_EXISTING,
        0x02000000 | 0x40000000, // FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED
        null,
    );
    if (dir_handle == windows.INVALID_HANDLE_VALUE) {
        log.err("Unable to open directory {s}", .{path});
        return error.InvalidHandle;
    }

    if (port.* == windows.INVALID_HANDLE_VALUE) {
        port.* = win32.CreateIoCompletionPort(dir_handle, null, key, 0) orelse return error.Unexpected;
    } else {
        _ = win32.CreateIoCompletionPort(dir_handle, port.*, key, 0) orelse return error.Unexpected;
    }

    return .{
        .dir_path = path,
        .dir_handle = dir_handle,
        .buf_idx = @intCast(ReadBufferEntrySize * key),
    };
}

pub fn start(watcher: *WindowsWatcher) !void {
    const t = try std.Thread.spawn(.{}, WindowsWatcher.listen, .{watcher});
    t.detach();
}

pub fn listen(watcher: *WindowsWatcher) !void {
    var dont_care: struct {
        bytes_transferred: windows.DWORD = undefined,
        overlap: ?*OVERLAPPED = undefined,
    } = .{};

    var key: CompletionKey = undefined;
    while (true) {
        // Waits here until any of the directory handles associated with the iocp port
        // have been updated.
        const wait_result = win32.GetQueuedCompletionStatus(
            watcher.iocp_port,
            &dont_care.bytes_transferred,
            &key,
            &dont_care.overlap,
            INFINITE,
        );
        if (wait_result == .FALSE) {
            log.err("GetQueuedCompletionStatus error: {s}", .{@tagName(wait_result)});
            return error.WaitFailed;
        }

        const entry = watcher.entries.getPtr(key) orelse @panic("Invalid CompletionKey");

        var info_iter = windows.FileInformationIterator(FILE_NOTIFY_INFORMATION){
            .buf = watcher.read_buffer[entry.buf_idx..][0..ReadBufferEntrySize],
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

            const args = .{ entry.dir_path, filename };
            switch (info.Action) {
                FILE_ACTION_ADDED => log.debug("added  {s}/{s}", args),
                FILE_ACTION_REMOVED => log.debug("removed  {s}/{s}", args),
                FILE_ACTION_MODIFIED => log.debug("modified  {s}/{s}", args),
                FILE_ACTION_RENAMED_OLD_NAME => log.debug("renamed_old_name {s}/{s}", args),
                FILE_ACTION_RENAMED_NEW_NAME => log.debug("renamed_new_name  {s}/{s}", args),
                else => log.debug("Unknown Action {s}/{s}", args),
            }

            watcher.debouncer.newEvent();
        }

        // Re-queue the directory entry
        if (win32.ReadDirectoryChangesW(
            entry.dir_handle,
            @ptrCast(@alignCast(&watcher.read_buffer[entry.buf_idx])),
            ReadBufferEntrySize,
            .TRUE,
            notify_filter,
            null,
            &entry.overlap,
            null,
        ) == .FALSE) {
            log.err("ReadDirectoryChanges error for: {s}", .{entry.dir_path});
            return error.QueueFailed;
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
) callconv(.winapi) windows.HANDLE;
