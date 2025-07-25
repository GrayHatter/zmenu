hmtx_bytes: []align(2) u8,

const Hmtx = @This();

pub const LongHorMetric = packed struct {
    advance_width: u16,
    left_side_bearing: i16,

    pub fn fromBytes(bytes: []align(2) u8) LongHorMetric {
        return .{
            .advance_width = byteSwap(@as(*u16, @ptrCast(bytes[0..])).*),
            .left_side_bearing = byteSwap(@as(*i16, @ptrCast(bytes[2..])).*),
        };
    }
};

pub fn init(bytes: []align(2) u8) Hmtx {
    return .{ .hmtx_bytes = bytes };
}

pub fn getMetrics(hmtx: Hmtx, num_hor_metrics: usize, glyph_index: usize) LongHorMetric {
    if (glyph_index < num_hor_metrics) {
        return hmtx.loadHorMetric(glyph_index);
    } else {
        const last = hmtx.loadHorMetric(num_hor_metrics - 1);
        const lsb_index = glyph_index - num_hor_metrics;
        const lsb_offs = num_hor_metrics * @bitSizeOf(LongHorMetric) / 8 + lsb_index * 2;
        const lsb: i16 = byteSwap(@as(*i16, @alignCast(@ptrCast(hmtx.hmtx_bytes[lsb_offs..]))).*);
        return .{
            .advance_width = last.advance_width,
            .left_side_bearing = lsb,
        };
    }
}

fn loadHorMetric(self: Hmtx, idx: usize) LongHorMetric {
    const offs = idx * @bitSizeOf(LongHorMetric) / 8;
    return .fromBytes(@alignCast(self.hmtx_bytes[offs..]));
}

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}
