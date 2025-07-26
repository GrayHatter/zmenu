head: Head,
maxp: Maxp,
cmap: Cmap,
loca: Loca,
glyf: Glyf,
hhea: Hhea,
hmtx: Hmtx,

cmap_subtable: Cmap.SubtableFormat4,

const Ttf = @This();

const tables = @import("ttf/tables.zig");

const Head = tables.Head;
const Maxp = tables.Maxp;
const Cmap = tables.Cmap;
const Hhea = tables.Hhea;
const Hmtx = tables.Hmtx;
const Loca = tables.Loca;
const Glyf = tables.Glyf;

pub const Glyph2 = @import("Glyph.zig");

const HeaderTag = enum {
    cmap,
    head,
    maxp,
    loca,
    glyf,
    hhea,
    hmtx,
    // not yet implemented
    post,
    prep,
    name,
    @"OS/2",
    gasp,
    BASE,
    GDEF,
    GPOS,
    GSUB,
    STAT,
};

pub fn init(font_data: []align(2) u8) !Ttf {
    var data: []align(2) u8 = font_data;
    const offset_table: tables.Offsets = .fromBytes(data);
    data = data[tables.Offsets.SIZE..];
    const table_entries: [*]tables.DirectoryEntry = @alignCast(@ptrCast(data));
    var head: ?Head = null;
    var maxp: ?Maxp = null;
    var cmap: ?Cmap = null;
    var glyf: ?Glyf = null;
    var loca: ?Loca = null;
    var hhea: ?Hhea = null;
    var hmtx: ?Hmtx = null;

    for (table_entries[0..offset_table.num_tables]) |entry_big| {
        const entry: tables.DirectoryEntry = .fromBigE(entry_big);
        //std.debug.print("header name {s}\n", .{entry.tag});
        const tag = std.meta.stringToEnum(HeaderTag, &entry.tag) orelse continue;

        switch (tag) {
            .head => head = .fromBytes(tableFromEntry(font_data, entry)),
            .hhea => hhea = .fromBytes(tableFromEntry(font_data, entry)),
            .loca => loca = .init(head.?.index_to_loc_format, tableFromEntry(font_data, entry)),
            .maxp => maxp = .fromBytes(tableFromEntry(font_data, entry)),
            .cmap => cmap = .init(tableFromEntry(font_data, entry)),
            .glyf => glyf = .init(tableFromEntry(font_data, entry)),
            .hmtx => hmtx = .init(tableFromEntry(font_data, entry)),
            // skip
            .post, .prep, .name, .@"OS/2", .gasp => {},
            .BASE, .GDEF, .GSUB, .GPOS, .STAT => {},
        }
    }

    const head_unwrapped = head orelse return error.NoHead;

    // Otherwise locs are the wrong size
    std.debug.assert(head.?.index_to_loc_format < 2);
    // Magic is easy to check
    std.debug.assert(head_unwrapped.magic_number == 0x5F0F3CF5);

    const subtable = try (cmap orelse return error.NoCMAP).readSubtable();

    return .{
        .maxp = maxp orelse return error.NoMaxp,
        .head = head_unwrapped,
        .loca = loca orelse return error.NoLoca,
        .cmap = cmap orelse return error.NoCmap,
        .glyf = glyf orelse return error.NoGlyf,
        .cmap_subtable = subtable,
        .hhea = hhea orelse return error.NoHhea,
        .hmtx = hmtx orelse return error.NoHmtx,
    };
}

fn tableFromEntry(font_data: []align(2) u8, entry: tables.DirectoryEntry) []align(2) u8 {
    return @alignCast(font_data[entry.offset .. entry.offset + entry.length]);
}

pub fn glyphHeaderForChar(ttf: Ttf, char: u16) ?Glyf.Header {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const start, _ = ttf.loca.offsetBounds(glyph_index) orelse return null;
    return .fromBytes(@alignCast(ttf.glyf.data[start..]));
}

pub fn glyphForChar(ttf: Ttf, alloc: Allocator, char: u16) !Glyph2 {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const start, const end = ttf.loca.offsetBounds(glyph_index) orelse return error.EmptyGlyph;

    return ttf.glyf.glyph(alloc, start, end);
}

