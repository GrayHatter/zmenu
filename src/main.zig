pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var zm: ZMenu = try .init();
    const box: Buffer.Box = .wh(600, 480);

    try zm.wayland.init(box);
    defer zm.raze();
    root_zmenu = &zm;

    var ui_options_children = [_]ui.Component{
        .{ .vtable = .auto(UiHistoryOptions), .children = &.{} },
        .{ .vtable = .auto(UiExecOptions), .children = &.{} },
    };

    var ui_children = [_]ui.Component{
        .{ .vtable = .auto(UiCommandBox), .children = &.{} },
        .{ .vtable = .auto(UiOptions), .children = &ui_options_children },
    };

    var root = ui.Component{
        .vtable = .auto(UiRoot),
        .box = box,
        .children = &ui_children,
    };
    zm.ui_root = &root;

    try root.init(alloc, box);
    defer root.raze(alloc);

    const shm = zm.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, box, "zmenu-buffer1");
    defer buffer.raze();

    root.background(&buffer, box);

    try zm.wayland.roundtrip();

    const paths = [_][]const u8{"/usr/bin"};
    sys_exes = try .initCapacity(alloc, 4096);
    var thread = try std.Thread.spawn(.{}, scanPaths, .{ alloc, &sys_exes, &paths });
    defer thread.join();

    const surface = zm.wayland.surface orelse return error.NoSurface;
    surface.attach(buffer.buffer, 0, 0);
    surface.commit();
    try zm.wayland.roundtrip();

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(alloc, font);
    ttf_ptr = &ttf;

    glyph_cache = .init(14);
    defer glyph_cache.raze(alloc);

    const dir = std.fs.cwd();
    command_history = loadHistory(dir, alloc) catch |err| b: {
        std.debug.print("error loading history {}\n", .{err});
        break :b &.{};
    };

    _ = root.draw(&buffer, box);

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
        if (ui_key_buffer.items.len != draw_count or root.damaged) {
            @branchHint(.unlikely);
            draw_count = ui_key_buffer.items.len;
            _ = root.draw(&buffer, box);
            surface.attach(buffer.buffer, 0, 0);
            surface.damageBuffer(0, 0, @intCast(box.w), @intCast(box.h));
            surface.commit();
            root.painted();
        }
    }

    if (ui_key_buffer.items.len > 2) {
        try writeOutHistory(dir, command_history, ui_key_buffer.items);
    }
}

var glyph_cache: Glyph.Cache = undefined;
var sys_exes: std.ArrayListUnmanaged([]const u8) = undefined;
var ui_key_buffer: *const std.ArrayListUnmanaged(u8) = undefined;
var ttf_ptr: *const Ttf = undefined;
var root_zmenu: *ZMenu = undefined;
var command_history: []Command = undefined;

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
            return !(l.count <= r.count);
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

const UiRoot = struct {
    pub fn background(_: *ui.Component, b: *const Buffer, box: Buffer.Box) void {
        b.drawRectangleRoundedFill(Buffer.ARGB, box, 25, .alpha(.ash_gray, 0x7c));
    }
};

