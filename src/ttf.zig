head: Head,
maxp: Maxp.Table,
cmap: Cmap,
loca: LocaSlice,
glyf: Glyph.Table,
hhea: HheaTable,
hmtx: HmtxTable,

cmap_subtable: Cmap.SubtableFormat4,

const Ttf = @This();

const Head = @import("ttf/tables/Head.zig");
const HeadTable = Head;
const Maxp = @import("ttf/tables/Maxp.zig");
const Cmap = @import("ttf/tables/Cmap.zig");
const CmapTable = Cmap;
const Hhea = @import("ttf/tables/Hhea.zig");
const HheaTable = Hhea.Table;

pub const LocaSlice = union(enum) {
    u16: []const u16,
    u32: []const u32,
};

pub const Glyph = @import("Glyph.zig");

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

pub const HmtxTable = struct {
    hmtx_bytes: []const u8,

    pub const LongHorMetric = packed struct {
        advance_width: u16,
        left_side_bearing: i16,
    };

    pub fn init(bytes: []const u8) HmtxTable {
        return .{ .hmtx_bytes = bytes };
    }

    pub fn getMetrics(self: HmtxTable, num_hor_metrics: usize, glyph_index: usize) LongHorMetric {
        if (glyph_index < num_hor_metrics) {
            return self.loadHorMetric(glyph_index);
        } else {
            const last = self.loadHorMetric(num_hor_metrics - 1);
            const lsb_index = glyph_index - num_hor_metrics;
            const lsb_offs = num_hor_metrics * @bitSizeOf(LongHorMetric) / 8 + lsb_index * 2;
            const lsb = fixEndianness(std.mem.bytesToValue(i16, self.hmtx_bytes[lsb_offs..]));
            return .{
                .advance_width = last.advance_width,
                .left_side_bearing = lsb,
            };
        }
    }

    fn loadHorMetric(self: HmtxTable, idx: usize) LongHorMetric {
        const offs = idx * @bitSizeOf(LongHorMetric) / 8;
        return fixEndianness(std.mem.bytesToValue(LongHorMetric, self.hmtx_bytes[offs..]));
    }
};

const OffsetTable = packed struct {
    scaler: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,

    pub const SIZE = 12;

    pub fn fromBytes(bytes: []align(2) const u8) OffsetTable {
        return .{
            .scaler = byteSwap(@as(*const u32, @alignCast(@ptrCast(bytes))).*),
            .num_tables = byteSwap(@as(*const u16, @ptrCast(bytes[4..])).*),
            .search_range = byteSwap(@as(*const u16, @ptrCast(bytes[6..])).*),
            .entry_selector = byteSwap(@as(*const u16, @ptrCast(bytes[8..])).*),
            .range_shift = byteSwap(@as(*const u16, @ptrCast(bytes[10..])).*),
        };
    }
};

const TableDirectoryEntry = extern struct {
    tag: [4]u8,
    check_sum: u32,
    offset: u32,
    length: u32,
};

