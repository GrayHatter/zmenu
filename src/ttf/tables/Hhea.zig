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

const Hhea = @This();

pub fn fromBytes(bytes: []align(2) u8) Hhea {
    return .{
        .version = .fromBytes(bytes[0..]),
        .ascent = byteSwap(@as(*i16, @ptrCast(bytes[4..])).*),
        .descent = byteSwap(@as(*i16, @ptrCast(bytes[6..])).*),
        .line_gap = byteSwap(@as(*i16, @ptrCast(bytes[8..])).*),
        .advance_width_max = byteSwap(@as(*u16, @ptrCast(bytes[10..])).*),
        .min_left_side_bearing = byteSwap(@as(*i16, @ptrCast(bytes[12..])).*),
        .min_right_side_bearing = byteSwap(@as(*i16, @ptrCast(bytes[14..])).*),
        .x_max_extent = byteSwap(@as(*i16, @ptrCast(bytes[16..])).*),
        .caret_slope_rise = byteSwap(@as(*i16, @ptrCast(bytes[18..])).*),
        .caret_slope_run = byteSwap(@as(*i16, @ptrCast(bytes[20..])).*),
        .caret_offset = byteSwap(@as(*i16, @ptrCast(bytes[22..])).*),
        .reserved1 = byteSwap(@as(*i16, @ptrCast(bytes[24..])).*),
        .reserved2 = byteSwap(@as(*i16, @ptrCast(bytes[26..])).*),
        .reserved3 = byteSwap(@as(*i16, @ptrCast(bytes[28..])).*),
        .reserved4 = byteSwap(@as(*i16, @ptrCast(bytes[30..])).*),
        .metric_data_format = byteSwap(@as(*i16, @ptrCast(bytes[32..])).*),
        .num_of_long_hor_metrics = byteSwap(@as(*u16, @ptrCast(bytes[34..])).*),
    };
}

const Fixed = @import("../Fixed.zig");
pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
