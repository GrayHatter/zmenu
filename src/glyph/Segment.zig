pub const Segment = union(enum) {
    line: Line,
    bezier: Bezier,

    pub const Line = struct {
        a: FPoint,
        b: FPoint,
        contour_id: usize,
    };
    pub const Bezier = struct {
        a: FPoint,
        b: FPoint,
        c: FPoint,
        contour_id: usize,
    };
};

pub const Iterator = struct {
    glyph: Glyf.Simple,

    idx: usize = 0,
    contour_idx: usize = 0,
    pos_acc: FPoint = .{ 0, 0 },
    prev_contour_end: FPoint = .{ 0, 0 },

    pub fn init(glyph: Glyf.Simple) Iterator {
        return .{
            .glyph = glyph,
        };
    }

    pub fn next(self: *Iterator) ?Segment {
        while (true) {
            if (self.idx >= self.glyph.num_contours) return null;
            defer self.idx += 1;

            const a = self.getPoint(self.idx, self.pos_acc);

            defer self.pos_acc = a.pos;

            const b = self.getPoint(self.idx + 1, self.pos_acc);
            const c = self.getPoint(self.idx + 2, self.pos_acc);

            const ret = abcToCurve(a, b, c, self.contour_idx);
            if (self.glyph.end_pts_of_contours[self.contour_idx] == self.idx) {
                self.contour_idx += 1;
                self.prev_contour_end = a.pos;
            }

            return ret orelse continue;
        }
    }

    fn abcToCurve(a: Point, b: Point, c: Point, contour_idx: usize) ?Segment {
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

        const a_on = if (a.on_curve) a.pos else (a.pos + b.pos) / FPoint{ 2, 2 };
        const c_on = if (c.on_curve) c.pos else (c.pos + b.pos) / FPoint{ 2, 2 };

        return .{ .bezier = .{
            .a = a_on,
            .b = b.pos,
            .c = c_on,
            .contour_id = contour_idx,
        } };
    }

    fn contourStart(self: Iterator) usize {
        return if (self.contour_idx > 0) self.glyph.end_pts_of_contours[self.contour_idx - 1] + 1 else 0;
    }

    fn wrappedContourIdx(self: Iterator, idx: usize) usize {
        const contour_start = self.contourStart();
        const contour_len = self.glyph.end_pts_of_contours[self.contour_idx] + 1 - contour_start;

        return (idx - contour_start) % contour_len + contour_start;
    }

    fn getPoint(self: Iterator, idx: usize, pos: FPoint) Point {
        var x_acc = pos[0];
        var y_acc = pos[1];

        for (self.idx..idx + 1) |i| {
            const wrapped_i = self.wrappedContourIdx(i);
            if (wrapped_i == self.contourStart()) {
                x_acc = self.prev_contour_end[0];
                y_acc = self.prev_contour_end[1];
            }
            x_acc += self.glyph.getX(wrapped_i);
            y_acc += self.glyph.getY(wrapped_i);
        }

        const on_curve = self.glyph.getFlag(self.wrappedContourIdx(idx)).on_curve_point;
        return .{
            .on_curve = on_curve,
            .pos = .{ x_acc, y_acc },
        };
    }
};

pub fn findRowCurvePoint(curve: Segment, y: i64) !RowCurvePoint {
    _ = curve;
    _ = y;
}

fn linePoints(l: Segment.Line, y: i64) ?RowCurvePoint {
    const a_f: @Vector(2, f32) = @floatFromInt(l.a);
    const b_f: @Vector(2, f32) = @floatFromInt(l.b);
    const y_f: f32 = @floatFromInt(y);

    if (l.b[1] == l.a[1]) return null;
    const t = (y_f - a_f[1]) / (b_f[1] - a_f[1]);

    if (!(t >= 0.0 and t <= 1.0)) {
        return null;
    }

    const x = std.math.lerp(a_f[0], b_f[0], t);

    const x_pos_i: i64 = @intFromFloat(@round(x));
    const entering = l.a[1] < l.b[1];

    return .{ .entering = entering, .x_pos = x_pos_i, .contour_id = l.contour_id };
}

