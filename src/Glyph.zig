const Glyph = @This();

pub const Header = packed struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

pub const Simple = struct {
    common: Header,
    data: []align(2) const u8,
    end_pts_of_contours: []u16,
    instruction_length: u16,
    //instructions: []u8,
    flags: []Flags,
    x_coordinates: []i16,
    y_coordinates: []i16,

    fl_ptr: []const u8,
    xc_ptr: []const u8,
    yc_ptr: []const u8,

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

    pub fn renderSize(glyph: Glyph.Simple, alloc: Allocator, size: f32, u_per_em: usize) !RenderedGlyph {
        var curves = std.ArrayList(Glyph.SegmentIter.Output).init(alloc);
        defer curves.deinit();

        _ = size;
        _ = u_per_em;
        //const s = fontScale(size, @floatFromInt(u_per_em));
        var bbox = BBox{
            .min_x = glyph.common.x_min,
            .max_x = glyph.common.x_max,
            .min_y = glyph.common.y_min,
            .max_y = glyph.common.y_max,
        };

        var iter = Glyph.SegmentIter.init(glyph);
        while (iter.next()) |item| {
            try curves.append(item);
        }

        var canvas = try Canvas.init(alloc, ((bbox.width() + 7) / 8) * 8, bbox.height());

        var y = bbox.min_y;
        while (y < bbox.max_y) {
            defer y += 1;
            const not_y: i64 = y - @as(isize, @intCast(bbox.min_y));
            const row_curve_points = try findRowCurvePoints(alloc, curves.items, y);
            defer alloc.free(row_curve_points);

            var winding_count: i64 = 0;
            var start: i64 = 0;
            for (row_curve_points) |point| {
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
                    canvas.draw(not_y, start - bbox.min_x, point.x_pos - bbox.min_x);
                }
            }
        }

        return .{ canvas, bbox };
    }

    pub const RenderedGlyph = struct {
        Canvas,
        BBox,
    };

    pub fn render1PxPerFunit(alloc: Allocator, glyph: Glyph.Simple) !RenderedGlyph {
        return try renderSize(alloc, glyph, 1.0, 1.0);
    }
};

