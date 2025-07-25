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

const Maxp = @This();

pub fn fromBytes(bytes: []align(2) u8) Maxp {
    return .{
        .version = .fromBytes(bytes[0..]),
        .num_glyphs = byteSwap(@as(*u16, @ptrCast(bytes[4..])).*),
        .max_points = byteSwap(@as(*u16, @ptrCast(bytes[6..])).*),
        .max_contours = byteSwap(@as(*u16, @ptrCast(bytes[8..])).*),
        .max_component_points = byteSwap(@as(*u16, @ptrCast(bytes[10..])).*),
        .max_component_contours = byteSwap(@as(*u16, @ptrCast(bytes[12..])).*),
        .max_zones = byteSwap(@as(*u16, @ptrCast(bytes[14..])).*),
        .max_twilight_points = byteSwap(@as(*u16, @ptrCast(bytes[16..])).*),
        .max_storage = byteSwap(@as(*u16, @ptrCast(bytes[18..])).*),
        .max_function_defs = byteSwap(@as(*u16, @ptrCast(bytes[20..])).*),
        .max_instruction_defs = byteSwap(@as(*u16, @ptrCast(bytes[22..])).*),
        .maxStackElements = byteSwap(@as(*u16, @ptrCast(bytes[24..])).*),
        .maxSizeOfInstructions = byteSwap(@as(*u16, @ptrCast(bytes[26..])).*),
        .maxComponentElements = byteSwap(@as(*u16, @ptrCast(bytes[28..])).*),
        .maxComponentDepth = byteSwap(@as(*u16, @ptrCast(bytes[30..])).*),
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
