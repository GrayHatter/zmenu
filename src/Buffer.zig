raw: []u32,
pool: *wl.ShmPool,
buffer: *wl.Buffer,
width: u32,
height: u32,
stride: u32,

damaged: Box = .zero,

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
    purple = 0xffaa11ff, // I *feel* like this is more purpley
    cyan = 0xff00ffff,

    bittersweet_shimmer = 0xffbc4749,
    parchment = 0xfff2e8cf,

    ash_gray = 0xffcad2c5,
    cambridge_blue = 0xff84a98c,
    hookers_green = 0xff52796f,
    dark_slate_gray = 0xff354f52,
    charcoal = 0xff2f3e46,

    _,

    pub const MASK = struct {
        pub const A = 0xff000000;
        pub const R = 0x00ff0000;
        pub const G = 0x0000ff00;
        pub const B = 0x000000ff;
    };

    pub const SHIFT = struct {
        pub const A = 0x18;
        pub const R = 0x10;
        pub const G = 0x08;
        pub const B = 0x00;
    };

    pub fn rgb(r: u8, g: u8, b: u8) ARGB {
        const color: u32 = (0xff000000 |
            @as(u32, r) << SHIFT.R |
            @as(u32, g) << SHIFT.G |
            @as(u32, b) << SHIFT.B);

        return @enumFromInt(color);
    }

    pub fn int(color: ARGB) u32 {
        return @intFromEnum(color);
    }

    pub fn hex(i: u32) ARGB {
        return @enumFromInt(i);
    }

    pub fn fromBytes(bytes: [4]u8) ARGB {
        return @enumFromInt(@as(*align(1) const u32, @ptrCast(&bytes)).*);
    }

    pub fn alpha(src: ARGB, trans: u8) ARGB {
        const color: u32 = @intFromEnum(src);
        const mask: u32 = 0x00ffffff | (@as(u32, trans) << 24);
        return @enumFromInt(color & mask);
    }

    pub fn mix(src: ARGB, dest: *u32) void {
        const alp: u32 = (src.int() & MASK.A) >> SHIFT.A;
        const red: u32 = (src.int() & MASK.R) >> SHIFT.R;
        const gre: u32 = (src.int() & MASK.G) >> SHIFT.G;
        const blu: u32 = (src.int() & MASK.B) >> SHIFT.B;

        const r: u32 = (dest.* & MASK.R) >> SHIFT.R;
        const g: u32 = (dest.* & MASK.G) >> SHIFT.G;
        const b: u32 = (dest.* & MASK.B) >> SHIFT.B;

        //aOut = aA + (aB * (255 - aA) / 255);
        const color: u32 = 0xff000000 |
            (((red * alp + r * (0xff - alp)) / (0xff * 1)) << 0x10 & MASK.R) |
            (((gre * alp + g * (0xff - alp)) / (0xff * 1)) << 0x08 & MASK.G) |
            (((blu * alp + b * (0xff - alp)) / (0xff * 1)) << 0x00 & MASK.B);
        dest.* = color;
    }
};

pub const Box = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,

    pub const zero: Box = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub const Delta = struct {
        x: isize,
        y: isize,
        w: isize,
        h: isize,
        pub const zero: Delta = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

        pub fn scale(s: isize) Delta {
            return .{ .x = s, .y = s, .w = s * -2, .h = s * -2 };
        }

        pub fn xywh(x: isize, y: isize, w: isize, h: isize) Delta {
            return .{ .x = x, .y = y, .w = w, .h = h };
        }
    };

    pub inline fn x2(b: Box) usize {
        return b.x + b.w;
    }

    pub inline fn y2(b: Box) usize {
        return b.y + b.h;
    }

    pub fn xy(x: usize, y: usize) Box {
        return .{ .x = x, .y = y, .w = 0, .h = 0 };
    }

    pub fn xywh(x: usize, y: usize, w: usize, h: usize) Box {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn wh(w: usize, h: usize) Box {
        return .{ .w = w, .h = h, .x = 0, .y = 0 };
    }

    pub fn radius(x: usize, y: usize, r: usize) Box {
        return .{ .x = x, .y = y, .w = r, .h = r };
    }

    pub fn add(src: *Box, delta: Delta) void {
        src.x = @intCast(@as(isize, @intCast(src.x)) + delta.x);
        src.y = @intCast(@as(isize, @intCast(src.y)) + delta.y);
        src.w = @intCast(@as(isize, @intCast(src.w)) + delta.w);
        src.h = @intCast(@as(isize, @intCast(src.h)) + delta.h);
    }
};

pub fn init(shm: *wl.Shm, box: Box, name: []const u8) !Buffer {
    const pool, const buffer, const raw = try newPool(shm, @intCast(box.w), @intCast(box.h), name);
    return .{
        .buffer = buffer,
        .raw = raw,
        .width = @intCast(box.w),
        .height = @intCast(box.h),
        .stride = @intCast(box.w * 4),
        .pool = pool,
    };
}

pub fn raze(b: Buffer) void {
    b.buffer.destroy();
    b.pool.destroy();
}

pub fn getDamaged(b: *Buffer) Box {
    defer b.damaged = .zero;
    return b.damaged;
}

fn rowSlice(b: Buffer, y: usize) []u32 {
    return b.raw[b.width * y ..][0..b.width];
}

pub fn draw(b: Buffer, box: Box, src: []const u32) void {
    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            src[sy * box.w ..][0..box.w],
        );
    }
}

