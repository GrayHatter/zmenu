frac: i16,
integer: i16,

pub const Fixed = @This();

pub fn fromBytes(bytes: []align(2) u8) Fixed {
    return .{
        .frac = byteSwap(@as(*i16, @ptrCast(bytes[0..])).*),
        .integer = byteSwap(@as(*i16, @ptrCast(bytes[2..])).*),
    };
}

const Packed = packed struct(u32) {
    frac: i16,
    integer: i16,
};

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (comptime builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