pub const Compound = struct {
    common: Header,
    data: []const u8,

    //Compound glyphs are glyphs made up of two or more component glyphs. A
    //compound glyph description begins like a simple glyph description with
    //four words describing the bounding box. It is followed by n component
    //glyph parts. Each component glyph parts consists of a flag entry, two
    //offset entries and from one to four transformation entries.

    //The format for describing each component glyph in a compound glyph is
    //documented in Table 17. The meanings associated with the flags in the
    //first entry are given in Table 18.

    flags: u16,
    glyphIndex: u16,
    arg1: union { int16: i16, uint16: u16, int8: i8, uint8: u8 },
    arg2: union { int16: i16, uint16: u16, int8: i8, uint8: u8 },

    pub const Flags = packed struct(u16) {
        args_are_words: bool,
        args_are_xy: bool,
        round_xy_to_grid: bool,
        single_scale: bool,
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

    fn getABCD(f: Flags) struct { u16, u16, u16, u16 } {
        const _u16 = 0;
        if (!f.single_scale) return .{ 1, 0, 0, 1 };

        if (f.single_scale) {
            std.debug.assert(!f.x_and_y_scales);
            std.debug.assert(!f.two_by_two_scales);
            return .{ _u16, 0, 0, _u16 };
        }
        if (f.x_and_y_scales) {
            std.debug.assert(!f.single_scale);
            std.debug.assert(!f.two_by_two_scales);
            return .{ _u16, 0, 0, _u16 };
        }
        if (f.two_by_two_scales) {
            std.debug.assert(!f.single_scale);
            std.debug.assert(!f.two_by_two_scales);
            return .{ _u16, _u16, _u16, _u16 };
        }
        return undefined;
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

const Canvas = struct {
    pixels: []u8,
    width: usize,
    height: usize,
    scale: f64,

    pub fn init(alloc: Allocator, width: usize, height: usize) !Canvas {
        return try initScale(alloc, width, height, 0.0188866);
    }

    pub fn initScale(alloc: Allocator, width: usize, height: usize, scale: f64) !Canvas {
        const w: u64 = @intFromFloat(@ceil(@as(f64, @floatFromInt(width)) * scale));
        const h: u64 = @intFromFloat(@ceil(@as(f64, @floatFromInt(height)) * scale));
        const pixels = try alloc.alloc(u8, w * h);
        @memset(pixels, 0);

        return .{
            .pixels = pixels,
            .width = w,
            .height = h,
            .scale = scale,
        };
    }

    pub fn iWidth(self: Canvas) i64 {
        return @intCast(self.width);
    }

    pub fn calcHeight(self: Canvas) i64 {
        return @intCast(self.pixels.len / self.width);
    }

    pub fn clampY(self: Canvas, val: i64) usize {
        return @intCast(std.math.clamp(val, 0, self.calcHeight()));
    }

    pub fn clampX(self: Canvas, val: i64) usize {
        return @intCast(std.math.clamp(val, 0, self.iWidth()));
    }

    fn getRow(c: Canvas, y: i64) ?[]u8 {
        const start: usize = c.width * @as(usize, @intCast(y));
        if (start >= c.pixels.len - c.width) return null;
        return c.pixels[start..][0..c.width];
    }

    pub fn draw(c: Canvas, y_int: i64, min_int: i64, max_int: i64) void {
        var y: f64 = @floatFromInt(y_int);
        var min: f64 = @floatFromInt(min_int);
        var max: f64 = @floatFromInt(max_int);
        const contra: u8 = if (@floor(y * c.scale) != @round(y * c.scale)) 0xAA else 0xFF;
        // Floor seems to look better, but I want to experment more
        if (comptime false) {
            y = @floor(y * c.scale);
            min = @floor(min * c.scale);
            max = @floor(max * c.scale);
        } else {
            y = @round(y * c.scale);
            min = @round(min * c.scale);
            max = @round(max * c.scale);
        }

        const x1: usize = c.clampX(@intFromFloat(min));
        const x2: usize = c.clampX(@intFromFloat(max));
        const row = c.getRow(@intFromFloat(y)) orelse return;
        for (row[x1..x2]) |*x| x.* |= contra;
    }
};

const FPoint = @Vector(2, i16);

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

pub const Table = struct {
    data: []const u8,

    pub fn glyphHeader(self: Table, start: usize) Header {
        const ptr: *align(2) const Header = @alignCast(@ptrCast(self.data[start..][0..@sizeOf(Header)]));

        return .{
            .number_of_contours = @byteSwap(ptr.number_of_contours),
            .x_min = @byteSwap(ptr.x_min),
            .x_max = @byteSwap(ptr.x_max),
            .y_min = @byteSwap(ptr.y_min),
            .y_max = @byteSwap(ptr.y_max),
        };
    }

    pub fn compound(self: Table, alloc: Allocator, start: usize, end: usize) !Compound {
        var runtime_parser = RuntimeParser{ .data = self.data[start..end] };
        const common = runtime_parser.readVal(Header);

        //std.debug.print("common {}\n", .{common});

        const end_pts_of_contours = try runtime_parser.readArray(u16, alloc, @intCast(common.number_of_contours));
        const instruction_length = runtime_parser.readVal(u16);
        //const instructions = try runtime_parser.readArray(u8, alloc, instruction_length);
        for (0..instruction_length) |_| _ = runtime_parser.readVal(u8);
        const num_contours = end_pts_of_contours[end_pts_of_contours.len - 1] + 1;

        const flags = try alloc.alloc(Compound.Flags, num_contours);
        const x_coords = try alloc.alloc(i16, num_contours);
        const y_coords = try alloc.alloc(i16, num_contours);

        const fl_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        var i: usize = 0;
        while (i < num_contours) {
            defer i += 1;
            const flag: Compound.Flags = @bitCast(runtime_parser.readVal(u8));
            std.debug.assert(flag.reserved == false);

            flags[i] = flag;

            if (flag.repeat_flag) {
                const num_repetitions = runtime_parser.readVal(u8);
                @memset(flags[i + 1 .. i + 1 + num_repetitions], flag);
                i += num_repetitions;
            }
        }

        const xc_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        for (flags, x_coords) |flag, *xc| {
            switch (flag.variant(.x)) {
                .short_pos => xc.* = runtime_parser.readVal(u8),
                .short_neg => xc.* = -@as(i16, runtime_parser.readVal(u8)),
                .long => xc.* = runtime_parser.readVal(i16),
                .repeat => xc.* = 0,
            }
        }

        const yc_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        for (flags, y_coords) |flag, *yc| {
            switch (flag.variant(.y)) {
                .short_pos => yc.* = runtime_parser.readVal(u8),
                .short_neg => yc.* = -@as(i16, runtime_parser.readVal(u8)),
                .long => yc.* = runtime_parser.readVal(i16),
                .repeat => yc.* = 0,
            }
        }

        return .{
            .common = common,
            .data = @alignCast(self.data[start..end]),
            .end_pts_of_contours = end_pts_of_contours,
            .instruction_length = instruction_length,
            //.instructions = instructions,
            .flags = flags,
            .x_coordinates = x_coords,
            .y_coordinates = y_coords,

            .fl_ptr = fl_ptr,
            .xc_ptr = xc_ptr,
            .yc_ptr = yc_ptr,
        };
    }

    pub fn simple(self: Table, alloc: Allocator, start: usize, end: usize) !Simple {
        var runtime_parser = RuntimeParser{ .data = self.data[start..end] };
        const common = runtime_parser.readVal(Header);

        //std.debug.print("common {}\n", .{common});

        const end_pts_of_contours = try runtime_parser.readArray(u16, alloc, @intCast(common.number_of_contours));
        const instruction_length = runtime_parser.readVal(u16);
        //const instructions = try runtime_parser.readArray(u8, alloc, instruction_length);
        for (0..instruction_length) |_| _ = runtime_parser.readVal(u8);
        const num_contours = end_pts_of_contours[end_pts_of_contours.len - 1] + 1;

        const flags = try alloc.alloc(Simple.Flags, num_contours);
        const x_coords = try alloc.alloc(i16, num_contours);
        const y_coords = try alloc.alloc(i16, num_contours);

        const fl_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        var i: usize = 0;
        while (i < num_contours) {
            defer i += 1;
            const flag: Simple.Flags = @bitCast(runtime_parser.readVal(u8));
            std.debug.assert(flag.reserved == false);

            flags[i] = flag;

            if (flag.repeat_flag) {
                const num_repetitions = runtime_parser.readVal(u8);
                @memset(flags[i + 1 .. i + 1 + num_repetitions], flag);
                i += num_repetitions;
            }
        }

        const xc_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        for (flags, x_coords) |flag, *xc| {
            switch (flag.variant(.x)) {
                .short_pos => xc.* = runtime_parser.readVal(u8),
                .short_neg => xc.* = -@as(i16, runtime_parser.readVal(u8)),
                .long => xc.* = runtime_parser.readVal(i16),
                .repeat => xc.* = 0,
            }
        }

        const yc_ptr: []const u8 = self.data[start + runtime_parser.idx ..];
        for (flags, y_coords) |flag, *yc| {
            switch (flag.variant(.y)) {
                .short_pos => yc.* = runtime_parser.readVal(u8),
                .short_neg => yc.* = -@as(i16, runtime_parser.readVal(u8)),
                .long => yc.* = runtime_parser.readVal(i16),
                .repeat => yc.* = 0,
            }
        }

        return .{
            .common = common,
            .data = @alignCast(self.data[start..end]),
            .end_pts_of_contours = end_pts_of_contours,
            .instruction_length = instruction_length,
            //.instructions = instructions,
            .flags = flags,
            .x_coordinates = x_coords,
            .y_coordinates = y_coords,

            .fl_ptr = fl_ptr,
            .xc_ptr = xc_ptr,
            .yc_ptr = yc_ptr,
        };
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

pub const SegmentIter = struct {
    glyph: Glyph.Simple,
    x_acc: i16 = 0,
    y_acc: i16 = 0,

    idx: usize = 0,
    contour_idx: usize = 0,
    last_contour_last_point: FPoint = .{ 0, 0 },

    pub const Output = union(enum) {
        line: struct {
            a: FPoint,
            b: FPoint,
            contour_id: usize,
        },
        bezier: struct {
            a: FPoint,
            b: FPoint,
            c: FPoint,
            contour_id: usize,
        },
    };

    pub fn init(glyph: Glyph.Simple) SegmentIter {
        return SegmentIter{
            .glyph = glyph,
        };
    }

    pub fn next(self: *SegmentIter) ?Output {
        while (true) {
            if (self.idx >= self.glyph.x_coordinates.len) return null;
            defer self.idx += 1;

            const a = self.getPoint(self.idx);

            defer self.x_acc = a.pos[0];
            defer self.y_acc = a.pos[1];

            const b = self.getPoint(self.idx + 1);
            const c = self.getPoint(self.idx + 2);

            const ret = abcToCurve(a, b, c, self.contour_idx);
            if (self.glyph.end_pts_of_contours[self.contour_idx] == self.idx) {
                self.contour_idx += 1;
                self.last_contour_last_point = a.pos;
            }

            if (ret) |val| {
                return val;
            }
        }
    }

    const Point = struct {
        on_curve: bool,
        pos: FPoint,
    };

    fn abcToCurve(a: Point, b: Point, c: Point, contour_idx: usize) ?Output {
        if (a.on_curve and b.on_curve) {
            return .{ .line = .{
                .a = a.pos,
                .b = b.pos,
                .contour_id = contour_idx,
            } };
        } else if (b.on_curve) {
            return null;
        }

        std.debug.assert(!b.on_curve);

        const a_on = resolvePoint(a, b);
        const c_on = resolvePoint(c, b);

        return .{ .bezier = .{
            .a = a_on,
            .b = b.pos,
            .c = c_on,
            .contour_id = contour_idx,
        } };
    }

    fn contourStart(self: SegmentIter) usize {
        if (self.contour_idx == 0) {
            return 0;
        } else {
            return self.glyph.end_pts_of_contours[self.contour_idx - 1] + 1;
        }
    }

    fn wrappedContourIdx(self: SegmentIter, idx: usize) usize {
        const contour_start = self.contourStart();
        const contour_len = self.glyph.end_pts_of_contours[self.contour_idx] + 1 - contour_start;

        return (idx - contour_start) % contour_len + contour_start;
    }

    fn getPoint(self: *SegmentIter, idx: usize) Point {
        var x_acc = self.x_acc;
        var y_acc = self.y_acc;

        for (self.idx..idx + 1) |i| {
            const wrapped_i = self.wrappedContourIdx(i);
            if (wrapped_i == self.contourStart()) {
                x_acc = self.last_contour_last_point[0];
                y_acc = self.last_contour_last_point[1];
            }
            x_acc += self.glyph.x_coordinates[wrapped_i];
            y_acc += self.glyph.y_coordinates[wrapped_i];
        }

        const pos = FPoint{
            x_acc,
            y_acc,
        };

        const on_curve = self.glyph.flags[self.wrappedContourIdx(idx)].on_curve_point;
        return .{
            .on_curve = on_curve,
            .pos = pos,
        };
    }

    fn resolvePoint(maybe_off: Point, off: Point) FPoint {
        if (maybe_off.on_curve) return maybe_off.pos;
        std.debug.assert(off.on_curve == false);

        return (maybe_off.pos + off.pos) / FPoint{ 2, 2 };
    }
};

const RowCurvePointInner = struct {
    x_pos: i64,
    entering: bool,
    contour_id: usize,

    pub fn format(value: RowCurvePointInner, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d} ({}, {})", .{ value.x_pos, value.entering, value.contour_id });
    }
};

const RowCurvePoint = struct {
    x_pos: i64,
    entering: bool,

    pub fn format(value: RowCurvePoint, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d} ({})", .{ value.x_pos, value.entering });
    }
};

fn sortRemoveDuplicateCurvePoints(alloc: Allocator, points: *std.ArrayList(RowCurvePointInner)) !void {
    var to_remove = std.ArrayList(usize).init(alloc);
    defer to_remove.deinit();
    for (0..points.items.len) |i| {
        const next_idx = (i + 1) % points.items.len;
        if (points.items[i].entering == points.items[next_idx].entering and points.items[i].contour_id == points.items[next_idx].contour_id) {
            if (points.items[i].entering) {
                if (points.items[i].x_pos > points.items[next_idx].x_pos) {
                    try to_remove.append(i);
                } else {
                    try to_remove.append(next_idx);
                }
            } else {
                if (points.items[i].x_pos > points.items[next_idx].x_pos) {
                    try to_remove.append(next_idx);
                } else {
                    try to_remove.append(i);
                }
            }
        }
    }

    while (to_remove.pop()) |i| {
        if (points.items.len == 1) break;
        _ = points.swapRemove(i);
    }

    const lessThan = struct {
        fn f(_: void, lhs: RowCurvePointInner, rhs: RowCurvePointInner) bool {
            if (lhs.x_pos == rhs.x_pos) {
                return lhs.entering and !rhs.entering;
            }
            return lhs.x_pos < rhs.x_pos;
        }
    }.f;
    std.mem.sort(RowCurvePointInner, points.items, {}, lessThan);
}

fn findRowCurvePoints(alloc: Allocator, curves: []const Glyph.SegmentIter.Output, y: i64) ![]RowCurvePoint {
    var ret = std.ArrayList(RowCurvePointInner).init(alloc);
    defer ret.deinit();

    for (curves) |curve| {
        switch (curve) {
            .line => |l| {
                const a_f: @Vector(2, f32) = @floatFromInt(l.a);
                const b_f: @Vector(2, f32) = @floatFromInt(l.b);
                const y_f: f32 = @floatFromInt(y);

                if (l.b[1] == l.a[1]) continue;
                const t = (y_f - a_f[1]) / (b_f[1] - a_f[1]);

                if (!(t >= 0.0 and t <= 1.0)) {
                    continue;
                }

                const x = std.math.lerp(a_f[0], b_f[0], t);

                const x_pos_i: i64 = @intFromFloat(@round(x));
                const entering = l.a[1] < l.b[1];

                try ret.append(.{ .entering = entering, .x_pos = x_pos_i, .contour_id = l.contour_id });
            },
            .bezier => |b| {
                const a_f: @Vector(2, f32) = @floatFromInt(b.a);
                const b_f: @Vector(2, f32) = @floatFromInt(b.b);
                const c_f: @Vector(2, f32) = @floatFromInt(b.c);

                const ts = findBezierTForY(a_f[1], b_f[1], c_f[1], @floatFromInt(y));

                for (ts, 0..) |t, i| {
                    if (!(t >= 0.0 and t <= 1.0)) {
                        continue;
                    }
                    const tangent_line = quadBezierTangentLine(a_f, b_f, c_f, t);

                    const eps = 1e-7;
                    const at_apex = @abs(tangent_line.a[1] - tangent_line.b[1]) < eps;
                    const at_end = t < eps or @abs(t - 1.0) < eps;
                    const moving_up = tangent_line.a[1] < tangent_line.b[1] or b.a[1] < b.c[1];

                    // If we are at the apex, and at the very edge of a curve,
                    // we have to be careful. In this case we can only count
                    // one of the enter/exit events as we are only half of the
                    // parabola.
                    //
                    // U -> enter/exit
                    // \_ -> enter
                    // _/ -> exit
                    //  _
                    // / -> enter
                    // _
                    //  \-> exit

                    // The only special case is that we are at the apex, and at
                    // the end of the curve. In this case we only want to
                    // consider one of the two points. Otherwise we just ignore
                    // the apex as it's an immediate enter/exit. I.e. useless
                    //
                    // This boils down to the following condition
                    if (at_apex and (!at_end or i == 1)) continue;

                    const x_f = sampleQuadBezierCurve(a_f, b_f, c_f, t)[0];
                    const x_px: i64 = @intFromFloat(@round(x_f));
                    try ret.append(.{
                        .entering = moving_up,
                        .x_pos = x_px,
                        .contour_id = b.contour_id,
                    });
                }
            },
        }
    }

    try sortRemoveDuplicateCurvePoints(alloc, &ret);

    const real_ret = try alloc.alloc(RowCurvePoint, ret.items.len);
    for (0..ret.items.len) |i| {
        real_ret[i] = .{
            .entering = ret.items[i].entering,
            .x_pos = ret.items[i].x_pos,
        };
    }

    return real_ret;
}

test "find row points V" {
    // Double counted point at the apex of a V, should immediately go in and out
    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .line = .{
                .a = .{ -1.0, 1.0 },
                .b = .{ 0.0, 0.0 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 0.0, 0.0 },
                .b = .{ 1.0, 1.0 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 0);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 0,
                .entering = true,
            },
            .{
                .x_pos = 0,
                .entering = false,
            },
        },
        points,
    );
}

test "find row points X" {
    // Double entry and exit on the horizontal part where there's wraparound
    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .line = .{
                .a = .{ 5, 0 },
                .b = .{ 10, -10 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ -10, -10 },
                .b = .{ -5, 0 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ -5, 0 },
                .b = .{ -10, 10 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 10, 10 },
                .b = .{ 5, 0 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 0);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = -5,
                .entering = true,
            },
            .{
                .x_pos = 5,
                .entering = false,
            },
        },
        points,
    );
}

