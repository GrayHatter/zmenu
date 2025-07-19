pixels: []u8,
width: usize,
height: usize,
scale: f64,

const Canvas = @This();

pub fn init(alloc: Allocator, width: usize, height: usize) !Canvas {
    return try initScale(alloc, width, height, 0.0188866);
}

pub fn initScale(alloc: Allocator, width: usize, height: usize, scale: f64) !Canvas {
    const w: u64 = @intFromFloat(@ceil(@as(f64, @floatFromInt(width)) * scale));
    const h: u64 = @intFromFloat(@ceil(@as(f64, @floatFromInt(height)) * scale));
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

pub fn calcHeight(self: Canvas) i64 {
    return @intCast(self.pixels.len / self.width);
}

pub fn clampY(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, self.calcHeight()));
}

pub fn clampX(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, self.iWidth()));
}

fn getRow(c: Canvas, y: i64) ?[]u8 {
    const start: usize = c.width * @as(usize, @intCast(y));
    if (start >= c.pixels.len - c.width) return null;
    return c.pixels[start..][0..c.width];
}

pub fn draw(c: Canvas, y_int: i64, min_int: i64, max_int: i64) void {
    var y: f64 = @floatFromInt(y_int);
    var min: f64 = @floatFromInt(min_int);
    var max: f64 = @floatFromInt(max_int);
    const contra: u8 = if (@floor(y * c.scale) != @round(y * c.scale)) 0xAA else 0xFF;
    // Floor seems to look better, but I want to experment more
    if (comptime false) {
        y = @floor(y * c.scale);
        min = @floor(min * c.scale);
        max = @floor(max * c.scale);
    } else {
        y = @round(y * c.scale);
        min = @round(min * c.scale);
        max = @round(max * c.scale);
    }

    const x1: usize = c.clampX(@intFromFloat(min));
    const x2: usize = c.clampX(@intFromFloat(max));
    const row = c.getRow(@intFromFloat(y)) orelse return;
    for (row[x1..x2]) |*x| x.* |= contra;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
