data: []align(2) const u8,

const Glyf = @This();

pub const Header = packed struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,

    pub fn fromBytes(bytes: []align(2) const u8) Header {
        return .{
            .number_of_contours = byteSwap(@as(*const i16, @ptrCast(bytes[0..])).*),
            .x_min = byteSwap(@as(*const i16, @ptrCast(bytes[2..])).*),
            .y_min = byteSwap(@as(*const i16, @ptrCast(bytes[4..])).*),
            .x_max = byteSwap(@as(*const i16, @ptrCast(bytes[6..])).*),
            .y_max = byteSwap(@as(*const i16, @ptrCast(bytes[8..])).*),
        };
    }
};

pub const Simple = struct {
    end_pts_of_contours: []u16,
    instruction_length: u16,
    //instructions: []u8,
    contours: []Contour,
    num_contours: usize,

    fl_ptr: []const u8,
    xc_ptr: []const u8,
    yc_ptr: []const u8,

    pub const Contour = struct {
        flag: Flags,
        x_coord: i16,
        y_coord: i16,
    };

    pub const Flags = packed struct(u8) {
        on_curve_point: bool,
        x_short_vector: bool,
        y_short_vector: bool,
        repeat_flag: bool,
        x_is_same_or_positive_x_short_vector: bool,
        y_is_same_or_positive_y_short_vector: bool,
        overlap_simple: bool,
        reserved: bool,

        pub const Variant = enum {
            short_pos,
            short_neg,
            long,
            repeat,
        };

        pub fn variant(f: Flags, comptime xy: enum { x, y }) Variant {
            return switch (comptime xy) {
                .x => switch (f.x_short_vector) {
                    true => switch (f.x_is_same_or_positive_x_short_vector) {
                        true => .short_pos,
                        false => .short_neg,
                    },
                    false => switch (f.x_is_same_or_positive_x_short_vector) {
                        true => .repeat,
                        false => .long,
                    },
                },
                .y => switch (f.y_short_vector) {
                    true => switch (f.y_is_same_or_positive_y_short_vector) {
                        true => .short_pos,
                        false => .short_neg,
                    },
                    false => switch (f.y_is_same_or_positive_y_short_vector) {
                        true => .repeat,
                        false => .long,
                    },
                },
            };
        }
    };

    pub fn getFlag(s: Simple, index: usize) Simple.Flags {
        const real = s.contours[index].flag;
        var pos: usize = 0;
        var idx: usize = 0;
        var flag: Simple.Flags = @bitCast(s.fl_ptr[pos]);
        while (idx <= index) {
            flag = @bitCast(s.fl_ptr[pos]);
            if (idx == index) break;
            idx +|= 1;
            pos += 1;
            if (flag.repeat_flag) {
                const repeat = s.fl_ptr[pos];
                pos += 1;
                if (idx + repeat <= index) {
                    idx += repeat;
                } else {
                    break;
                }
            }
        }
        std.debug.assert(real == flag);
        return flag;
    }

    pub fn getX(s: Simple, index: usize) i16 {
        const real = s.contours[index].x_coord;
        var idx: usize = 0;
        var flag: Simple.Flags = @bitCast(s.fl_ptr[0]);
        var x_offset: usize = 0;
        while (idx <= index) {
            flag = s.getFlag(idx); //@bitCast(s.fl_ptr[pos]);
            if (idx == index) break;
            idx +|= 1;
            const f_offset = switch (flag.variant(.x)) {
                .short_neg, .short_pos => 1,
                .long => 2,
                .repeat => @as(usize, 0),
            };
            x_offset += f_offset;
        }

        const searched: i16 = switch (flag.variant(.x)) {
            .short_pos => s.xc_ptr[x_offset],
            .short_neg => -@as(i16, s.xc_ptr[x_offset]),
            .long => byteSwap(@as(*align(1) const i16, @alignCast(@ptrCast(s.xc_ptr[x_offset..].ptr))).*),
            .repeat => @as(i16, 0),
        };

        std.debug.assert(searched == real);
        return searched;
    }

    pub fn getY(s: Simple, index: usize) i16 {
        const real = s.contours[index].y_coord;
        var idx: usize = 0;
        var flag: Simple.Flags = s.getFlag(0);
        var y_offset: usize = 0;
        while (idx <= index) {
            flag = s.getFlag(idx);
            if (idx == index) break;
            idx +|= 1;
            const f_offset = switch (flag.variant(.y)) {
                .short_neg, .short_pos => 1,
                .long => 2,
                .repeat => @as(usize, 0),
            };
            y_offset += f_offset;
        }

        const searched: i16 = switch (flag.variant(.y)) {
            .short_pos => s.yc_ptr[y_offset],
            .short_neg => -@as(i16, s.yc_ptr[y_offset]),
            .long => byteSwap(@as(*align(1) const i16, @alignCast(@ptrCast(s.yc_ptr[y_offset..].ptr))).*),
            .repeat => @as(i16, 0),
        };
        std.debug.assert(searched == real);
        return searched;
    }

    pub fn init(alloc: Allocator, data: []const u8) !Simple {
        var runtime_parser = RuntimeParser{ .data = data };
        const common = runtime_parser.readVal(Header);

        const end_pts_of_contours = try runtime_parser.readArray(u16, alloc, @intCast(common.number_of_contours));
        const instruction_length = runtime_parser.readVal(u16);
        //const instructions = try runtime_parser.readArray(u8, alloc, instruction_length);
        for (0..instruction_length) |_| _ = runtime_parser.readVal(u8);
        const num_contours = end_pts_of_contours[end_pts_of_contours.len - 1] + 1;

        //std.debug.print("number of contors {}\n", .{common.number_of_contours});
        //std.debug.print("end pt of contors {any}\n", .{end_pts_of_contours});
        //std.debug.print("real number of contors {}\n", .{num_contours});

        const contours = try alloc.alloc(Contour, num_contours);
        const fl_ptr: []const u8 = data[runtime_parser.idx..];
        var i: usize = 0;
        while (i < num_contours) : (i += 1) {
            const flag: Simple.Flags = @bitCast(runtime_parser.readVal(u8));
            std.debug.assert(flag.reserved == false);
            contours[i].flag = flag;

            if (flag.repeat_flag) {
                const num_repetitions = runtime_parser.readVal(u8);
                for (0..num_repetitions) |rep| {
                    contours[i + 1 + rep].flag = flag;
                }
                i += num_repetitions;
            }
        }

        //var simple: Simple = undefined;
        //simple.fl_ptr = fl_ptr;
        //const xc_ptr: []const u8 = data[runtime_parser.idx..];
        //var y_off: usize = 0;
        //for (0..num_contours) |fi| {
        //    y_off += switch (simple.getFlag(fi).variant(.x)) {
        //        .short_pos, .short_neg => 1,
        //        .long => 2,
        //        .repeat => 0,
        //    };
        //}
        //const yc_ptr: []const u8 = data[runtime_parser.idx + y_off ..];

        const xc_ptr: []const u8 = data[runtime_parser.idx..];
        for (contours) |*cont| {
            cont.x_coord = switch (cont.flag.variant(.x)) {
                .short_pos => runtime_parser.readVal(u8),
                .short_neg => -@as(i16, runtime_parser.readVal(u8)),
                .long => runtime_parser.readVal(i16),
                .repeat => 0,
            };
        }

        const yc_ptr: []const u8 = data[runtime_parser.idx..];
        for (contours) |*cont| {
            cont.y_coord = switch (cont.flag.variant(.y)) {
                .short_pos => runtime_parser.readVal(u8),
                .short_neg => -@as(i16, runtime_parser.readVal(u8)),
                .long => runtime_parser.readVal(i16),
                .repeat => 0,
            };
        }

        return .{
            .end_pts_of_contours = end_pts_of_contours,
            .instruction_length = instruction_length,
            .contours = contours,
            .num_contours = num_contours,

            .fl_ptr = fl_ptr,
            .xc_ptr = xc_ptr,
            .yc_ptr = yc_ptr,
        };
    }
};