const UiCommandBox = struct {
    alloc: Allocator,
    key_buffer: std.ArrayListUnmanaged(u8),

    pub fn init(comp: *ui.Component, a: Allocator, _: Buffer.Box) ui.InitError!void {
        const textbox: *UiCommandBox = try a.create(UiCommandBox);
        textbox.* = .{
            .alloc = a,
            .key_buffer = try .initCapacity(a, 4096),
        };
        comp.state = textbox;
        ui_key_buffer = &textbox.key_buffer;
    }

    pub fn raze(comp: *ui.Component, a: Allocator) void {
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        textbox.key_buffer.deinit(a);
        a.destroy(textbox);
    }

    pub fn draw(comp: *ui.Component, buffer: *const Buffer, root: Buffer.Box) bool {
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        var box = root;
        box = .xywh(35, 30, 600 - 35 * 2, 40);
        buffer.drawRectangleRoundedFill(Buffer.ARGB, box, 10, .ash_gray);
        buffer.drawRectangleRounded(Buffer.ARGB, box, 10, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 9, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 8, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 7, .hookers_green);

        if (textbox.key_buffer.items.len > 0) {
            drawText(
                textbox.alloc,
                &glyph_cache,
                buffer,
                ui_key_buffer.items,
                ttf_ptr.*,
                .xywh(45, 55, root.w - 80, root.h - 80),
            ) catch @panic("draw the textbox failed :<");
        }
        return true;
    }

    pub fn keyPress(comp: *ui.Component, evt: ui.KeyEvent) bool {
        if (evt.up) return false;
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        switch (evt.key) {
            .char => |chr| textbox.key_buffer.appendAssumeCapacity(chr),
            .ctrl => |ctrl| switch (ctrl) {
                .backspace => _ = textbox.key_buffer.pop(),
                .enter => {
                    if (textbox.key_buffer.items.len > 0) {
                        //if (std.posix.fork()) |pid| {
                        //    if (pid == 0) {
                        //        exec(zm.key_buffer.items) catch {};
                        //    } else {
                        //        zm.running = false;
                        //    }
                        //} else |_| @panic("everyone knows fork can't fail");
                    }
                },
                .escape => {
                    if (textbox.key_buffer.items.len > 0) {
                        textbox.key_buffer.clearRetainingCapacity();
                    } else {
                        root_zmenu.end();
                    }
                },
                else => {},
            },
        }
        return true;
    }
};

const UiOptions = struct {
    pub fn draw(comp: *ui.Component, buffer: *const Buffer, box: Buffer.Box) bool {
        const history_box: Buffer.Box = .xywh(45, 70, box.w - 70, box.h - 95);
        buffer.drawRectangleFill(Buffer.ARGB, history_box, .alpha(.ash_gray, 0x7c));

        const hist: *UiHistoryOptions = @alignCast(@ptrCast(comp.children[0].state));
        const ret = comp.children[0].draw(buffer, history_box);

        var path_box = history_box;
        path_box.y += 20 * hist.drawn;
        path_box.h -= 20 * hist.drawn;
        const path: *UiExecOptions = @alignCast(@ptrCast(comp.children[1].state));
        _ = &path;
        return comp.children[1].draw(buffer, path_box) or ret;
    }
};

