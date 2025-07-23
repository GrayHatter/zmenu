line_height: i16,
text: []const u8,
wrap_width_px: u31,
funit_converter: Ttf.FunitToPixelConverter,
glyphs: std.ArrayList(Text.GlyphLoc),

x_cursor: i64 = 0,
y_cursor: i64 = 0,
text_idx: usize = 0,
rollback_data: Rollback = .zero,
bounds: Box = .zero,
layout_state: State = .boundry,

const LayoutHelper = @This();

const State = enum {
    inside,
    boundry,
};

const Box = struct {
    min_x: i32,
    max_x: i32,
    min_y: i32,
    max_y: i32,

    pub const zero: Box = .{ .min_x = 0, .max_x = 0, .min_y = 0, .max_y = 0 };

    fn width(b: Box) i32 {
        return b.max_x - b.min_x;
    }

    fn merge(a: Box, b: Box) Box {
        return .{
            .min_x = @min(a.min_x, b.min_x),
            .max_x = @max(a.max_x, b.max_x),
            .min_y = @min(a.min_y, b.min_y),
            .max_y = @max(a.max_y, b.max_y),
        };
    }
};

pub const Text = struct {
    glyphs: []GlyphLoc,
    min_x: i32,
    max_x: i32,
    min_y: i32,
    max_y: i32,

    pub const empty = Text{ .glyphs = &.{}, .min_x = 0, .max_x = 0, .min_y = 0, .max_y = 0 };

    pub const GlyphLoc = struct {
        char: u8,
        pixel_x1: i32,
        pixel_x2: i32,
        pixel_y1: i32,
        pixel_y2: i32,
    };

    pub fn width(t: Text) u32 {
        return @intCast(t.max_x - t.min_x);
    }

    pub fn height(t: Text) u32 {
        return @intCast(t.max_y - t.min_y);
    }
};

const Rollback = struct {
    text_idx: usize = 0,
    glyphs_len: usize = 0,
    bounds: Box = .zero,
    start_x: i64 = 0,

    pub const zero: Rollback = .{ .text_idx = 0, .glyphs_len = 0, .bounds = .zero, .start_x = 0 };
};

pub fn init(alloc: Allocator, text: []const u8, ttf: Ttf, wrap_width_px: u31, font_size: f32) LayoutHelper {
    const funit_converter = Ttf.FunitToPixelConverter.init(font_size, @floatFromInt(ttf.head.units_per_em));
    const min_y = funit_converter.pixelFromFunit(ttf.hhea.descent);
    const max_y = funit_converter.pixelFromFunit(ttf.hhea.ascent);
    //const s: Ttf.Scale = .initFont(font_size, @floatFromInt(ttf.head.units_per_em));

    return .{
        .line_height = Ttf.lineHeight(ttf),
        .text = text,
        .wrap_width_px = wrap_width_px,
        .funit_converter = funit_converter,
        .bounds = .{
            .min_x = 0,
            .max_x = 0,
            .min_y = min_y,
            .max_y = max_y,
        },
        .glyphs = std.ArrayList(Text.GlyphLoc).init(alloc),
    };
}

pub fn step(lh: *LayoutHelper, ttf: Ttf) !bool {
    const c = lh.nextChar() orelse return false;
    lh.updateRollbackData(c);
    if (c == '\n') return lh.advanceLine();

    const metrics = ttf.metricsForChar(c);
    const bounds = lh.calcCharBounds(ttf, metrics.left_side_bearing, c) orelse {
        return lh.advanceNoGlyphChar(metrics.advance_width);
    };

    const new_bounds = lh.bounds.merge(bounds);
    if (new_bounds.width() >= lh.wrap_width_px) {
        return lh.doTextWrapping();
    }

    lh.x_cursor += metrics.advance_width;
    try lh.glyphs.append(.{
        .char = c,
        .pixel_x1 = bounds.min_x,
        .pixel_x2 = bounds.max_x,
        .pixel_y1 = bounds.min_y,
        .pixel_y2 = bounds.max_y,
    });
    lh.bounds = new_bounds;
    return true;
}

fn nextChar(lh: *LayoutHelper) ?u8 {
    if (lh.text_idx >= lh.text.len) return null;
    defer lh.text_idx += 1;
    return lh.text[lh.text_idx];
}

fn advanceLine(lh: *LayoutHelper) bool {
    lh.y_cursor -= lh.line_height;
    lh.x_cursor = 0;
    lh.bounds.min_y -= lh.funit_converter.pixelFromFunit(lh.line_height);
    // If we've moved up a line, rollback data needs to put us back at the
    // start of the line, not wherever we were when the word started
    lh.rollback_data.start_x = 0;
    return true;
}