pub fn init(font_data: []align(2) u8) !Ttf {
    var data: []align(2) u8 = font_data;
    const offset_table: OffsetTable = .fromBytes(data);
    data = data[OffsetTable.SIZE..];
    //const table_directory_start = @bitSizeOf(OffsetTable) / 8;
    //const table_directory_end = table_directory_start + @bitSizeOf(TableDirectoryEntry) * offset_table.num_tables / 8;
    const table_entries: [*]TableDirectoryEntry = @alignCast(@ptrCast(data));
    var head: ?HeadTable = null;
    var maxp: ?Maxp.Table = null;
    var cmap: ?CmapTable = null;
    var glyf: ?Glyph.Table = null;
    var loca: ?LocaSlice = null;
    var hhea: ?HheaTable = null;
    var hmtx: ?HmtxTable = null;

    for (table_entries[0..offset_table.num_tables]) |entry_big| {
        const entry = fixEndianness(entry_big);
        //std.debug.print("header name {s}\n", .{entry.tag});
        const tag = std.meta.stringToEnum(HeaderTag, &entry.tag) orelse continue;

        switch (tag) {
            .head => head = .fromBytes(tableFromEntry(font_data, entry)),
            .hhea => hhea = fixEndianness(std.mem.bytesToValue(HheaTable, tableFromEntry(font_data, entry))),
            .loca => {
                loca = switch (head.?.index_to_loc_format) {
                    0 => .{ .u16 = @alignCast(std.mem.bytesAsSlice(u16, tableFromEntry(font_data, entry))) },
                    1 => .{ .u32 = @alignCast(std.mem.bytesAsSlice(u32, tableFromEntry(font_data, entry))) },
                    else => @panic("these are the only two options, I promise!"),
                };
            },
            .maxp => maxp = fixEndianness(std.mem.bytesToValue(Maxp.Table, tableFromEntry(font_data, entry))),
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

    const subtable = try readSubtable(cmap orelse return error.NoCMAP);

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

fn tableFromEntry(font_data: []align(2) u8, entry: TableDirectoryEntry) []align(2) u8 {
    return @alignCast(font_data[entry.offset .. entry.offset + entry.length]);
}

fn readSubtable(cmap: CmapTable) !CmapTable.SubtableFormat4 {
    const index = cmap.index();
    const unicode_table_offs = blk: {
        for (0..index.num_subtables) |i| {
            const subtable = cmap.readSubtableLookup(i);
            if (subtable.isUnicodeBmp()) {
                break :blk subtable.offset;
            }
        }
        return error.NoUnicodeBmpTables;
    };

    const format = cmap.readSubtableFormat(unicode_table_offs);
    if (format != 4) {
        std.log.err("Can only handle unicode format 4", .{});
        return error.Unimplemented;
    }

    return try cmap.readSubtableFormat4(unicode_table_offs);
}

pub fn offsetFromIndex(ttf: Ttf, idx: usize) ?struct { u32, u32 } {
    const start, const end = switch (ttf.loca) {
        .u16 => |s| .{ @as(u32, byteSwap(s[idx])) * 2, @as(u32, byteSwap(s[idx + 1])) * 2 },
        .u32 => |l| .{ byteSwap(l[idx]), byteSwap(l[idx + 1]) },
    };

    if (start == end) return null;
    return .{ start, end };
}

pub fn glyphHeaderForChar(ttf: Ttf, char: u16) ?Glyph.Header {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const start, _ = ttf.offsetFromIndex(glyph_index) orelse return null;
    return ttf.glyf.glyphHeader(start);
}

pub fn glyphForChar(ttf: Ttf, alloc: Allocator, char: u16) !Glyph {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const start, const end = ttf.offsetFromIndex(glyph_index) orelse return error.EmptyGlyph;

    return ttf.glyf.glyph(alloc, start, end);
}

pub fn metricsForChar(ttf: Ttf, char: u16) HmtxTable.LongHorMetric {
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

    pub fn pixelBoundsForGlyph(self: FunitToPixelConverter, glyph_header: Glyph.Header) [2]u16 {
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

fn pointsBounds(points: []const Glyph.FPoint) Glyph.BBox {
    var ret = Glyph.BBox.invalid;

    for (points) |point| {
        ret.min_x = @min(point[0], ret.min_x);
        ret.min_y = @min(point[1], ret.min_x);
        ret.max_x = @max(point[0], ret.max_x);
        ret.max_y = @max(point[1], ret.max_x);
    }

    return ret;
}

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

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}

pub fn fixEndianness(val: anytype) @TypeOf(val) {
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }

    switch (@typeInfo(@TypeOf(val))) {
        .@"struct" => {
            var ret = val;
            std.mem.byteSwapAllFields(@TypeOf(val), &ret);
            return ret;
        },
        .int => {
            return std.mem.bigToNative(@TypeOf(val), val);
        },
        inline else => @compileError("Cannot fix endianness for " ++ @typeName(@TypeOf(val))),
    }
}

test "render all chars" {
    const debug_print_timing = false;

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

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const byteSwapAllFields = std.mem.byteSwapAllFields;
const bytesToValue = std.mem.bytesToValue;