test "find row points G" {
    // G has segment that goes
    //
    // |       ^
    // v____   |
    //      |  |
    //      v  |
    //
    // In this case we somehow have to avoid double counting the down arrow
    //

    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .line = .{
                .a = .{ 0, -5 },
                .b = .{ 0, 0 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 0, 0 },
                .b = .{ 5, 0 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 5, 0 },
                .b = .{ 5, 5 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 5, 5 },
                .b = .{ 10, 5 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 10, 5 },
                .b = .{ 10, -5 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 0);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 0,
                .entering = true,
            },
            .{
                .x_pos = 10,
                .entering = false,
            },
        },
        points,
    );
}

test "find row points horizontal line into bezier cw" {
    // Bottom inside of one of the holes in the letter B
    // shape like ___/. Here we want to ensure that after we exit the
    // quadratic, we have determined that we are outside the curve
    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .bezier = .{
                .a = .{ 855, 845 },
                .b = .{ 755, 713 },
                .c = .{ 608, 713 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 608, 713 },
                .b = .{ 369, 713 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 369, 713 },
                .b = .{ 369, 800 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 713);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 369,
                .entering = true,
            },
            .{
                .x_pos = 608,
                .entering = false,
            },
        },
        points,
    );
}

test "find row points bezier apex matching" {
    // Top of a C. There are two bezier curves that run into eachother at the
    // apex with a tangent of 0. This should result in an immediate in/out
    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .bezier = .{
                .a = .{ 350, 745 },
                .b = .{ 350, 135 },
                .c = .{ 743, 135 },
                .contour_id = 0,
            },
        },
        .{
            .bezier = .{
                .a = .{ 743, 135 },
                .b = .{ 829, 135 },
                .c = .{ 916, 167 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 135);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 743,
                .entering = true,
            },
            .{
                .x_pos = 743,
                .entering = false,
            },
        },
        points,
    );
}