fn updateRollbackData(lh: *LayoutHelper, c: u8) void {
    if (std.ascii.isWhitespace(c)) {
        lh.layout_state = .boundry;
        return;
    } else if (lh.layout_state == .inside) {
        return;
    }

    // Now guaranteed to be in a word without layout state between word
    lh.layout_state = .inside;
    lh.rollback_data.text_idx = lh.text_idx - 1;
    lh.rollback_data.glyphs_len = lh.glyphs.items.len;
    lh.rollback_data.bounds = lh.bounds;
    lh.rollback_data.start_x = lh.x_cursor;
}

fn advanceNoGlyphChar(lh: *LayoutHelper, advance_width: u16) bool {
    lh.x_cursor += advance_width;
    lh.bounds.max_x += lh.funit_converter.pixelFromFunit(advance_width);
    // -1 to ensure that we stay BELOW the wrap width, or else future
    // checks will get confused about why the bounding box is >= the
    // wrap width
    lh.bounds.max_x = @min(lh.wrap_width_px - 1, lh.bounds.max_x);
    return true;
}

fn doTextWrapping(lh: *LayoutHelper) bool {
    const word_at_line_start = lh.rollback_data.start_x == 0;
    if (word_at_line_start) {
        // In this case the word ithelper is longer than the wrap width. We
        // don't have a choice but to split the word up. Move back a
        // character since the character we just laid out is past the end
        // of the line and move to the next line
        lh.text_idx -= 1;
    } else lh.rollback();

    return lh.advanceLine();
}

fn calcCharBounds(lh: *LayoutHelper, ttf: Ttf, left_side_bearing: i16, c: u8) ?Box {
    const header = ttf.glyphHeaderForChar(c) orelse return null;

    const x1 = lh.x_cursor + left_side_bearing;
    const x2 = x1 + header.x_max - header.x_min;

    const y1 = lh.y_cursor + header.y_min;
    const y2 = y1 + header.y_max - header.y_min;

    const x1_px = lh.funit_converter.pixelFromFunit(x1);
    const y1_px = lh.funit_converter.pixelFromFunit(y1);
    // Why not just use x2 or header.y_max? We want to make sure no matter
    // how much the cursor has advanced in funits, we always render the
    // glyph aligned to the same number of pixels.
    const x2_px = x1_px + lh.funit_converter.pixelFromFunit(x2 - x1);
    const y2_px = y1_px + lh.funit_converter.pixelFromFunit(y2 - y1);

    return .{
        .min_x = x1_px,
        .max_x = x2_px,
        .min_y = y1_px,
        .max_y = y2_px,
    };
}

fn rollback(lh: *LayoutHelper) void {
    lh.text_idx = lh.rollback_data.text_idx;
    lh.glyphs.resize(lh.rollback_data.glyphs_len) catch unreachable;
    lh.bounds = lh.rollback_data.bounds;
    lh.x_cursor = lh.rollback_data.start_x;
}

test "layoutHelper" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const embed = @embedFile("font.ttf");
    const font: []align(2) u8 = try alloc.alignedAlloc(u8, 2, embed.len);
    @memcpy(font, embed);
    defer alloc.free(font);
    const ttf = try Ttf.init(alloc, font);
    const text = "this is some really long text";
    var lh: LayoutHelper = .init(alloc, text, ttf, 100, 14);
    while (try lh.step(ttf)) {}
    errdefer lh.glyphs.deinit();

    const tl: LayoutHelper.Text = .{
        .glyphs = try lh.glyphs.toOwnedSlice(),
        .min_x = lh.bounds.min_x,
        .max_x = lh.bounds.max_x,
        .min_y = lh.bounds.min_y,
        .max_y = lh.bounds.max_y,
    };

    try std.testing.expectEqual(@as(isize, 0), tl.min_x);
    try std.testing.expectEqual(@as(isize, 89), tl.max_x);
    try std.testing.expectEqual(@as(isize, -98), tl.min_y);
    try std.testing.expectEqual(@as(isize, 18), tl.max_y);
    try std.testing.expectEqual(@as(u8, 116), tl.glyphs[0].char);
    try std.testing.expectEqual(@as(isize, 1), tl.glyphs[0].pixel_x1);
    try std.testing.expectEqual(@as(isize, 10), tl.glyphs[0].pixel_x2);
    try std.testing.expectEqual(@as(isize, 0), tl.glyphs[0].pixel_y1);
    try std.testing.expectEqual(@as(isize, 12), tl.glyphs[0].pixel_y2);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ttf = @import("ttf.zig");
