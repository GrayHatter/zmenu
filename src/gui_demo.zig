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
    const ttf = try Ttf.init(@alignCast(font));
    try drawText2(alloc, &buffer, ttf);
    try drawText3(alloc, &buffer, ttf);

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

    buffer.drawRectangleFill(Buffer.ARGB, .xywh(130, 810, 200, 50), .blue);
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(30, 800, 200, 50), .red);
    buffer.drawRectangleFillMix(Buffer.ARGB, .xywh(130, 810, 200, 50), .alpha(.blue, 0x88));
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(400, 800, 100, 50), .hex(0xffff00ff));

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

fn drawText(alloc: Allocator, buffer: *const Buffer, text: []const u8, ttf: Ttf) !void {
    var layout_helper = LayoutHelper.init(alloc, text, ttf, 512, 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    for (tl.glyphs) |g| {
        const glyph = ttf.glyphForChar(alloc, g.char) catch continue;

        const canvas, _ = try glyph.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = ttf.head.units_per_em });
        buffer.drawFont(Buffer.ARGB, .black, .xywh(
            @intCast(400 + g.pixel_x1),
            @intCast(100 - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
    }
}

fn drawText2(alloc: Allocator, buffer: *const Buffer, ttf: Ttf) !void {
    var layout_helper = LayoutHelper.init(alloc, "abcdefghijklmnopqrstuvwxyz", ttf, 512, 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    for (tl.glyphs) |g| {
        const glyph = ttf.glyphForChar(alloc, g.char) catch continue;

        const canvas, _ = try glyph.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
        buffer.drawFont(Buffer.ARGB, .black, .xywh(
            @intCast(200 + g.pixel_x1),
            @intCast(300 - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
    }
}

fn drawText3(alloc: Allocator, buffer: *const Buffer, ttf: Ttf) !void {
    var layout_helper = LayoutHelper.init(alloc, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", ttf, 512, 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    for (tl.glyphs) |g| {
        const glyph = ttf.glyphForChar(alloc, g.char) catch continue;

        const canvas, _ = try glyph.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
        buffer.drawFont(Buffer.ARGB, .black, .xywh(
            @intCast(100 + g.pixel_x1),
            @intCast(700 - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
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

const LayoutHelper = @import("LayoutHelper.zig");
const Ttf = @import("ttf.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