pub fn metricsForChar(ttf: Ttf, char: u16) Hmtx.LongHorMetric {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    return ttf.hmtx.getMetrics(ttf.hhea.num_of_long_hor_metrics, glyph_index);
}

pub fn lineHeight(ttf: Ttf) i16 {
    return ttf.hhea.ascent - ttf.hhea.descent + ttf.hhea.line_gap;
}

pub fn lineHeightPx(ttf: Ttf, point_size: f32) i32 {
    const converter = FunitToPixelConverter.init(point_size, @floatFromInt(ttf.head.units_per_em));
    return converter.pixelFromFunit(lineHeight(ttf));
}

pub const FunitToPixelConverter = struct {
    scale: f32,

    pub fn init(font_size: f32, units_per_em: f32) FunitToPixelConverter {
        const dpi = 96; // Default DPI is 96
        const base_dpi = 72; // from ttf spec
        return .{
            .scale = font_size * dpi / (base_dpi * units_per_em),
        };
    }

    pub fn pixelBoundsForGlyph(self: FunitToPixelConverter, glyph_header: Glyf.Header) [2]u16 {
        const width_f: f32 = @floatFromInt(glyph_header.x_max - glyph_header.x_min);
        const height_f: f32 = @floatFromInt(glyph_header.y_max - glyph_header.y_min);

        return .{
            @intFromFloat(@round(width_f * self.scale)),
            @intFromFloat(@round(height_f * self.scale)),
        };
    }

    pub fn pixelFromFunit(self: FunitToPixelConverter, funit: i64) i32 {
        const size_f: f32 = @floatFromInt(funit);
        return @intFromFloat(@round(self.scale * size_f));
    }
};

pub const Scale = struct {
    scale: f32,

    pub fn initFont(font_size: f32, units_per_em: f32) Scale {
        const dpi = 96; // Default DPI is 96
        const base_dpi = 72; // from ttf spec
        return .{ .scale = font_size * dpi / (base_dpi * units_per_em) };
    }

    pub fn int(s: Scale, i: isize) isize {
        const f: f64 = @floatFromInt(i);
        return @intFromFloat(f * s.scale);
    }
};

test "render chars timed" {
    const config = @import("config");

    const debug_print_timing = config.timings;

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const embed = @embedFile("font.ttf");
    const font: []align(2) u8 = try alloc.alignedAlloc(u8, 2, embed.len);
    @memcpy(font, embed);
    defer alloc.free(font);
    const ttf = try Ttf.init(font);

    var timer = try std.time.Timer.start();

    for ("abcdefghijklmnopqrstuvwxyz") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = glyph;
    }
    for ("ABCDEFGHIJKLMNOPQRSTUVWXYZ") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = glyph;
    }
    if (debug_print_timing) std.debug.print("after load        {d: >8}\n", .{timer.lap()});

    for ("abcdefghijklmnopqrstuvwxyz") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = try glyph.render(alloc, ttf);
    }
    for ("ABCDEFGHIJKLMNOPQRSTUVWXYZ") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = try glyph.render(alloc, ttf);
    }
    if (debug_print_timing) std.debug.print("after render      {d: >8}\n", .{timer.lap()});

    for ("abcdefghijklmnopqrstuvwxyz") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = try glyph.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
    }
    for ("ABCDEFGHIJKLMNOPQRSTUVWXYZ") |char| {
        const glyph = try ttf.glyphForChar(alloc, char);
        _ = try glyph.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
    }
    if (debug_print_timing) std.debug.print("after render size {d: >8}\n", .{timer.lap()});
}

test "render most chars" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const embed = @embedFile("font.ttf");
    const font: []align(2) u8 = try alloc.alignedAlloc(u8, 2, embed.len);
    @memcpy(font, embed);
    defer alloc.free(font);
    const ttf = try Ttf.init(font);

    for (0x21..0x7f) |char| {
        const glyph = ttf.glyphForChar(alloc, @intCast(char)) catch |err| switch (err) {
            error.EmptyGlyph => {
                std.debug.print("Error: can't render {c} {}\n", .{ @as(u8, @intCast(char)), char });
                return err;
            },
            else => return err,
        };
        _ = try glyph.render(alloc, ttf);
    }
}

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const byteSwapAllFields = std.mem.byteSwapAllFields;
const bytesToValue = std.mem.bytesToValue;