fn bezierPoints(b: Segment.Bezier, y: i64) ?[2]?RowCurvePoint {
    const a_f: @Vector(2, f32) = @floatFromInt(b.a);
    const b_f: @Vector(2, f32) = @floatFromInt(b.b);
    const c_f: @Vector(2, f32) = @floatFromInt(b.c);

    const eps = 1e-7;

    const t1, const t2 = findBezierTForY(a_f[1], b_f[1], c_f[1], @floatFromInt(y));
    const part1: ?RowCurvePoint = brk: {
        if (!(t1 >= 0.0 and t1 <= 1.0)) break :brk null;
        const tangent_line = quadBezierTangentLine(a_f, b_f, c_f, t1);
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
        const at_apex = @abs(tangent_line.a[1] - tangent_line.b[1]) < eps;
        const at_end = t1 < eps or @abs(t1 - 1.0) < eps;
        const moving_up = tangent_line.a[1] < tangent_line.b[1] or b.a[1] < b.c[1];
        if (at_apex and !at_end) break :brk null;

        const x_f = sampleQuadBezierCurve(a_f, b_f, c_f, t1)[0];
        const x_px: i64 = @intFromFloat(@round(x_f));
        break :brk .{
            .entering = moving_up,
            .x_pos = x_px,
            .contour_id = b.contour_id,
        };
    };
    const part2: ?RowCurvePoint = brk: {
        if (!(t2 >= 0.0 and t2 <= 1.0)) break :brk null;
        const tangent_line = quadBezierTangentLine(a_f, b_f, c_f, t2);
        const at_apex = @abs(tangent_line.a[1] - tangent_line.b[1]) < eps;
        const moving_up = tangent_line.a[1] < tangent_line.b[1] or b.a[1] < b.c[1];
        if (at_apex) break :brk null;
        const x_f = sampleQuadBezierCurve(a_f, b_f, c_f, t2)[0];
        const x_px: i64 = @intFromFloat(@round(x_f));
        break :brk .{
            .entering = moving_up,
            .x_pos = x_px,
            .contour_id = b.contour_id,
        };
    };
    return .{
        part1, part2,
    };
}

pub fn findRowCurvePoints(curves: []const Segment, y: i64) !std.BoundedArray(Glyph.Segment.RowCurvePoint, 20) {
    var array: std.BoundedArray(Glyph.Segment.RowCurvePoint, 20) = .{};
    for (curves) |curve| {
        switch (curve) {
            .line => |l| try array.append(linePoints(l, y) orelse continue),
            .bezier => |b| for (bezierPoints(b, y) orelse continue) |p| {
                try array.append(p orelse continue);
            },
        }
    }

    try sortRemoveDuplicateCurvePoints(&array);
    return array;
}

const FPoint = @Vector(2, i16);

const Point = struct {
    on_curve: bool,
    pos: FPoint,
};

pub const RowCurvePoint = struct {
    x_pos: i64,
    entering: bool,
    contour_id: usize = 0,

    pub fn format(value: RowCurvePoint, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d} ({})", .{ value.x_pos, value.entering });
    }
};

