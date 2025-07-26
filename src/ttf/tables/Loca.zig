slice: Slice,

const Loca = @This();

pub const Slice = union(enum) {
    u16: []const u16,
    u32: []const u32,
};

pub fn init(format: i16, data: []align(2) u8) Loca {
    return .{ .slice = switch (format) {
        0 => .{ .u16 = @alignCast(@ptrCast(data)) },
        1 => .{ .u32 = @alignCast(@ptrCast(data)) },
        else => @panic("these are the only two options, I promise!"),
    } };
}

pub const Offsets = struct { u32, u32 };

pub fn glyphOffsets(loca: Loca, idx: usize) ?Offsets {
    const start, const end = switch (loca.slice) {
        .u16 => |s| .{ @as(u32, byteSwap(s[idx])) * 2, @as(u32, byteSwap(s[idx + 1])) * 2 },
        .u32 => |l| .{ byteSwap(l[idx]), byteSwap(l[idx + 1]) },
    };

    return if (start != end) .{ start, end } else null;
}

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (comptime builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
