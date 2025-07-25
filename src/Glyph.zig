header: Glyf.Header,
src_data: []align(2) const u8,

glyph: Type,

const Glyph = @This();

pub fn renderSimpleSize(glyph: Glyf.Simple, bbox: BBox, canvas: *Canvas, ext: RenderExtra) !void {
    var curves: std.BoundedArray(Glyph.Segment.Segment, 100) = .{};
    var iter = Glyph.Segment.Iterator.init(glyph);
    while (iter.next()) |item| {
        try curves.append(item);
    }

    var y = bbox.min_y;
    while (y < bbox.max_y) : (y += 1) {
        const row_curve_points = try Segment.findRowCurvePoints(curves.slice(), y);

        var winding_count: i64 = 0;
        var start: i64 = 0;
        for (row_curve_points.slice()) |point| {
            if (point.entering == false) {
                winding_count -= 1;
            } else {
                winding_count += 1;
                if (winding_count == 1) {
                    start = point.x_pos;
                }
            }
            // NOTE: Always see true first due to sorting
            if (winding_count == 0) {
                const not_y: i64 = y - @as(isize, @intCast(bbox.min_y)) + ext.y_offset;
                const left = @min(start, point.x_pos) + ext.x_offset;
                const right = @max(start, point.x_pos) + ext.x_offset;
                canvas.draw(not_y, left - bbox.min_x, right - bbox.min_x);
            }
        }
    }
}

pub const Type = union(enum) {
    simple: Glyf.Simple,
    compound: Compound,
};

pub const RenderExtra = struct {
    size: f32 = 1.0,
    u_per_em: f32 = 1.0,
    /// TODO verify this is safe to be a i32 instead of i16 see also
    /// `Compound.Component`
    x_offset: i32 = 0,
    y_offset: i32 = 0,
};

