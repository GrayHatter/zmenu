pub const Head = @import("tables/Head.zig");
pub const Maxp = @import("tables/Maxp.zig");
pub const Cmap = @import("tables/Cmap.zig");
pub const Hhea = @import("tables/Hhea.zig");
pub const Hmtx = @import("tables/Hmtx.zig");
pub const Loca = @import("tables/Loca.zig");

pub const Offsets = packed struct {
    scaler: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,

    pub const SIZE = 12;

    pub fn fromBytes(bytes: []align(2) const u8) Offsets {
        return .{
            .scaler = byteSwap(@as(*const u32, @alignCast(@ptrCast(bytes))).*),
            .num_tables = byteSwap(@as(*const u16, @ptrCast(bytes[4..])).*),
            .search_range = byteSwap(@as(*const u16, @ptrCast(bytes[6..])).*),
            .entry_selector = byteSwap(@as(*const u16, @ptrCast(bytes[8..])).*),
            .range_shift = byteSwap(@as(*const u16, @ptrCast(bytes[10..])).*),
        };
    }
};

pub const DirectoryEntry = extern struct {
    tag: [4]u8,
    check_sum: u32,
    offset: u32,
    length: u32,

    pub fn fromBigE(tde: DirectoryEntry) DirectoryEntry {
        return .{
            .tag = tde.tag,
            .check_sum = byteSwap(tde.check_sum),
            .offset = byteSwap(tde.offset),
            .length = byteSwap(tde.length),
        };
    }
};

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
