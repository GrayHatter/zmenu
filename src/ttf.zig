head: HeadTable,
maxp: MaxpTable,
cmap: Cmap,
loca: LocaSlice,
glyf: Glyph.Table,
hhea: HheaTable,
hmtx: HmtxTable,

cmap_subtable: Cmap.SubtableFormat4,

const Ttf = @This();

const HeadTable = packed struct {
    version: Fixed,
    font_revision: Fixed,
    check_sum_adjustment: u32,
    magic_number: u32,
    flags: u16,
    units_per_em: u16,
    created: i64,
    modified: i64,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: u16,
    lowest_rec_ppem: u16,
    font_direction_hint: i16,
    index_to_loc_format: i16,
    glyph_data_format: i16,
};

const MaxpTable = packed struct {
    version: Fixed,
    num_glyphs: u16,
    max_points: u16,
    max_contours: u16,
    max_component_points: u16,
    max_component_contours: u16,
    max_zones: u16,
    max_twilight_points: u16,
    max_storage: u16,
    max_function_defs: u16,
    max_instruction_defs: u16,
    maxStackElements: u16,
    maxSizeOfInstructions: u16,
    maxComponentElements: u16,
    maxComponentDepth: u16,
};

const Cmap = @import("ttf/Cmap.zig");
const CmapTable = Cmap;

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
};
const HheaTable = packed struct {
    version: Fixed,
    ascent: i16,
    descent: i16,
    line_gap: i16,
    advance_width_max: u16,
    min_left_side_bearing: i16,
    min_right_side_bearing: i16,
    x_max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    reserved1: i16,
    reserved2: i16,
    reserved3: i16,
    reserved4: i16,
    metric_data_format: i16,
    num_of_long_hor_metrics: u16,
};

pub const HmtxTable = struct {
    hmtx_bytes: []const u8,

    pub const LongHorMetric = packed struct {
        advance_width: u16,
        left_side_bearing: i16,
    };

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
};

const TableDirectoryEntry = extern struct {
    tag: [4]u8,
    check_sum: u32,
    offset: u32,
    length: u32,
};

const Fixed = packed struct(u32) {
    frac: i16,
    integer: i16,
};

