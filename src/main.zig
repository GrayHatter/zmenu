pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var zm: ZMenu = try .init(alloc);
    const box: Buffer.Box = .wh(600, 480);

    try zm.wayland.init(box);
    defer zm.raze(alloc);

    const shm = zm.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, box, "zmenu-buffer1");
    defer buffer.raze();
    //try drawColors(size, buffer, colors);
    buffer.drawRectangleRoundedFill(Buffer.ARGB, box, 25, .alpha(.ash_gray, 0x7c));
    buffer.drawRectangleRoundedFill(Buffer.ARGB, .xywh(35, 30, 600 - 35 * 2, 40), 10, .ash_gray);
    buffer.drawRectangleRounded(Buffer.ARGB, .xywh(35, 30, 600 - 35 * 2, 40), 10, .hookers_green);
    buffer.drawRectangleRounded(Buffer.ARGB, .xywh(36, 31, 598 - 35 * 2, 38), 9, .hookers_green);

    try zm.wayland.roundtrip();

    const paths = [_][]const u8{"/usr/bin"};
    var sys_exes: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, 4096);
    var thread = try std.Thread.spawn(.{}, scanPaths, .{ alloc, &sys_exes, &paths });
    defer thread.join();

    const surface = zm.wayland.surface orelse return error.NoSurface;
    surface.attach(buffer.buffer, 0, 0);
    surface.commit();
    try zm.wayland.roundtrip();

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(alloc, font);

    var glyph_cache: Glyph.Cache = .init(14);
    defer glyph_cache.raze(alloc);

    const dir = std.fs.cwd();
    const commands: []Command = loadHistory(dir, alloc) catch |err| b: {
        std.debug.print("error loading history {}\n", .{err});
        break :b &.{};
    };

    const history_box: Buffer.Box = .xywh(45, 70, box.w - 70, box.h - 95);

    _ = try drawHistory(alloc, &glyph_cache, &buffer, commands, "", ttf, history_box);

    surface.attach(buffer.buffer, 0, 0);
    surface.damageBuffer(0, 0, @intCast(box.w), @intCast(box.h));
    surface.commit();

    var i: usize = 0;
    var draw_count: usize = 0;
    while (zm.running) : (i +%= 1) {
        try zm.wayland.iterate();
        if (i % 1000 == 0) {
            surface.attach(buffer.buffer, 0, 0);
            surface.damage(0, 0, @intCast(box.w), @intCast(box.h));
            surface.commit();
        }
        if (zm.key_buffer.items.len != draw_count) {
            @branchHint(.unlikely);
            draw_count = zm.key_buffer.items.len;
            buffer.drawRectangleRoundedFill(Buffer.ARGB, .xywh(35, 30, 512 + 40, 40), 10, .ash_gray);
            buffer.drawRectangleRounded(Buffer.ARGB, .xywh(35, 30, 512 + 40, 40), 10, .hookers_green);
            buffer.drawRectangleRounded(Buffer.ARGB, .xywh(36, 31, 510 + 40, 38), 9, .hookers_green);
            if (draw_count > 0) {
                try drawText(alloc, &glyph_cache, &buffer, zm.key_buffer.items, ttf, .xywh(45, 55, box.w - 80, box.h - 80));
            }
            const hist_drawn = try drawHistory(alloc, &glyph_cache, &buffer, commands, zm.key_buffer.items, ttf, history_box);
            var path_box = history_box;
            path_box.y += 20 * hist_drawn;
            path_box.h -= 20 * hist_drawn;
            _ = try drawPathlist(alloc, &glyph_cache, &buffer, sys_exes.items, zm.key_buffer.items, ttf, path_box);
            surface.attach(buffer.buffer, 0, 0);
            surface.damageBuffer(0, 0, @intCast(box.w), @intCast(box.h));
            surface.commit();
        }
    }

    if (zm.key_buffer.items.len > 2) {
        try writeOutHistory(dir, commands, zm.key_buffer.items);
    }
}

pub const Options = struct {
    history: bool = true,
};

fn loadRc(a: Allocator) !Options {
    const rc = std.fs.cwd().readFileAlloc(a, ".zmenurc", 0x1ffff) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer a.free(rc);
    // split lines
    // parse line
    // return options

    return .{};
}

pub const Command = struct {
    count: usize,
    time: i64 = 0,
    text: []const u8,

    pub fn raze(c: Command, a: Allocator) void {
        a.free(c.text);
    }
};

fn loadHistory(dir: std.fs.Dir, a: Allocator) ![]Command {
    const history = dir.readFileAlloc(a, ".zmenu_history", 0x1ffff) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer a.free(history);

    const count = std.mem.count(u8, history, "\n");
    const cmds: []Command = try a.alloc(Command, count);

    var itr = std.mem.splitScalar(u8, history, '\n');
    for (cmds) |*cmd| {
        const line = itr.next() orelse return error.IteratorFailed;
        if (std.mem.indexOfScalar(u8, line, ':')) |i| {
            const text_i = std.mem.indexOfScalarPos(u8, line, i + 1, ':') orelse i;
            cmd.* = .{
                .count = std.fmt.parseInt(usize, line[0..i], 10) catch return error.InvalidHitCount,
                .text = try a.dupe(u8, line[text_i + 1 ..]),
            };
        } else return error.InvalidHistoryLine;
    }
    return cmds;
}