const UiHistoryOptions = struct {
    alloc: Allocator,
    highlight: usize = 0,
    drawn: usize = 0,

    pub fn init(comp: *ui.Component, a: Allocator, _: Buffer.Box) ui.InitError!void {
        const options: *UiHistoryOptions = try a.create(UiHistoryOptions);
        options.* = .{
            .alloc = a,
        };
        comp.state = options;
    }

    pub fn raze(comp: *ui.Component, a: Allocator) void {
        a.destroy(@as(*UiHistoryOptions, @alignCast(@ptrCast(comp.state))));
    }

    pub fn draw(comp: *ui.Component, buffer: *const Buffer, box: Buffer.Box) bool {
        const hist: *UiHistoryOptions = @alignCast(@ptrCast(comp.state));

        const drawn = drawHistory(
            hist.alloc,
            buffer,
            hist.highlight,
            command_history,
            ui_key_buffer.items,
            box,
        ) catch @panic("drawing failed");
        hist.highlight = @min(hist.highlight, drawn);
        hist.drawn = drawn;
        return true;
    }

    pub fn keyPress(comp: *ui.Component, evt: ui.KeyEvent) bool {
        if (evt.up) return false;
        const highlight: *UiHistoryOptions = @alignCast(@ptrCast(comp.state));
        switch (evt.key) {
            .ctrl => |ctrl| switch (ctrl) {
                .arrow_up => highlight.highlight -|= 1,
                .arrow_down => highlight.highlight +|= 1,
                else => {},
            },
            else => {},
        }
        //std.debug.print("exec keyevent {}\n", .{evt});
        return true;
    }

    fn drawHistory(
        a: Allocator,
        buf: *const Buffer,
        highlighted: usize,
        cmds: []Command,
        prefix: []const u8,
        box: Buffer.Box,
    ) !usize {
        var fillbox = box;
        fillbox.x -|= 5;
        buf.drawRectangleFill(Buffer.ARGB, fillbox, .alpha(.ash_gray, 0x7c));
        var drawn: usize = 0;
        for (cmds) |cmd| {
            const y = box.y + 20 + 20 * (drawn);
            if (prefix.len == 0 or std.mem.startsWith(u8, cmd.text, prefix)) {
                try drawText(a, &glyph_cache, buf, cmd.text, ttf_ptr.*, .xywh(box.x, y, box.w, 25));
                drawn += 1;
                if (drawn == highlighted) {
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y - 19, box.w, 25), 10, .hookers_green);
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y - 18, box.w - 2, 25 - 2), 9, .hookers_green);
                }
            }

            if (drawn > 4) break;
        }
        if (highlighted > drawn and drawn > 0) {
            const y = box.y + 20 * (drawn - 1);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y + 1, box.w, 25), 10, .hookers_green);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y + 2, box.w - 2, 25 - 2), 9, .hookers_green);
        }
        return drawn;
    }
};
const UiExecOptions = struct {
    alloc: Allocator,
    highlight: usize = 0,
    drawn: usize = 0,

    pub fn init(comp: *ui.Component, a: Allocator, _: Buffer.Box) ui.InitError!void {
        const options: *UiExecOptions = try a.create(UiExecOptions);
        options.* = .{
            .alloc = a,
        };
        comp.state = options;
    }

    pub fn raze(comp: *ui.Component, a: Allocator) void {
        a.destroy(@as(*UiExecOptions, @alignCast(@ptrCast(comp.state))));
    }

    pub fn draw(comp: *ui.Component, buffer: *const Buffer, box: Buffer.Box) bool {
        const highlight: *UiExecOptions = @alignCast(@ptrCast(comp.state));

        const drawn = drawPathlist(
            highlight.alloc,
            buffer,
            highlight.highlight,
            sys_exes.items,
            ui_key_buffer.items,
            box,
        ) catch @panic("drawing failed");
        highlight.highlight = @min(highlight.highlight, drawn);
        highlight.drawn = drawn;
        return true;
    }

    pub fn keyPress(comp: *ui.Component, evt: ui.KeyEvent) bool {
        if (evt.up) return false;
        const highlight: *UiExecOptions = @alignCast(@ptrCast(comp.state));
        switch (evt.key) {
            .ctrl => |ctrl| switch (ctrl) {
                .arrow_up => highlight.highlight -|= 1,
                .arrow_down => highlight.highlight +|= 1,
                else => {},
            },
            else => {},
        }
        //std.debug.print("exec keyevent {}\n", .{evt});
        return true;
    }

    fn drawPathlist(
        a: Allocator,
        buf: *const Buffer,
        highlighted: usize,
        bins: []const []const u8,
        prefix: []const u8,
        box: Buffer.Box,
    ) !usize {
        if (prefix.len == 0 or bins.len == 0) return 0;
        var drawn: usize = 0;
        for (bins) |bin| {
            const y = box.y + 20 + 20 * (drawn);
            if (prefix.len == 0 or std.mem.startsWith(u8, bin, prefix)) {
                try drawText(a, &glyph_cache, buf, bin, ttf_ptr.*, .xywh(box.x, y, box.w, 25));
                drawn += 1;
                if (drawn == highlighted) {
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y - 19, box.w, 25), 10, .hookers_green);
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y - 18, box.w - 2, 25 - 2), 9, .hookers_green);
                }
            }
            if (drawn > 6) break;
        }
        if (highlighted > drawn and drawn > 0) {
            const y = box.y + 20 * (drawn - 1);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y + 1, box.w, 25), 10, .hookers_green);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y + 2, box.w - 2, 25 - 2), 9, .hookers_green);
        }
        return drawn;
    }
};

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
const ui = @import("ui.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
const Zwp = wayland.client.zwp;