pub fn drawRectangle(b: Buffer, T: type, box: Box, ecolor: T) void {
    const width = box.x + box.w;
    const height = box.y + box.h;
    const color: u32 = @intFromEnum(ecolor);
    std.debug.assert(box.w > 3);
    std.debug.assert(box.h > 3);
    for (box.y + 1..height - 1) |y| {
        const row = b.rowSlice(y);
        row[box.x] = color;
        row[width - 1] = color;
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x..width], color);
    const bottom = b.rowSlice(height - 1);
    @memset(bottom[box.x..width], color);
}

pub fn drawRectangleFill(b: Buffer, T: type, box: Box, ecolor: T) void {
    const width = box.x + box.w;
    const height = box.y + box.h;
    const color: u32 = @intFromEnum(ecolor);
    std.debug.assert(box.w > 3);
    std.debug.assert(box.h > 3);
    for (box.y..height) |y| {
        const row = b.rowSlice(y);
        @memset(row[box.x..width], color);
    }
}

pub fn drawRectangleFillMix(b: Buffer, T: type, box: Box, ecolor: T) void {
    //const width = box.x + box.w;
    const height = box.y + box.h;
    //const color: u32 = @intFromEnum(ecolor);
    std.debug.assert(box.w > 3);
    std.debug.assert(box.h > 3);
    for (box.y..height) |y| {
        const row = b.rowSlice(y);
        for (box.x..box.x2()) |x| {
            ecolor.mix(&row[x]);
        }
    }
}

pub fn drawRectangleRounded(b: Buffer, T: type, box: Box, base_r: f64, ecolor: T) void {
    const r: f64 = base_r - 0.5;
    const color: u32 = @intFromEnum(ecolor);
    const radius: usize = @intFromFloat(base_r);
    std.debug.assert(box.w > radius);
    std.debug.assert(box.h > radius);
    for (box.y..box.y + radius, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
    }

    for (box.y2() - radius..box.y2(), radius..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
    }

    for (box.y + radius..box.y2() - radius) |y| {
        const row = b.rowSlice(y);
        row[box.x] = color;
        row[box.x2() - 1] = color;
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x + radius .. box.x2() - radius], color);
    const bottom = b.rowSlice(box.y2() - 1);
    @memset(bottom[box.x + radius .. box.x2() - radius], color);
}

pub fn drawRectangleRoundedFill(b: Buffer, T: type, box: Box, base_r: f64, ecolor: T) void {
    const r: f64 = base_r - 0.5;
    const radius: usize = @intFromFloat(base_r);
    const color: u32 = @intFromEnum(ecolor);
    std.debug.assert(box.w > radius);
    std.debug.assert(box.h > radius);
    for (box.y..box.y + radius, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r + 0.0;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0) row[dst_x] = color;
        }
        @memset(row[box.x + radius .. box.x2() - radius], color);
    }

    for (box.y2() - radius..box.y2(), radius..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel < 1.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel < 1.0) row[dst_x] = color;
        }
        @memset(row[box.x + radius .. box.x2() - radius], color);
    }

    for (box.y + radius..box.y2() - radius) |y| {
        const row = b.rowSlice(y);
        @memset(row[box.x..box.x2()], color);
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x + radius .. box.x2() - radius], color);
    const bottom = b.rowSlice(box.y2() - 1);
    @memset(bottom[box.x + radius .. box.x2() - radius], color);
}

pub fn drawPoint(b: Buffer, T: type, box: Box, ecolor: T) void {
    std.debug.assert(box.w < 2);
    std.debug.assert(box.h < 2);
    const color: u32 = @intFromEnum(ecolor);
    const row = b.rowSlice(box.y);
    row[box.x] = color;
}

pub fn drawCircle(b: Buffer, T: type, box: Box, ecolor: T) void {
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    for (box.y..box.y + box.w, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (box.x..box.x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel <= 1) row[dst_x] = color;
        }
    }
}

/// TODO add support for center vs corner alignment
pub fn drawCircleFill(b: Buffer, T: type, box: Box, ecolor: T) void {
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    for (box.y..box.y + box.w, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (box.x..box.x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel < 1.5 and pixel > 0.5) row[dst_x] = color;
        }
    }
}

pub fn drawCircleCentered(b: Buffer, T: type, box: Box, ecolor: T) void {
    std.debug.assert(box.h == box.w);
    std.debug.assert(box.x > (box.w - 1) / 2);
    std.debug.assert(box.y > (box.h - 1) / 2);
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    const adj_x: u32 = @truncate(box.x - @as(u32, @intFromFloat(@floor(half + 0.6))));
    const adj_y: u32 = @truncate(box.y - @as(u32, @intFromFloat(@floor(half + 0.6))));

    for (adj_y..adj_y + box.h, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (adj_x..adj_x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel <= 1) row[dst_x] = color;
        }
    }
}

pub fn drawFont(b: Buffer, T: type, color: T, box: Box, src: []const u8) void {
    //std.debug.print("{}\n", .{box});
    for (1..box.h + 1, box.y..) |sy, dy| {
        //std.debug.print("{} - {} {}\n", .{ box.h, dy, sy });
        const row = b.rowSlice(dy - box.h);
        for (box.x..box.x + box.w, 0..) |dx, sx| {
            const p: u8 = src[(box.h - sy) * box.w + sx];
            if (p == 0) continue;
            const color2 = color.alpha(p);
            color2.mix(&row[dx]);
        }
    }
}

fn newPool(shm: *wl.Shm, width: u32, height: u32, name: []const u8) !struct { *wl.ShmPool, *wl.Buffer, []u32 } {
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
    const buffer = try pool.createBuffer(0, @intCast(width), @intCast(height), @intCast(stride), .argb8888);
    return .{ pool, buffer, @ptrCast(data) };
}

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;
const hypot = std.math.hypot;