pub fn init(alloc: Allocator, font_data: []u8) !Ttf {
    const offset_table = fixEndianness(std.mem.bytesToValue(OffsetTable, font_data[0 .. @bitSizeOf(OffsetTable) / 8]));
    const table_directory_start = @bitSizeOf(OffsetTable) / 8;
    const table_directory_end = table_directory_start + @bitSizeOf(TableDirectoryEntry) * offset_table.num_tables / 8;
    const table_entries = std.mem.bytesAsSlice(TableDirectoryEntry, font_data[table_directory_start..table_directory_end]);
    var head: ?HeadTable = null;
    var maxp: ?MaxpTable = null;
    var cmap: ?CmapTable = null;
    var glyf: ?Glyph.Table = null;
    var loca: ?LocaSlice = null;
    var hhea: ?HheaTable = null;
    var hmtx: ?HmtxTable = null;

    //    for (table_entries) |entry_big| {
    //        const entry = fixEndianness(entry_big);
    //        const tag = std.meta.stringToEnum(HeaderTag, &entry.tag) orelse continue;
    //
    //        const tbl: []align(2) const u8 = @alignCast(tableFromEntry(font_data, entry));
    //        switch (tag) {
    //            .head => {
    //                head = bytesToValue(HeadTable, tbl);
    //                byteSwapAllFields(HeadTable, &head.?);
    //            },
    //            .hhea => {
    //                hhea = bytesToValue(HheaTable, tbl);
    //                byteSwapAllFields(HheaTable, &hhea.?);
    //            },
    //            .loca => {
    //                loca = switch (head.?.index_to_loc_format) {
    //                    0 => .{ .u16 = try fixSliceEndianness(u16, alloc, std.mem.bytesAsSlice(u16, tbl)) },
    //                    1 => .{ .u32 = try fixSliceEndianness(u32, alloc, std.mem.bytesAsSlice(u32, tbl)) },
    //                    else => @panic("these are the only two options, I promise!"),
    //                };
    //            },
    //            .maxp => {
    //                maxp = fixEndianness(std.mem.bytesToValue(MaxpTable, tbl));
    //            },
    //            .cmap => {
    //                cmap = CmapTable{ .cmap_bytes = tbl };
    //            },
    //            .glyf => {
    //                glyf = GlyphTable{ .data = tbl };
    //            },
    //            .hmtx => {
    //                hmtx = HmtxTable{ .hmtx_bytes = tbl };
    //            },
    //        }
    //    }

    for (table_entries) |entry_big| {
        const entry = fixEndianness(entry_big);
        const tag = std.meta.stringToEnum(HeaderTag, &entry.tag) orelse continue;

        switch (tag) {
            .head => head = fixEndianness(std.mem.bytesToValue(HeadTable, tableFromEntry(font_data, entry))),
            .hhea => hhea = fixEndianness(std.mem.bytesToValue(HheaTable, tableFromEntry(font_data, entry))),
            .loca => {
                loca = switch (head.?.index_to_loc_format) {
                    0 => .{ .u16 = try fixSliceEndianness(u16, alloc, std.mem.bytesAsSlice(u16, tableFromEntry(font_data, entry))) },
                    1 => .{ .u32 = try fixSliceEndianness(u32, alloc, std.mem.bytesAsSlice(u32, tableFromEntry(font_data, entry))) },
                    else => @panic("these are the only two options, I promise!"),
                };
            },
            .maxp => maxp = fixEndianness(std.mem.bytesToValue(MaxpTable, tableFromEntry(font_data, entry))),
            .cmap => cmap = CmapTable{ .cmap_bytes = tableFromEntry(font_data, entry) },
            .glyf => glyf = Glyph.Table{ .data = tableFromEntry(font_data, entry) },
            .hmtx => hmtx = HmtxTable{ .hmtx_bytes = tableFromEntry(font_data, entry) },
        }
    }

    const head_unwrapped = head orelse return error.NoHead;

    // Otherwise locs are the wrong size
    std.debug.assert(head.?.index_to_loc_format < 2);
    // Magic is easy to check
    std.debug.assert(head_unwrapped.magic_number == 0x5F0F3CF5);

    const subtable = try readSubtable(alloc, cmap orelse unreachable);

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

fn tableFromEntry(font_data: []const u8, entry: TableDirectoryEntry) []const u8 {
    return font_data[entry.offset .. entry.offset + entry.length];
}

pub const RuntimeParser = struct {
    data: []const u8,
    idx: usize = 0,

    pub fn readVal(self: *RuntimeParser, comptime T: type) T {
        const size = @bitSizeOf(T) / 8;
        defer self.idx += size;
        return fixEndianness(std.mem.bytesToValue(T, self.data[self.idx .. self.idx + size]));
    }

    pub fn readArray(self: *RuntimeParser, comptime T: type, alloc: Allocator, len: usize) ![]T {
        const size = @bitSizeOf(T) / 8 * len;
        defer self.idx += size;
        return fixSliceEndianness(T, alloc, std.mem.bytesAsSlice(T, self.data[self.idx .. self.idx + size]));
    }
};
fn readSubtable(alloc: Allocator, cmap: CmapTable) !CmapTable.SubtableFormat4 {
    const index = cmap.readIndex();
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

    return try cmap.readSubtableFormat4(alloc, unicode_table_offs);
}

pub fn glyphHeaderForChar(ttf: Ttf, char: u16) ?Glyph.Header {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const glyf_start, const glyf_end = switch (ttf.loca) {
        .u16 => |s| .{ @as(u32, s[glyph_index]) * 2, @as(u32, s[glyph_index + 1]) * 2 },
        .u32 => |l| .{ l[glyph_index], l[glyph_index + 1] },
    };

    if (glyf_start == glyf_end) return null;

    return ttf.glyf.glyphHeader(glyf_start);
}

pub fn glyphForChar(ttf: Ttf, alloc: Allocator, char: u16) !Glyph.Simple {
    const glyph_index = ttf.cmap_subtable.getGlyphIndex(char);
    const glyf_start, const glyf_end = switch (ttf.loca) {
        .u16 => |s| .{ @as(u32, s[glyph_index]) * 2, @as(u32, s[glyph_index + 1]) * 2 },
        .u32 => |l| .{ l[glyph_index], l[glyph_index + 1] },
    };

    if (glyf_start == glyf_end) return error.EmptyGlyph;

    const glyph_header = ttf.glyf.glyphHeader(glyf_start);

    if (glyph_header.number_of_contours < 0) {
        if (false) try ttf.glyf.compound(alloc, glyf_start, glyf_end);
        return error.CompoundGlyphNotImplemented;
    }
    return try ttf.glyf.simple(alloc, glyf_start, glyf_end);
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

pub fn fixSliceEndianness(comptime T: type, alloc: Allocator, slice: []align(1) const T) ![]T {
    const duped = try alloc.alloc(T, slice.len);
    for (0..slice.len) |i| {
        duped[i] = fixEndianness(slice[i]);
    }
    return duped;
}

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const byteSwapAllFields = std.mem.byteSwapAllFields;
const bytesToValue = std.mem.bytesToValue;
