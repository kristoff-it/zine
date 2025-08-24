const std = @import("std");
const builtin = @import("builtin");
const supermd = @import("supermd");
const wuffs = @import("wuffs");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.wuffs);

const win = if (builtin.os.tag != .windows) void else struct {
    //HANDLE CreateFileMappingA(
    //  [in]           HANDLE                hFile,
    //  [in, optional] LPSECURITY_ATTRIBUTES lpFileMappingAttributes,
    //  [in]           DWORD                 flProtect,
    //  [in]           DWORD                 dwMaximumSizeHigh,
    //  [in]           DWORD                 dwMaximumSizeLow,
    //  [in, optional] LPCSTR                lpName
    //);
    extern "kernel32" fn CreateFileMappingA(
        hFile: windows.HANDLE,
        lpFileMappingAttributes: ?*windows.SECURITY_ATTRIBUTES,
        flProtect: windows.DWORD,
        dwMaximumSizeHigh: windows.DWORD,
        dwMaximumSizeLow: windows.DWORD,
        lpName: ?windows.LPCSTR,
    ) callconv(.winapi) windows.HANDLE;

    //LPVOID MapViewOfFile(
    //  [in] HANDLE hFileMappingObject,
    //  [in] DWORD  dwDesiredAccess,
    //  [in] DWORD  dwFileOffsetHigh,
    //  [in] DWORD  dwFileOffsetLow,
    //  [in] SIZE_T dwNumberOfBytesToMap
    //);
    extern "kernel32" fn MapViewOfFile(
        hFileMappingObject: windows.HANDLE,
        dwDesiredAccess: windows.DWORD,
        dwFileOffsetHigh: windows.DWORD,
        dwFileOffsetLow: windows.DWORD,
        dwNumberOfBytesToMap: windows.SIZE_T,
    ) callconv(.winapi) [*]u8;

    //BOOL UnmapViewOfFile(
    //  [in] LPCVOID lpBaseAddress
    //);
    extern "kernel32" fn UnmapViewOfFile(
        lpBaseAddress: windows.LPCVOID,
    ) callconv(.winapi) windows.BOOL;

    // extern "kernel32" fn CreateFileA(
    //     lpFileName: windows.LPCSTR,
    //     dwDesiredAccess: windows.DWORD,
    //     dwShareMode: windows.DWORD,
    //     lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
    //     dwCreationDisposition: windows.DWORD,
    //     dwFlagsAndAttributes: windows.DWORD,
    //     hTemplateFile: ?windows.HANDLE,
    // ) callconv(.winapi) windows.HANDLE;
};

pub fn setImageSize(
    gpa: Allocator,
    directive: *supermd.Directive,
    base_dir: std.fs.Dir,
    image_path: []const u8,
) void {
    log.debug("calculating size for '{s}'", .{image_path});
    var file_mapping: if (builtin.target.os.tag != .windows) void else windows.HANDLE = undefined;
    const data = blk: {
        const image = base_dir.openFile(image_path, .{}) catch |err| {
            log.debug("erro while opening the image file '{s}': {}", .{
                image_path, err,
            });
            return;
        };

        defer image.close();

        const stat = image.stat() catch |err| {
            log.debug("unable to stat image '{s}': {}", .{ image_path, err });
            return;
        };

        log.debug("image stat:'{any}'", .{stat});

        const ptr = switch (builtin.target.os.tag) {
            .windows => winblk: {
                //TODO: how do we detect failures here?
                file_mapping = win.CreateFileMappingA(
                    image.handle,
                    null,
                    windows.PAGE_READONLY,
                    0,
                    0,
                    null,
                );

                const ptr = win.MapViewOfFile(file_mapping, 1 << 2, 0, 0, 0);
                break :winblk ptr;
            },
            else => std.posix.mmap(
                null,
                stat.size,
                std.posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                image.handle,
                0,
            ) catch |err| {
                log.debug("mmap of '{s}' failed: {}", .{ image_path, err });
                return;
            },
        };

        break :blk ptr[0..stat.size];
    };

    defer switch (builtin.target.os.tag) {
        .windows => {
            _ = win.UnmapViewOfFile(data.ptr);
            windows.CloseHandle(file_mapping);
        },
        else => std.posix.munmap(data),
    };

    const img_size = parseImageSize(gpa, data) catch |err| {
        log.debug("failure when trying to detect image size of '{s}': {}", .{
            image_path, err,
        });
        return;
    };

    log.debug("computed size: '{any}'", .{img_size});

    directive.kind.image.size = .{ .w = img_size.w, .h = img_size.h };
}

