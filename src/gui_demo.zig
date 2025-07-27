const charcoal = @import("charcoal");
const Buffer = charcoal.Buffer;
const Ui = charcoal.Ui;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    const box: Buffer.Box = .wh(1000, 1000);

    var char: charcoal.Charcoal = try .init();
    try char.connect();
    try char.wayland.resize(box);
    defer char.raze();

    var root = Ui.Component{
        .vtable = .auto(struct {}),
        .box = box,
        .children = &.{},
    };
    char.ui.root = &root;

    const shm = char.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, box, "buffer1");
    defer buffer.raze();
    const colors: Buffer = try .init(shm, box, "buffer2");
    defer colors.buffer.destroy();
    try drawColors(box.w, buffer, colors);

    try char.wayland.roundtrip();

    const surface = char.wayland.surface orelse return error.NoSurface;
    surface.attach(colors.buffer, 0, 0);
    surface.commit();
    try char.wayland.roundtrip();

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.load(@alignCast(font));

    const small_font = false;
    glyph_cache = .init(&ttf, 0.01866);
    if (small_font) {
        glyph_cache.scale_vert = 0.0195;
        glyph_cache.scale_horz = 0.025;
    }
    defer glyph_cache.raze(alloc);

    try drawText2(alloc, &buffer);

    try drawText3(alloc, &buffer);

    try drawText4(alloc, &buffer);

    colors.drawRectangle(Buffer.ARGB, .xywh(50, 50, 50, 50), .green);
    colors.drawRectangleFill(Buffer.ARGB, .xywh(100, 75, 50, 50), .purple);
    colors.drawCircle(Buffer.ARGB, .xywh(200, 200, 50, 50), .purple);
    colors.drawCircle(Buffer.ARGB, .xywh(800, 100, 50, 50), .purple);

    colors.drawCircleFill(Buffer.ARGB, .xywh(300, 200, 50, 50), .purple);
    colors.drawCircleFill(Buffer.ARGB, .xywh(700, 100, 50, 50), .purple);

    colors.drawPoint(Buffer.ARGB, .xy(300, 200), .black);

    colors.drawCircleCentered(Buffer.ARGB, .radius(700, 100, 11), .cyan);
    colors.drawPoint(Buffer.ARGB, .xy(700, 100), .black);

    colors.drawRectangleRounded(Buffer.ARGB, .xywh(10, 300, 200, 50), 10, .red);
    colors.drawRectangleRoundedFill(Buffer.ARGB, .xywh(10, 400, 200, 20), 3, .parchment);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(10, 400, 200, 20), 3, .bittersweet_shimmer);

    colors.drawRectangleRoundedFill(Buffer.ARGB, .xywh(40, 600, 300, 40), 10, .parchment);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(40, 600, 300, 40), 10, .bittersweet_shimmer);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(41, 601, 298, 38), 9, .bittersweet_shimmer);

    buffer.drawRectangleFill(Buffer.ARGB, .xywh(130, 110, 200, 50), .blue);
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(30, 100, 200, 50), .red);
    buffer.drawRectangleFillMix(Buffer.ARGB, .xywh(130, 110, 200, 50), .alpha(.blue, 0xc8));
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(400, 100, 100, 50), @enumFromInt(0xffff00ff));

    buffer.drawRectangleFill(Buffer.ARGB, .xywh(130, 410, 200, 50), .blue);
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(30, 300, 200, 50), .red);
    buffer.drawRectangleFillMix(Buffer.ARGB, .xywh(130, 410, 200, 50), .alpha(.blue, 0x88));
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(400, 400, 100, 50), .hex(0xffff00ff));

    var i: usize = 0;
    while (char.wayland.connected) {
        try char.wayland.iterate();
        i +%= 1;
        if (i % 100 == 0) {
            if (i / 100 & 1 > 0) {
                surface.attach(colors.buffer, 0, 0);
                surface.damage(0, 0, @intCast(box.w), @intCast(box.h));
                surface.commit();
            } else {
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(0, 0, @intCast(box.w), @intCast(box.h));
                surface.commit();
            }
        }
    }
}

var glyph_cache: Ttf.GlyphCache = undefined;

fn drawText(alloc: Allocator, buffer: *const Buffer, text: []const u8) !void {
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(ARGB, .black, .xywh(
            @intCast(@as(i32, @intCast(400)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(100)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

fn drawText2(alloc: Allocator, buffer: *const Buffer) !void {
    const text = "abcdefghijklmnopqrstuvwxyz";
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(ARGB, .black, .xywh(
            @intCast(@as(i32, @intCast(200)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(300)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

fn drawText3(alloc: Allocator, buffer: *const Buffer) !void {
    const text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(ARGB, .black, .xywh(
            @intCast(@as(i32, @intCast(100)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(700)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

fn drawText4(alloc: Allocator, buffer: *const Buffer) !void {
    var next_x: i32 = 0;
    var per_char: f16 = 0xff;
    const per_char_delta: f16 = 255.0 / (0x7f.0 - 0x21.0);
    for (0x21..0x7f) |g| {
        const glyph = try glyph_cache.get(alloc, @intCast(g));
        buffer.drawFont(ARGB, .black, .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(850)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .dark_gray, .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(875)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .gray, .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(900)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .light_gray, .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(925)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .white, .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(950)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .rgb(
            @intFromFloat(@round(per_char)),
            @intFromFloat(@round(per_char)),
            @intFromFloat(@round(per_char)),
        ), .xywh(
            @intCast(@as(i32, @intCast(10)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(975)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        std.debug.print("{}\n", .{per_char});
        per_char -= per_char_delta;
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

fn drawColors(size: usize, buffer: Buffer, colors: Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = @intCast(x * 0xff / size);
        const r_y: usize = @intCast(y * 0xff / size);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c = Buffer.ARGB.rgb(r, g, b);
        colors.draw(.xywh(x, y, 1, 1), &[1]u32{c.int()});
        const b2: u8 = 0xff - g;
        const c2 = Buffer.ARGB.rgb(r, g, b2);
        buffer.draw(.xywh(x, y, 1, 1), &[1]u32{@intFromEnum(c2)});
    };
}

const Ttf = charcoal.TrueType;
const ARGB = charcoal.Buffer.ARGB;

const std = @import("std");
const Allocator = std.mem.Allocator;
