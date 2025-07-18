buffer: *wl.Buffer,
raw: []u8,
w: u32,
h: u32,
stride: u32 = 4,

const Buffer = @This();

pub const Box = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,

    pub fn xywh(x: usize, y: usize, w: usize, h: usize) Box {
        return .{ .w = w, .h = h, .x = x, .y = y };
    }

    pub fn wh(w: usize, h: usize) Box {
        return .{ .w = w, .h = h, .x = 0, .y = 0 };
    }
};

pub fn init(shm: *wl.Shm, width: u32, height: u32, name: []const u8) !Buffer {
    const buffer, const raw = try newPool(shm, width, height, name);
    return .{
        .buffer = buffer,
        .raw = raw,
        .w = width,
        .h = height,
    };
}

pub fn raze(b: Buffer) void {
    b.buffer.destroy();
}

fn rowSlice(b: Buffer, y: usize) []u8 {
    return b.raw[b.w * b.stride * y ..][0 .. b.w * b.stride];
}

pub fn draw(b: Buffer, box: Box, src: []const u8) void {
    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        @memcpy(
            b.rowSlice(dy)[box.x * b.stride ..][0 .. box.w * b.stride],
            src[sy * box.w * b.stride ..][0 .. box.w * b.stride],
        );
    }
}

pub fn drawFont(b: Buffer, box: Box, src: []const u8) void {
    //std.debug.print("{}\n", .{box});
    for (0..box.h, box.y..) |sy, dy| {
        //std.debug.print("{} - {} {}\n", .{ box.h, dy, sy });
        const row = b.rowSlice(dy - box.h);
        for (box.x..box.x + box.w, 0..) |dx, sx| {
            const p: u8 = src[(box.h - 1 - sy) * box.w + sx];
            if (p == 0) continue;
            var pixel: [4]u8 = [4]u8{ p, p, p, 0xff };
            @memcpy(row[dx * b.stride ..][0..b.stride], pixel[0..4]);
        }
    }
}

fn newPool(shm: *wl.Shm, width: u32, height: u32, name: []const u8) !struct { *wl.Buffer, []u8 } {
    const stride = width * 4;
    const size: usize = stride * height;

    const fd = try posix.memfd_create(name, 0);
    try posix.ftruncate(fd, size);
    const data = try posix.mmap(
        null,
        size,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    const pool = try shm.createPool(fd, @intCast(size));
    defer pool.destroy();

    return .{
        try pool.createBuffer(0, @intCast(width), @intCast(height), @intCast(stride), .argb8888),
        data,
    };
}
const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;