pub const Compound = struct {
    //Compound glyphs are glyphs made up of two or more component glyphs. A
    //compound glyph description begins like a simple glyph description with
    //four words describing the bounding box. It is followed by n component
    //glyph parts. Each component glyph parts consists of a flag entry, two
    //offset entries and from one to four transformation entries.

    //The format for describing each component glyph in a compound glyph is
    //documented in Table 17. The meanings associated with the flags in the
    //first entry are given in Table 18.

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

    pub fn getTransform(f: Flags, rp: *Glyf.RuntimeParser) Transform {
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

pub const BBox = struct {
    const invalid = BBox{
        .min_x = std.math.maxInt(i16),
        .max_x = std.math.minInt(i16),
        .min_y = std.math.maxInt(i16),
        .max_y = std.math.minInt(i16),
    };

    min_x: i16,
    max_x: i16,
    min_y: i16,
    max_y: i16,

    pub fn width(self: BBox) usize {
        return @intCast(self.max_x - self.min_x);
    }

    pub fn height(self: BBox) usize {
        return @intCast(self.max_y - self.min_y);
    }

    pub fn mergeWith(a: BBox, b: BBox) BBox {
        return .{
            .min_x = @min(a.min_x, b.min_x),
            .max_x = @max(a.max_x, b.max_x),
            .min_y = @min(a.min_y, b.min_y),
            .max_y = @max(a.max_y, b.max_y),
        };
    }
};

pub fn renderSize(glyph: Glyph, alloc: Allocator, ttf: Ttf, ext: RenderExtra) !RenderedGlyph {
    var bbox = BBox{
        .min_x = glyph.header.x_min,
        .max_x = glyph.header.x_max,
        .min_y = glyph.header.y_min,
        .max_y = glyph.header.y_max,
    };
    const dpi = 96; // Default DPI is 96
    const base_dpi = 72; // from ttf spec

    var canvas: Canvas = try .initScale(
        alloc,
        bbox.width(),
        bbox.height(),
        ext.size * dpi / (base_dpi * ext.u_per_em),
    );

    switch (glyph.glyph) {
        .simple => |s| try renderSimpleSize(s, bbox, &canvas, ext),
        .compound => |c| for (c.components) |com| {
            const start, const end = ttf.offsetFromIndex(com.index) orelse continue;
            const next = try ttf.glyf.glyph(alloc, start, end);
            if (next.glyph != .simple) @panic("something's fucky");
            try renderSimpleSize(next.glyph.simple, bbox, &canvas, .{
                .x_offset = com.arg0,
                .y_offset = com.arg1,
                .size = ext.size,
                .u_per_em = ext.u_per_em,
            });
        },
    }

    return .{ canvas, bbox };
}

pub fn debugGlyph(rendered: Canvas) void {
    std.debug.print("               |", .{});
    for (0..rendered.width) |i| std.debug.print("{d:4}", .{i});
    std.debug.print("\n", .{});
    std.debug.print("               |____________________________________\n", .{});
    for (1..rendered.height + 1) |h| {
        std.debug.print("sy {d:3}  dy {d:3} | ", .{ h, rendered.height - h });
        for (rendered.getRow(@intCast(rendered.height - h)) orelse {
            std.debug.print("\n", .{});
            continue;
        }) |x| {
            std.debug.print("{d:3} ", .{x});
        }
        std.debug.print("\n", .{});
    }
}

test "renderSize" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    //const alloc = std.testing.allocator;

    var timer: std.time.Timer = try .start();
    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(@alignCast(font));

    const g = try ttf.glyphForChar(alloc, 'd');
    const rendered, _ = try g.renderSize(alloc, ttf, .{ .size = 14, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
    defer alloc.free(rendered.pixels);

    if (false) debugGlyph(rendered);
    const lap = timer.lap();
    //std.debug.print("glyph {}\n", .{rendered});
    if (false) std.debug.print("lap {}\n", .{lap});
}

pub const RenderedGlyph = struct {
    Canvas,
    BBox,
};

pub fn render(glyph: Glyph, alloc: Allocator, ttf: Ttf) !RenderedGlyph {
    return try glyph.renderSize(alloc, ttf, .{ .size = 1.0, .u_per_em = 1.0 });
}

const RuntimeParser = struct {
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

pub const Cache = struct {
    map: std.AutoHashMapUnmanaged(u8, RenderedGlyph) = .{},
    size: f32,

    pub fn init(size: f32) Cache {
        return .{
            .size = size,
        };
    }

    pub fn raze(c: *Cache, a: Allocator) void {
        var kitr = c.map.keyIterator();
        while (kitr.next()) |key| {
            _ = c.map.fetchRemove(key.*);
            // TODO clean up glyph canvas
        }
        c.map.deinit(a);
    }

    pub fn get(c: *Cache, a: Allocator, ttf: Ttf, char: u8) !*const RenderedGlyph {
        const gop = try c.map.getOrPut(a, char);
        errdefer _ = c.map.remove(char);
        if (!gop.found_existing) {
            const g = try ttf.glyphForChar(a, char);
            const rendered = try g.renderSize(a, ttf, .{ .size = c.size, .u_per_em = @floatFromInt(ttf.head.units_per_em) });
            gop.value_ptr.* = rendered;
        }
        return gop.value_ptr;
    }
};

//fn pixelBoundsForGlyph(scale: f32, header: Glyph.Header) [2]u16 {
//    const width_f: f32 = @floatFromInt(header.x_max - header.x_min);
//    const height_f: f32 = @floatFromInt(header.y_max - header.y_min);
//
//    return .{
//        @intFromFloat(@round(width_f * scale)),
//        @intFromFloat(@round(height_f * scale)),
//    };
//}
//pub fn pixelFromFunit(scale: f32, funit: i64) i32 {
//    const size_f: f32 = @floatFromInt(funit);
//    return @intFromFloat(@round(scale * size_f));
//}

test "glyph main" {
    _ = std.testing.refAllDecls(@This());
    _ = &Canvas;
    _ = &Segment;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const Ttf = @import("ttf.zig");
const Glyf = @import("ttf/tables/Glyf.zig");
const Canvas = @import("Canvas.zig");
pub const Segment = @import("glyph/Segment.zig");
