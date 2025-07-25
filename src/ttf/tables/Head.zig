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

const Head = @This();

pub fn fromBytes(bytes: []align(2) u8) Head {
    return .{
        .version = .fromBytes(bytes[0..]),
        .font_revision = .fromBytes(bytes[4..]),
        .check_sum_adjustment = byteSwap(@as(*u32, @alignCast(@ptrCast(bytes[8..]))).*),
        .magic_number = byteSwap(@as(*u32, @alignCast(@ptrCast(bytes[12..]))).*),
        .flags = byteSwap(@as(*u16, @ptrCast(bytes[16..])).*),
        .units_per_em = byteSwap(@as(*u16, @ptrCast(bytes[18..])).*),
        .created = byteSwap(@as(*align(2) i64, @ptrCast(bytes[20..])).*),
        .modified = byteSwap(@as(*align(2) i64, @ptrCast(bytes[28..])).*),
        .x_min = byteSwap(@as(*i16, @ptrCast(bytes[36..])).*),
        .y_min = byteSwap(@as(*i16, @ptrCast(bytes[38..])).*),
        .x_max = byteSwap(@as(*i16, @ptrCast(bytes[40..])).*),
        .y_max = byteSwap(@as(*i16, @ptrCast(bytes[42..])).*),
        .mac_style = byteSwap(@as(*u16, @ptrCast(bytes[44..])).*),
        .lowest_rec_ppem = byteSwap(@as(*u16, @ptrCast(bytes[46..])).*),
        .font_direction_hint = byteSwap(@as(*i16, @ptrCast(bytes[48..])).*),
        .index_to_loc_format = byteSwap(@as(*i16, @ptrCast(bytes[50..])).*),
        .glyph_data_format = byteSwap(@as(*i16, @ptrCast(bytes[52..])).*),
    };
}

const Fixed = @import("../Fixed.zig");

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (comptime builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
