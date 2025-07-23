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
    //const w: u64 = (@as(usize, @intFromFloat(@ceil(w_f * scale))) + 7) & ~@as(usize, 7);
    //const h: u64 = (@as(usize, @intFromFloat(@ceil(h_f * scale))) + 7) & ~@as(usize, 7);
    const w: u64 = (@as(usize, @intFromFloat(@ceil(w_f * scale))));
    const h: u64 = (@as(usize, @intFromFloat(@ceil(h_f * scale))));

    const pixels = try alloc.alloc(u8, w * h);
    @memset(pixels, 0);
    return .{ .pixels = pixels, .width = w, .height = h, .scale = scale };
}

pub fn iWidth(self: Canvas) i64 {
    return @intCast(self.width);
}

pub fn clampY(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, @as(isize, @intCast(self.height - 1))));
}

pub fn clampX(self: Canvas, val: i64) usize {
    return @intCast(std.math.clamp(val, 0, self.iWidth()));
}

pub fn getRow(c: Canvas, y_sign: i64) ?[]u8 {
    const y = c.clampY(y_sign);
    return c.pixels[y * c.width ..][0..c.width];
}

const debug_rendering: bool = false;

pub fn draw(c: Canvas, y_int: i64, min_int: i64, max_int: i64) void {
    const y_f: f64 = @floatFromInt(y_int);
    const y = y_f * c.scale;
    const row_y: u32 = @intFromFloat(@round(y));
    const y_alpha: f64 = (y - @trunc(y));

    const min_f: f64 = @floatFromInt(min_int);
    const x1_alpha = min_f * c.scale - @trunc(min_f * c.scale);
    const min = min_f * c.scale;
    const x1: usize = c.clampX(@intFromFloat(min));

    const max_f: f64 = @floatFromInt(max_int);
    const x2_alpha = max_f * c.scale - @trunc(max_f * c.scale);
    const max = @max(@floor(max_f * c.scale), min);
    const x2: usize = c.clampX(@intFromFloat(max));

    if (comptime debug_rendering) std.debug.print("drawing {d:4} {d:4.4} {d:4} {d:5} {d:5}   ||| ", .{ y_int, y, row_y, min_int, max_int });
    if (comptime debug_rendering) std.debug.print(
        "x1..x2 {d:6.5} {d:6.5} + {d:6.5}-{d:6.5},{d:6.5} || reduced x1..x2 {d:4} {d:4}\n",
        .{ min, max, x1_alpha, x2_alpha, y_alpha, x1, x2 },
    );
    if (x1 == x2) return;
    const row = c.getRow(row_y) orelse return;
    for (x1..x2) |i| {
        row[i] = @max(row[i], @as(u8, @intFromFloat(y_alpha * 255.0)));
    }
    if (x2 < row.len) {
        row[x2] = @max(row[x2], @as(u8, @intFromFloat(x2_alpha * y_alpha * 255)));
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