const Size = struct { w: i64, h: i64 };
fn parseImageSize(
    gpa: Allocator,
    image_src: []const u8,
) !Size {
    var g_src = wuffs.wuffs_base__ptr_u8__reader(@constCast(image_src.ptr), image_src.len, true);

    const g_fourcc = wuffs.wuffs_base__magic_number_guess_fourcc(
        wuffs.wuffs_base__io_buffer__reader_slice(&g_src),
        g_src.meta.closed,
    );
    if (g_fourcc < 0) return error.CouldNotGuessFileFormat;

    const decoder_raw, const g_image_decoder = switch (g_fourcc) {
        wuffs.WUFFS_BASE__FOURCC__BMP => try allocDecoder(gpa, "bmp"),
        wuffs.WUFFS_BASE__FOURCC__GIF => try allocDecoder(gpa, "gif"),
        wuffs.WUFFS_BASE__FOURCC__JPEG => try allocDecoder(gpa, "jpeg"),
        wuffs.WUFFS_BASE__FOURCC__NPBM => try allocDecoder(gpa, "netpbm"),
        wuffs.WUFFS_BASE__FOURCC__NIE => try allocDecoder(gpa, "nie"),
        wuffs.WUFFS_BASE__FOURCC__PNG => try allocDecoder(gpa, "png"),
        wuffs.WUFFS_BASE__FOURCC__QOI => try allocDecoder(gpa, "qoi"),
        wuffs.WUFFS_BASE__FOURCC__TGA => try allocDecoder(gpa, "tga"),
        wuffs.WUFFS_BASE__FOURCC__WBMP => try allocDecoder(gpa, "wbmp"),
        wuffs.WUFFS_BASE__FOURCC__WEBP => try allocDecoder(gpa, "webp"),
        else => {
            return error.UnsupportedImageFormat;
        },
    };
    defer gpa.free(decoder_raw);

    var g_image_config = std.mem.zeroes(wuffs.wuffs_base__image_config);
    try wrapErr(wuffs.wuffs_base__image_decoder__decode_image_config(
        g_image_decoder,
        &g_image_config,
        &g_src,
    ));

    const g_width = wuffs.wuffs_base__pixel_config__width(&g_image_config.pixcfg);
    const g_height = wuffs.wuffs_base__pixel_config__height(&g_image_config.pixcfg);

    return .{
        .w = std.math.cast(i64, g_width) orelse return error.Cast,
        .h = std.math.cast(i64, g_height) orelse return error.Cast,
    };
}
const max_align: std.mem.Alignment = .of(std.c.max_align_t);
fn allocDecoder(
    gpa: Allocator,
    comptime name: []const u8,
) !struct { []align(max_align.toByteUnits()) u8, *wuffs.wuffs_base__image_decoder } {
    const size = @field(wuffs, "sizeof__wuffs_" ++
        name ++ "__decoder")();
    const init_fn = @field(wuffs, "wuffs_" ++
        name ++ "__decoder__initialize");
    const upcast_fn = @field(wuffs, "wuffs_" ++
        name ++ "__decoder__upcast_as__wuffs_base__image_decoder");

    const decoder_raw = try gpa.alignedAlloc(u8, max_align, size);
    errdefer gpa.free(decoder_raw);
    for (decoder_raw) |*byte| byte.* = 0;

    try wrapErr(init_fn(
        @ptrCast(decoder_raw),
        size,
        wuffs.WUFFS_VERSION,
        wuffs.WUFFS_INITIALIZE__ALREADY_ZEROED,
    ));

    const upcasted = upcast_fn(@ptrCast(decoder_raw)).?;
    return .{ decoder_raw, upcasted };
}

fn wrapErr(status: wuffs.wuffs_base__status) !void {
    if (wuffs.wuffs_base__status__message(&status)) |x| {
        _ = x;
        // const y: [*:0]const u8 = x;
        // std.debug.print("Wuffs image parsing returned an error: \"{s}\", image sizes may not be emitted. Consider stripping Exif data.\n", .{y});
        return error.WuffsError;
    }
}