test "find row points ascending line segments" {
    // Double counted point should be deduplicated as it's going in the same direction
    //
    // e.g. the o will be in two segments, but should count as one line cross
    //     /
    //    /
    //   o
    //  /
    // /

    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .line = .{
                .a = .{ 0, 0 },
                .b = .{ 1, 1 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 1, 1 },
                .b = .{ 2, 2 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 1);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 1,
                .entering = true,
            },
        },
        points,
    );
}

test "find row points bezier curve into line" {
    // In the following case
    //  |<-----
    //  |      \
    //  v
    //
    // If we end up on the horizontal line, we should see an exit followed by entry (counter clockwise)
    //
    const curves = [_]Glyph.SegmentIter.Output{
        .{
            .bezier = .{
                .a = .{ 5, 0 },
                .b = .{ 5, 1 },
                .c = .{ 3, 1 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 3, 1 },
                .b = .{ 1, 1 },
                .contour_id = 0,
            },
        },
        .{
            .line = .{
                .a = .{ 1, 1 },
                .b = .{ 1, 0 },
                .contour_id = 0,
            },
        },
    };

    const points = try findRowCurvePoints(std.testing.allocator, &curves, 1);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{
                .x_pos = 1,
                .entering = false,
            },
            .{
                .x_pos = 3,
                .entering = true,
            },
        },
        points,
    );
}

