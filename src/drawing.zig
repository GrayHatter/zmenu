pub var g_cache: Ttf.GlyphCache = undefined;

var alloc: Allocator = undefined;
var ttf: Ttf = undefined;

pub fn init(a: Allocator) !void {
    alloc = a;
    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    ttf = try .load(@alignCast(font));
    g_cache = .init(&ttf, 0.01866);
}

pub fn raze() void {
    g_cache.raze(alloc);
    alloc.free(ttf.ttf_bytes);
}

pub fn text(buffer: *Buffer, string: []const u8, box: Buffer.Box, color: ARGB) !void {
    var next_x: i32 = 0;
    for (string) |g| {
        const glyph = try g_cache.get(alloc, g);
        buffer.drawFont(ARGB, color, .xywh(
            @intCast(@as(i32, @intCast(box.x)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(box.y)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

pub fn colors(size: usize, buffer: Buffer, color: Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = @intCast(x * 0xff / size);
        const r_y: usize = @intCast(y * 0xff / size);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c = ARGB.rgb(r, g, b);
        color.draw(.xywh(x, y, 1, 1), &[1]u32{c.int()});
        const b2: u8 = 0xff - g;
        const c2 = ARGB.rgb(r, g, b2);
        buffer.draw(.xywh(x, y, 1, 1), &[1]u32{@intFromEnum(c2)});
    };
}

pub fn background0(buf: *Buffer, box: Buffer.Box) !void {
    for (box.y..box.y2()) |y| for (box.x..box.x2()) |x| {
        const r_y: usize = @intCast(y * 0xff / buf.width);
        const r_x: usize = @intCast(x * 0xff / buf.width);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = 0xff - g;
        const c = ARGB.rgb(r, g, b);
        buf.drawPoint(ARGB, .xy(x, y), c);
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Charcoal = @import("charcoal");
const Ttf = Charcoal.TrueType;
const ARGB = Buffer.ARGB;
const Buffer = Charcoal.Buffer;
const Box = Buffer.Box;
test {
    _ = &std.testing.refAllDecls(@This());
}
