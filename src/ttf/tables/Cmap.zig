cmap_bytes: []const u8,

const Cmap = @This();

const Index = packed struct {
    version: u16,
    num_subtables: u16,
};

pub const SubtableLookup = packed struct {
    platform_id: u16,
    platform_specific_id: u16,
    offset: u32,

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
            if (self.end_code[i] >= c and self.start_code[i] <= c) {
                break;
            }
            i += 1;
        }

        if (i >= self.end_code.len) return 0;

        const byte_offset_from_id_offset = self.id_range_offset[i];
        if (byte_offset_from_id_offset == 0) {
            return self.id_delta[i] +% c;
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
            const offs_from_loc = byte_offset_from_id_offset / 2 + (c - self.start_code[i]);
            const dist_to_end = self.id_range_offset.len - i;
            const glyph_index_index = offs_from_loc - dist_to_end;
            return self.glyph_indices[glyph_index_index] +% self.id_delta[i];
        }
    }
};

pub fn readIndex(self: Cmap) Index {
    return fixEndianness(std.mem.bytesToValue(Index, self.cmap_bytes[0 .. @bitSizeOf(Index) / 8]));
}

pub fn readSubtableLookup(self: Cmap, idx: usize) SubtableLookup {
    const subtable_size = @bitSizeOf(SubtableLookup) / 8;
    const start = @bitSizeOf(Index) / 8 + idx * subtable_size;
    const end = start + subtable_size;

    return fixEndianness(std.mem.bytesToValue(SubtableLookup, self.cmap_bytes[start..end]));
}

pub fn readSubtableFormat(self: Cmap, offset: usize) u16 {
    return fixEndianness(std.mem.bytesToValue(u16, self.cmap_bytes[offset .. offset + 2]));
}

pub fn readSubtableFormat4(self: Cmap, alloc: Allocator, offset: usize) !SubtableFormat4 {
    var runtime_parser = RuntimeParser{ .data = self.cmap_bytes[offset..] };
    const format = runtime_parser.readVal(u16);
    const length = runtime_parser.readVal(u16);
    const language = runtime_parser.readVal(u16);
    const seg_count_x2 = runtime_parser.readVal(u16);
    const search_range = runtime_parser.readVal(u16);
    const entry_selector = runtime_parser.readVal(u16);
    const range_shift = runtime_parser.readVal(u16);

    const end_code: []const u16 = try runtime_parser.readArray(u16, alloc, seg_count_x2 / 2);
    const reserved_pad = runtime_parser.readVal(u16);
    const start_code: []const u16 = try runtime_parser.readArray(u16, alloc, seg_count_x2 / 2);
    const id_delta: []const u16 = try runtime_parser.readArray(u16, alloc, seg_count_x2 / 2);
    const id_range_offset: []const u16 = try runtime_parser.readArray(u16, alloc, seg_count_x2 / 2);
    const glyph_indices: []const u16 = try runtime_parser.readArray(u16, alloc, (runtime_parser.data.len - runtime_parser.idx) / 2);

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

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