pub fn findBezierTForY(p1: f32, p2: f32, p3: f32, y: f32) [2]f32 {
    // Bezier curve formula comes from lerping p1->p2 by t, p2->p3 by t, and
    // then lerping the line from those two points by t as well
    //
    // p12 = (t * (p2 - p1)) + p1
    // p23 = (t * (p3 - p2)) + p2
    // out = (t * (p23 - p12)) + p12
    //
    // expanding and simplifying...
    // p12 = t*p2 - t*p1 + p1
    // p23 = t*p3 - t*p2 + p2
    // out = t(t*p3 - t*p2 + p2) - t(t*p2 - t*p1 + p1) + t*p2 - t*p1 + p1
    // out = t^2*p3 - t^2*p2 + t*p2 - t^2*p2 + t^2*p1 - t*p1 + t*p2 - t*p1 + p1
    // out = t^2(p3 - 2*p2 + p1) + t(p2 - p1 + p2 - p1) + p1
    // out = t^2(p3 - 2*p2 + p1) + 2*t(p2 - p1) + p1
    //
    // Which now looks like a quadratic formula that we can solve for.
    // Calling t^2 coefficient a, t coefficient b, and the remainder c...
    const a = p3 - 2 * p2 + p1;
    const b = 2 * (p2 - p1);
    // Note that we are solving for out == y, so we need to adjust the c term
    // to p1 - y
    const c = p1 - y;

    const eps = 1e-7;
    const not_quadratic = @abs(a) < eps;
    const not_linear = not_quadratic and @abs(b) < eps;
    if (not_linear) {
        // I guess in this case we can return any t, as all t values will
        // result in the same y value.
        return .{ 0.5, 0.5 };
    } else if (not_quadratic) {
        // bt + c = 0 (c accounts for y)
        const ret = -c / b;
        return .{ ret, ret };
    }

    const out_1 = (-b + @sqrt(b * b - 4 * a * c)) / (2 * a);
    const out_2 = (-b - @sqrt(b * b - 4 * a * c)) / (2 * a);
    return .{ out_1, out_2 };
}