fn sortRemoveDuplicateCurvePoints(points: *std.BoundedArray(RowCurvePoint, 20)) !void {
    var buffer: [20]usize = undefined;
    var to_remove: std.ArrayListUnmanaged(usize) = .initBuffer(&buffer);
    for (0..points.slice().len) |i| {
        const next_idx = (i + 1) % points.slice().len;
        if (points.slice()[i].entering == points.slice()[next_idx].entering and points.slice()[i].contour_id == points.slice()[next_idx].contour_id) {
            if (points.slice()[i].entering) {
                if (points.slice()[i].x_pos > points.slice()[next_idx].x_pos) {
                    to_remove.appendAssumeCapacity(i);
                } else {
                    to_remove.appendAssumeCapacity(next_idx);
                }
            } else {
                if (points.slice()[i].x_pos > points.slice()[next_idx].x_pos) {
                    to_remove.appendAssumeCapacity(next_idx);
                } else {
                    to_remove.appendAssumeCapacity(i);
                }
            }
        }
    }

    while (to_remove.pop()) |i| {
        if (points.slice().len == 1) break;
        _ = points.swapRemove(i);
    }

    const lessThan = struct {
        fn f(_: void, lhs: RowCurvePoint, rhs: RowCurvePoint) bool {
            if (lhs.x_pos == rhs.x_pos) {
                return lhs.entering and !rhs.entering;
            }
            return lhs.x_pos < rhs.x_pos;
        }
    }.f;
    std.mem.sort(RowCurvePoint, points.slice(), {}, lessThan);
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

const TangentLine = struct {
    a: @Vector(2, f32),
    b: @Vector(2, f32),
};

test "find row points V" {
    // Double counted point at the apex of a V, should immediately go in and out
    const curves = [_]Segment{
        .{ .line = .{ .a = .{ -1.0, 1.0 }, .b = .{ 0.0, 0.0 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 0.0, 0.0 }, .b = .{ 1.0, 1.0 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 0);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{ .x_pos = 0, .entering = true },
            .{ .x_pos = 0, .entering = false },
        },
        points.slice(),
    );
}

test "find row points X" {
    // Double entry and exit on the horizontal part where there's wraparound
    const curves = [_]Segment{
        .{ .line = .{ .a = .{ 5, 0 }, .b = .{ 10, -10 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ -10, -10 }, .b = .{ -5, 0 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ -5, 0 }, .b = .{ -10, 10 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 10, 10 }, .b = .{ 5, 0 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 0);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{ .x_pos = -5, .entering = true },
            .{ .x_pos = 5, .entering = false },
        },
        points.slice(),
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

    const curves = [_]Segment{
        .{ .line = .{ .a = .{ 0, -5 }, .b = .{ 0, 0 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 0, 0 }, .b = .{ 5, 0 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 5, 0 }, .b = .{ 5, 5 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 5, 5 }, .b = .{ 10, 5 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 10, 5 }, .b = .{ 10, -5 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 0);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(
        RowCurvePoint,
        &.{
            .{ .x_pos = 0, .entering = true },
            .{ .x_pos = 10, .entering = false },
        },
        points.slice(),
    );
}

test "find row points horizontal line into bezier cw" {
    // Bottom inside of one of the holes in the letter B
    // shape like ___/. Here we want to ensure that after we exit the
    // quadratic, we have determined that we are outside the curve
    const curves = [_]Segment{
        .{ .bezier = .{ .a = .{ 855, 845 }, .b = .{ 755, 713 }, .c = .{ 608, 713 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 608, 713 }, .b = .{ 369, 713 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 369, 713 }, .b = .{ 369, 800 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 713);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(RowCurvePoint, &.{
        .{ .x_pos = 369, .entering = true },
        .{ .x_pos = 608, .entering = false },
    }, points.slice());
}

test "find row points bezier apex matching" {
    // Top of a C. There are two bezier curves that run into eachother at the
    // apex with a tangent of 0. This should result in an immediate in/out
    const curves = [_]Segment{
        .{ .bezier = .{ .a = .{ 350, 745 }, .b = .{ 350, 135 }, .c = .{ 743, 135 }, .contour_id = 0 } },
        .{ .bezier = .{ .a = .{ 743, 135 }, .b = .{ 829, 135 }, .c = .{ 916, 167 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 135);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(RowCurvePoint, &.{
        .{ .x_pos = 743, .entering = true },
        .{ .x_pos = 743, .entering = false },
    }, points.slice());
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

    const curves = [_]Segment{
        .{ .line = .{ .a = .{ 0, 0 }, .b = .{ 1, 1 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 1, 1 }, .b = .{ 2, 2 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 1);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(RowCurvePoint, &.{
        .{ .x_pos = 1, .entering = true },
    }, points.slice());
}

test "find row points bezier curve into line" {
    // In the following case
    //  |<-----
    //  |      \
    //  v
    //
    // If we end up on the horizontal line, we should see an exit followed by entry (counter clockwise)
    //
    const curves = [_]Segment{
        .{ .bezier = .{ .a = .{ 5, 0 }, .b = .{ 5, 1 }, .c = .{ 3, 1 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 3, 1 }, .b = .{ 1, 1 }, .contour_id = 0 } },
        .{ .line = .{ .a = .{ 1, 1 }, .b = .{ 1, 0 }, .contour_id = 0 } },
    };

    const points = try findRowCurvePoints(&curves, 1);
    //defer std.testing.allocator.free(points);

    //if (true) return error.SkipZigTest;
    try std.testing.expectEqualSlices(RowCurvePoint, &.{
        .{ .x_pos = 1, .entering = false },
        .{ .x_pos = 3, .entering = true },
    }, points.slice());
}

test "bezier solving" {
    const curves = [_][3]@Vector(2, f32){
        .{ .{ -20, 20 }, .{ 0, 0 }, .{ 20, 20 } },
        .{ .{ -15, -30 }, .{ 5, 15 }, .{ 10, 20 } },
        .{ .{ 40, -30 }, .{ 80, -10 }, .{ 20, 10 } },
    };

    const ts = [_]f32{ 0.0, 0.1, 0.4, 0.5, 0.8, 1.0 };

    for (curves) |curve| {
        for (ts) |in_t| {
            const point1 = sampleQuadBezierCurve(curve[0], curve[1], curve[2], in_t);

            var t1, var t2 = findBezierTForY(curve[0][1], curve[1][1], curve[2][1], point1[1]);
            if (@abs(t1 - in_t) > @abs(t2 - in_t)) {
                std.mem.swap(f32, &t1, &t2);
            }
            try std.testing.expectApproxEqAbs(in_t, t1, 0.001);

            if (t2 <= 1.0 and t2 >= 0.0) {
                const point2 = sampleQuadBezierCurve(curve[0], curve[1], curve[2], t2);
                try std.testing.expectApproxEqAbs(point2[1], point1[1], 0.001);
            }
        }
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Glyph = @import("../Glyph.zig");
const Glyf = @import("../ttf/tables/Glyf.zig");
