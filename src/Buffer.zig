buffer: *wl.Buffer,
raw: []u32,
w: u32,
h: u32,

const Buffer = @This();

pub const BGRA = enum(u32) {
    transparent = 0x00000000,
    white = 0xffffffff,
    black = 0x000000ff,
    _,

    pub fn rgb(r: u8, g: u8, b: u8) ARGB {
        comptime unreachable; // wrong shifts
        const color: u32 = (0xff000000 |
            @as(u32, r) << 16 |
            @as(u32, g) << 8 |
            @as(u32, b));

        return @enumFromInt(color);
    }
    pub fn int(color: BGRA) u32 {
        return @intFromEnum(color);
    }

    pub fn fromBytes(bytes: [4]u8) BGRA {
        return @enumFromInt(@as(*align(1) const u32, @ptrCast(&bytes)).*);
    }
};

pub const ARGB = enum(u32) {
    transparent = 0x00000000,
    white = 0xffffffff,
    black = 0xff000000,
    red = 0xffff0000,
    green = 0xff00ff00,
    blue = 0xff0000ff,
    _,

    pub fn rgb(r: u8, g: u8, b: u8) ARGB {
        const color: u32 = (0xff000000 |
            @as(u32, r) << 16 |
            @as(u32, g) << 8 |
            @as(u32, b));

        return @enumFromInt(color);
    }

    pub fn int(color: ARGB) u32 {
        return @intFromEnum(color);
    }

    pub fn fromBytes(bytes: [4]u8) ARGB {
        return @enumFromInt(@as(*align(1) const u32, @ptrCast(&bytes)).*);
    }
};

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

fn rowSlice(b: Buffer, y: usize) []u32 {
    return b.raw[b.w * y ..][0..b.w];
}

pub fn draw(b: Buffer, box: Box, src: []const u32) void {
    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            src[sy * box.w ..][0..box.w],
        );
    }
}

pub fn drawFont(b: Buffer, T: type, color: T, box: Box, src: []const u8) void {
    //std.debug.print("{}\n", .{box});
    for (0..box.h, box.y..) |sy, dy| {
        //std.debug.print("{} - {} {}\n", .{ box.h, dy, sy });
        const row = b.rowSlice(dy - box.h);
        for (box.x..box.x + box.w, 0..) |dx, sx| {
            const p: u8 = src[(box.h - 1 - sy) * box.w + sx];
            if (p == 0) continue;
            const pixel: u32 = @intFromEnum(color);
            row[dx] = pixel;
        }
    }
}

fn newPool(shm: *wl.Shm, width: u32, height: u32, name: []const u8) !struct { *wl.Buffer, []u32 } {
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
        @ptrCast(data),
    };
}

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;