const TangentLine = struct {
    a: @Vector(2, f32),
    b: @Vector(2, f32),
};

pub fn quadBezierTangentLine(a: @Vector(2, f32), b: @Vector(2, f32), c: @Vector(2, f32), t: f32) TangentLine {
    const t_splat: @Vector(2, f32) = @splat(t);
    const ab = std.math.lerp(a, b, t_splat);
    const bc = std.math.lerp(b, c, t_splat);
    return .{
        .a = ab,
        .b = bc,
    };
}

pub fn sampleQuadBezierCurve(a: @Vector(2, f32), b: @Vector(2, f32), c: @Vector(2, f32), t: f32) @Vector(2, f32) {
    const tangent_line = quadBezierTangentLine(a, b, c, t);
    return std.math.lerp(tangent_line.a, tangent_line.b, @as(@Vector(2, f32), @splat(t)));
}

test "bezier solving" {
    const curves = [_][3]@Vector(2, f32){
        .{
            .{ -20, 20 },
            .{ 0, 0 },
            .{ 20, 20 },
        },
        .{
            .{ -15, -30 },
            .{ 5, 15 },
            .{ 10, 20 },
        },
        .{
            .{ 40, -30 },
            .{ 80, -10 },
            .{ 20, 10 },
        },
    };

    const ts = [_]f32{ 0.0, 0.1, 0.4, 0.5, 0.8, 1.0 };

    for (curves) |curve| {
        for (ts) |in_t| {
            const point1 = sampleQuadBezierCurve(
                curve[0],
                curve[1],
                curve[2],
                in_t,
            );

            var t1, var t2 = findBezierTForY(curve[0][1], curve[1][1], curve[2][1], point1[1]);
            if (@abs(t1 - in_t) > @abs(t2 - in_t)) {
                std.mem.swap(f32, &t1, &t2);
            }
            try std.testing.expectApproxEqAbs(in_t, t1, 0.001);

            if (t2 <= 1.0 and t2 >= 0.0) {
                const point2 = sampleQuadBezierCurve(
                    curve[0],
                    curve[1],
                    curve[2],
                    t2,
                );

                try std.testing.expectApproxEqAbs(point2[1], point1[1], 0.001);
            }
        }
    }
}

fn pixelBoundsForGlyph(scale: f32, header: Glyph.Header) [2]u16 {
    const width_f: f32 = @floatFromInt(header.x_max - header.x_min);
    const height_f: f32 = @floatFromInt(header.y_max - header.y_min);

    return .{
        @intFromFloat(@round(width_f * scale)),
        @intFromFloat(@round(height_f * scale)),
    };
}
pub fn pixelFromFunit(scale: f32, funit: i64) i32 {
    const size_f: f32 = @floatFromInt(funit);
    return @intFromFloat(@round(scale * size_f));
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