fn writeOutHistory(dir: std.fs.Dir, cmds: []Command, new: []const u8) !void {
    var next: Command = .{
        .count = 1,
        .text = new,
    };
    for (cmds) |*cmd| {
        if (std.mem.eql(u8, cmd.text, new)) {
            cmd.count += 1;
            next.count = 0;
            break;
        }
    }
    std.mem.sort(Command, cmds, {}, struct {
        pub fn inner(_: void, l: Command, r: Command) bool {
            return l.count >= r.count;
        }
    }.inner);

    var file = try dir.createFile(".zmenu_history.new", .{});
    var w = file.writer();
    for (cmds) |c| try w.print("{}::{s}\n", .{ c.count, c.text });
    if (next.count > 0) try w.print("{}::{s}\n", .{ next.count, next.text });
    file.close();
    try dir.rename(".zmenu_history.new", ".zmenu_history");
}

/// Paths must be absolute
fn scanPaths(a: Allocator, list: *std.ArrayListUnmanaged([]const u8), paths: []const []const u8) void {
    for (paths) |path| {
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
            std.debug.print("Unable to open path '{s}' because {}\n", .{ path, err });
            continue;
        };
        defer dir.close();
        var ditr = dir.iterate();

        while (ditr.next() catch |err| {
            std.debug.print("Unable to iterate on path '{s}' because {}\n", .{ path, err });
            break;
        }) |file| switch (file.kind) {
            .file => list.append(a, a.dupe(u8, file.name) catch @panic("OOM")) catch @panic("OOM"),
            else => {},
        };
        std.Thread.yield() catch {};
    }
}

fn drawPathlist(
    a: Allocator,
    gc: *Glyph.Cache,
    buf: *const Buffer,
    bins: []const []const u8,
    prefix: []const u8,
    ttf: Ttf,
    box: Buffer.Box,
) !usize {
    if (prefix.len == 0 or bins.len == 0) return 0;
    var drawn: usize = 0;
    for (bins) |bin| {
        const y = box.y + 20 + 20 * (drawn);
        if (prefix.len == 0 or std.mem.startsWith(u8, bin, prefix)) {
            try drawText(a, gc, buf, bin, ttf, .xywh(box.x, y, box.w, 25));
            drawn += 1;
        }
        if (drawn > 4) break;
    }
    return drawn;
}

fn drawHistory(
    a: Allocator,
    gc: *Glyph.Cache,
    buf: *const Buffer,
    cmds: []Command,
    prefix: []const u8,
    ttf: Ttf,
    box: Buffer.Box,
) !usize {
    buf.drawRectangleFill(Buffer.ARGB, box, .alpha(.ash_gray, 0x7c));
    var drawn: usize = 0;
    for (cmds) |cmd| {
        const y = box.y + 20 + 20 * (drawn);
        if (prefix.len == 0 or std.mem.startsWith(u8, cmd.text, prefix)) {
            try drawText(a, gc, buf, cmd.text, ttf, .xywh(box.x, y, box.w, 25));
            drawn += 1;
        }

        if (drawn > 4) break;
    }
    return drawn;
}

fn drawText(
    alloc: Allocator,
    cache: *Glyph.Cache,
    buffer: *const Buffer,
    text: []const u8,
    ttf: Ttf,
    box: Buffer.Box,
) !void {
    var layout_helper = LayoutHelper.init(alloc, text, ttf, @intCast(box.w), 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    for (tl.glyphs) |g| {
        const canvas, _ = (try cache.get(alloc, ttf, g.char)).*;
        buffer.drawFont(Buffer.ARGB, .charcoal, .xywh(
            @intCast(@as(i32, @intCast(box.x)) + g.pixel_x1),
            @intCast(@as(i32, @intCast(box.y)) - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
    }
}

fn drawColors(size: usize, buffer: Buffer, colors: Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = @intCast(x * 0xff / size);
        const r_y: usize = @intCast(y * 0xff / size);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c = Buffer.ARGB.rgb(r, g, b);
        colors.draw(.xywh(x, y, 1, 1), &[1]u32{c.int()});
        const b2: u8 = 0xff - g;
        const c2 = Buffer.ARGB.rgb(r, g, b2);
        buffer.draw(.xywh(x, y, 1, 1), &[1]u32{@intFromEnum(c2)});
    };
}

fn drawBackground0(buf: Buffer, box: Buffer.Box) !void {
    for (box.y..box.y2()) |y| for (box.x..box.x2()) |x| {
        const r_y: usize = @intCast(y * 0xff / buf.width);
        const r_x: usize = @intCast(x * 0xff / buf.width);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = 0xff - g;
        const c = Buffer.ARGB.rgb(r, g, b);
        buf.drawPoint(Buffer.ARGB, .xy(x, y), c);
    };
}

test {
    _ = &Buffer;
    _ = &LayoutHelper;
    _ = &Ttf;
    _ = &ZMenu;
    _ = &Glyph;
}

const Buffer = @import("Buffer.zig");
const LayoutHelper = @import("LayoutHelper.zig");
const Ttf = @import("ttf.zig");
const Glyph = @import("Glyph.zig");
const ZMenu = @import("ZMenu.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
const Zwp = wayland.client.zwp;