pub const Compound = struct {
    components: []Component,

    pub const Flags = packed struct(u16) {
        args_are_words: bool,
        args_are_xy: bool,
        round_xy_to_grid: bool,
        comp_has_scale: bool,
        _obsolete: bool,
        more_components: bool,
        x_and_y_scales: bool,
        two_by_two_scales: bool,
        we_have_instructions: bool,
        use_my_metrics: bool,
        overlap_compound: bool,
        _padding: u5,
    };

    pub const Transform = union(enum) {
        scale: u16, // scale (same for x and y)
        xy_scale: struct {
            x: u16,
            y: u16,
        },
        xy_twoby: struct {
            x: u16,
            z01: u16,
            z10: u16,
            y: u16,
        },
    };

    /// This pretends to match the layout, but because TTF says arg0,1 can be
    /// i8 or u8 or i16 or u16, they're set i32 here to cover all cases
    pub const Component = struct {
        flag: Flags,
        index: u32,
        arg0: i32,
        arg1: i32,
        transform: Transform,
    };

    pub fn init(alloc: Allocator, data: []const u8) !Compound {
        var runtime_parser = RuntimeParser{ .data = data };
        _ = runtime_parser.readVal(Header);
        var clist: std.ArrayList(Compound.Component) = .init(alloc);
        while (true) {
            const flags: Compound.Flags = @bitCast(runtime_parser.readVal(u16));
            const index: u16 = runtime_parser.readVal(u16);
            const arg0: i16, const arg1: i16 = if (flags.args_are_words)
                .{ runtime_parser.readVal(i16), runtime_parser.readVal(i16) }
            else
                .{ runtime_parser.readVal(i8), runtime_parser.readVal(i8) };
            const transform = Compound.getTransform(flags, &runtime_parser);
            try clist.append(.{
                .flag = flags,
                .index = index,
                .arg0 = arg0,
                .arg1 = arg1,
                .transform = transform,
            });
            if (!flags.more_components) break;
        }

        return .{ .components = try clist.toOwnedSlice() };
    }

    fn getED(f: Flags) struct { f16, f16 } {
        const _f8 = 0;
        const _f16 = 0;
        const idx_8 = 0;
        const idx_16 = 0;
        switch (f.args_are_xy) {
            true => return if (f.args_are_words)
                .{ _f16, _f16 }
            else
                .{ _f8, _f8 },
            false => return if (f.args_are_words)
                .{ idx_16, idx_16 }
            else
                .{ idx_8, idx_8 },
        }
    }

    fn getTransform(f: Flags, rp: *Glyf.RuntimeParser) Transform {
        if (!f.comp_has_scale and !f.x_and_y_scales and !f.two_by_two_scales) return .{ .scale = 1 };

        if (f.comp_has_scale) {
            std.debug.assert(!f.x_and_y_scales);
            std.debug.assert(!f.two_by_two_scales);

            return .{ .xy_scale = .{
                .x = rp.readVal(u16),
                .y = rp.readVal(u16),
            } };
        }
        if (f.x_and_y_scales) {
            std.debug.assert(!f.comp_has_scale);
            std.debug.assert(!f.two_by_two_scales);
            return .{ .xy_scale = .{
                .x = rp.readVal(u16),
                .y = rp.readVal(u16),
            } };
        }
        if (f.two_by_two_scales) {
            std.debug.assert(!f.comp_has_scale);
            std.debug.assert(!f.two_by_two_scales);
            return .{ .xy_twoby = .{
                .x = rp.readVal(u16),
                .z01 = rp.readVal(u16),
                .z10 = rp.readVal(u16),
                .y = rp.readVal(u16),
            } };
        }
        unreachable;
    }

    fn transformation(a: i16, b: i16, c: i16, d: i16, e: i16) void {
        const m = @max(@abs(a), @abs(b)) * if (@abs(@abs(a) - @abs(c)) <= 33 / 65536) 2 else 1;
        const n = @max(@abs(c), @abs(d)) * if (@abs(@abs(b) - @abs(d)) <= 33 / 65536) 2 else 1;

        const x = 0;
        const y = 0;
        const x2 = m * ((a / m) * x + (c / m) * y + e);
        const y2 = m * ((b / n) * x + (d / n) * y + e);
        _ = x2;
        _ = y2;
    }
};

pub fn init(bytes: []align(2) const u8) Glyf {
    return .{ .data = bytes };
}

pub fn glyph(glyf: Glyf, alloc: Allocator, start: usize, end: usize) !Glyph {
    const header: Header = .fromBytes(@alignCast(glyf.data[start..]));

    return .{
        .header = header,
        .src_data = @alignCast(glyf.data[start..end]),
        .glyph = if (header.number_of_contours < 0) .{
            .compound = try .init(alloc, glyf.data[start..end]),
        } else .{
            .simple = try .init(alloc, glyf.data[start..end]),
        },
    };
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

fn fixSliceEndianness(comptime T: type, alloc: Allocator, slice: []align(1) const T) ![]T {
    const duped = try alloc.alloc(T, slice.len);
    for (0..slice.len) |i| {
        duped[i] = fixEndianness(slice[i]);
    }
    return duped;
}

fn fixEndianness(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
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

pub inline fn byteSwap(val: anytype) @TypeOf(val) {
    const builtin = @import("builtin");
    if (comptime builtin.cpu.arch.endian() == .big) {
        return val;
    }
    return @byteSwap(val);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Glyph = @import("../../Glyph.zig");
