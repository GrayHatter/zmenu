cmap_bytes: []u8,

const Cmap = @This();

pub const Index = packed struct {
    version: u16,
    num_subtables: u16,

    pub fn fromBytes(bytes: []const u8) Index {
        return .{
            .version = byteSwap(@as(*const u16, @alignCast(@ptrCast(bytes.ptr))).*),
            .num_subtables = byteSwap(@as(*const u16, @alignCast(@ptrCast(bytes[2..].ptr))).*),
        };
    }
};

pub const SubtableLookup = packed struct {
    platform_id: u16,
    platform_specific_id: u16,
    offset: u32,

    pub fn fromBytes(bytes: []align(2) const u8) SubtableLookup {
        return .{
            .platform_id = byteSwap(@as(*const u16, @ptrCast(bytes.ptr)).*),
            .platform_specific_id = byteSwap(@as(*const u16, @ptrCast(bytes[2..].ptr)).*),
            .offset = byteSwap(@as(*const u32, @alignCast(@ptrCast(bytes[4..].ptr))).*),
        };
    }

    pub fn isUnicodeBmp(self: SubtableLookup) bool {
        return (self.platform_id == 0 and self.platform_specific_id == 3) or // unicode + bmp
            (self.platform_id == 3 and self.platform_specific_id == 1) // windows + unicode ucs 2
        ;
    }
};

const Subtable = packed struct {
    platform_id: u16,
    platform_specific_id: u16,
    offset: u32,
};

pub const SubtableFormat4 = struct {
    format: u16,
    length: u16,
    language: u16,
    seg_count_x2: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
    end_code: []const u16,
    reserved_pad: u16,
    start_code: []const u16,
    id_delta: []const u16,
    id_range_offset: []const u16,
    glyph_indices: []const u16,

    pub fn getGlyphIndex(self: SubtableFormat4, c: u16) u16 {
        // This won't make sense if you don't read the spec...
        var i: usize = 0;
        while (i < self.end_code.len) {
            if (byteSwap(self.end_code[i]) >= c and byteSwap(self.start_code[i]) <= c) {
                break;
            }
            i += 1;
        }

        if (i >= self.end_code.len) return 0;

        const byte_offset_from_id_offset = byteSwap(self.id_range_offset[i]);
        if (byte_offset_from_id_offset == 0) {
            return byteSwap(self.id_delta[i]) +% c;
        } else {
            // We apply the pointer offset a little different than the spec
            // suggests. We made individual allocations when copying/byte
            // swapping the id_range_offset and glyph_indices out of the input
            // data. This means that we can't just do pointer addition
            //
            // Instead we look at the data as follows
            //
            // [ id range ] [glyph indices ]
            //     |--offs_bytes--|
            //     ^
            //     i
            //
            // To find the index into glyph indices, we just subtract i from
            // id_range.len, and subtract that from the offset
            const offs_from_loc = byte_offset_from_id_offset / 2 + (c - byteSwap(self.start_code[i]));
            const dist_to_end = self.id_range_offset.len - i;
            const glyph_index_index = offs_from_loc - dist_to_end;
            return byteSwap(self.glyph_indices[glyph_index_index]) +% byteSwap(self.id_delta[i]);
        }
    }
};

pub fn init(bytes: []u8) Cmap {
    return .{
        .cmap_bytes = bytes,
    };
}

pub fn index(cmap: Cmap) Index {
    return .fromBytes(cmap.cmap_bytes);
}

pub fn readSubtableLookup(self: Cmap, idx: usize) SubtableLookup {
    const subtable_size = @sizeOf(SubtableLookup);
    const start = @sizeOf(Index) + idx * subtable_size;

    return .fromBytes(@alignCast(@ptrCast(self.cmap_bytes[start..])));
}

pub fn readSubtable(cmap: Cmap) !Cmap.SubtableFormat4 {
    const idx = cmap.index();
    const unicode_table_offs = blk: {
        for (0..idx.num_subtables) |i| {
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

pub fn readSubtableFormat(self: Cmap, offset: usize) u16 {
    return byteSwap(@as(*u16, @alignCast(@ptrCast(self.cmap_bytes[offset..].ptr))).*);
}

pub fn readSubtableFormat4(self: Cmap, offset: usize) !SubtableFormat4 {
    const words: []u16 = @as([*]u16, @alignCast(@ptrCast(self.cmap_bytes[offset..].ptr)))[0 .. (self.cmap_bytes.len - offset) / 2];
    const format = byteSwap(words[0]);
    const length = byteSwap(words[1]);
    const language = byteSwap(words[2]);
    const seg_count_x2 = byteSwap(words[3]);
    const search_range = byteSwap(words[4]);
    const entry_selector = byteSwap(words[5]);
    const range_shift = byteSwap(words[6]);
    const count = seg_count_x2 / 2;
    var used: usize = 7;

    const end_code: []u16 = words[used..][0..count];
    used += count;
    const reserved_pad: u16 = words[used];
    used += 1;
    const start_code: []u16 = words[used..][0..count];
    used += count;
    const id_delta: []u16 = words[used..][0..count];
    used += count;
    const id_range_offset: []u16 = words[used..][0..count];
    used += count;
    const glyph_indices: []u16 = words[used..];

    return .{
        .format = format,
        .length = length,
        .language = language,
        .seg_count_x2 = seg_count_x2,
        .search_range = search_range,
        .entry_selector = entry_selector,
        .range_shift = range_shift,
        .end_code = end_code,
        .reserved_pad = reserved_pad,
        .start_code = start_code,
        .id_delta = id_delta,
        .id_range_offset = id_range_offset,
        .glyph_indices = glyph_indices,
    };
}

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
