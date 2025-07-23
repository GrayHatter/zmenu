pixels: []u8,
width: usize,
height: usize,
scale: f64,

const Canvas = @This();

pub fn init(alloc: Allocator, width: usize, height: usize) !Canvas {
    return try initScale(alloc, width, height, 0.0188);
}

pub fn initScale(alloc: Allocator, width: usize, height: usize, scale: f64) !Canvas {
    const w_f: f64 = @floatFromInt(width);
    const h_f: f64 = @floatFromInt(height);
    const w: u64 = (@as(usize, @intFromFloat(@ceil(w_f * scale))) + 7) & ~@as(usize, 7);
    const h: u64 = (@as(usize, @intFromFloat(@ceil(h_f * scale))) + 7) & ~@as(usize, 7);

    const pixels = try alloc.alloc(u8, w * h);
    @memset(pixels, 0);

    return .{
        .pixels = pixels,
        .width = w,
        .height = h,
        .scale = scale,
    };
}

pub fn iWidth(self: Canvas) i64 {
    return @intCast(self.width);
}

pub fn clampY(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, @as(isize, @intCast(self.height))));
}

pub fn clampX(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, self.iWidth()));
}

fn getRow(c: Canvas, y: i64) ?[]u8 {
    const start: usize = c.width * c.clampY(y);
    if (start >= c.pixels.len - c.width) return null;
    return c.pixels[start..][0..c.width];
}

pub fn draw(c: Canvas, y_int: i64, min_int: i64, max_int: i64) void {
    var y: f64 = @floatFromInt(y_int);
    var min: f64 = @floatFromInt(min_int);
    var max: f64 = @floatFromInt(max_int);
    y *= c.scale;
    min *= c.scale;
    max = @max(@floor(max * c.scale), min);
    const x1: usize = c.clampX(@intFromFloat(min));
    const x2: usize = c.clampX(@intFromFloat(max));
    if (x1 == x2) return;
    const alpha: u8 = @intFromFloat(@round((y - @trunc(y)) * 255.0));
    const row = c.getRow(@intFromFloat(@ceil(y))) orelse return;
    for (x1..x2) |i| {
        row[i] = @max(row[i], alpha);
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
