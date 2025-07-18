pub const ZMenu = struct {
    pub const Wayland = struct {
        display: *wl.Display,
        registry: *wl.Registry,
        shm: ?*wl.Shm = null,
        compositor: ?*wl.Compositor = null,
        surface: ?*wl.Surface = null,
        wm_base: ?*Xdg.WmBase = null,
        seat: ?*wl.Seat = null,
        xdgsurface: ?*Xdg.Surface = null,
        toplevel: ?*Xdg.Toplevel = null,
        pointer: ?*wl.Pointer = null,
        keyboard: ?*wl.Keyboard = null,

        pub fn roundtrip(w: *Wayland) !void {
            if (w.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        }
    };

    wayland: Wayland,
    running: bool = true,

    pub fn init() !ZMenu {
        const display = try wl.Display.connect(null);
        const registry = try display.getRegistry();
        return .{
            .wayland = .{
                .display = display,
                .registry = registry,
            },
        };
    }

    pub fn initWayland(zm: *ZMenu) !void {
        zm.wayland.registry.setListener(*ZMenu, listeners.registry, zm);
        if (zm.wayland.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn end(zm: *ZMenu) void {
        zm.running = false;
    }

    pub fn configure(_: *ZMenu, evt: Xdg.Toplevel.Event) void {
        if (false) std.debug.print("toplevel conf {}\n", .{evt});
    }

    pub fn newKeymap(_: *ZMenu, evt: wl.Keyboard.Event) void {
        if (true) std.debug.print("newKeymap {} {}\n", .{ evt.keymap.fd, evt.keymap.size });
    }
};

pub fn main() !void {
    var zm: ZMenu = try .init();
    try zm.initWayland();

    const size = 900;

    const shm = zm.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, size, size, "zmenu-buffer1");
    defer buffer.raze();
    const colors: Buffer = try .init(shm, size, size, "zmenu-buffer2");
    defer colors.buffer.destroy();
    try drawColors(size, buffer, colors);

    try zm.wayland.roundtrip();

    const compositor = zm.wayland.compositor orelse return error.NoWlCompositor;

    const surface = try compositor.createSurface();
    defer surface.destroy();
    const wm_base = zm.wayland.wm_base orelse return error.NoXdgWmBase;
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    zm.wayland.toplevel = try xdg_surface.getToplevel(); //  orelse return error.NoToplevel;
    defer zm.wayland.toplevel.?.destroy();

    xdg_surface.setListener(*ZMenu, listeners.xdgSurface, &zm);
    zm.wayland.toplevel.?.setListener(*ZMenu, listeners.xdgToplevel, &zm);
    zm.wayland.toplevel.?.setMaxSize(size, size);
    zm.wayland.toplevel.?.setMinSize(size, size);
    surface.commit();
    try zm.wayland.roundtrip();

    surface.attach(colors.buffer, 0, 0);
    surface.commit();
    try zm.wayland.roundtrip();

    //zm.wayland.toplevel.?.setMaxSize(size, size);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(alloc, font);
    const text: []const u8 = "this is some really long text, text that I HOPE will be longer than the surface width!";
    try drawText(alloc, &buffer, text, ttf);

    var i: usize = 0;
    while (zm.running) {
        switch (zm.wayland.display.dispatch()) {
            .SUCCESS => {},
            else => |w| {
                std.debug.print("wut {}\n", .{w});
                return error.DispatchFailed;
            },
        }
        i +%= 1;
        if (i % 100 == 0) {
            if (i / 100 & 1 > 0) {
                surface.attach(colors.buffer, 0, 0);
                surface.damage(0, 0, size, size);
                surface.commit();
            } else {
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(0, 0, size, size);
                surface.commit();
            }
        }
    }
}

fn initWayland() !void {}

fn drawText(alloc: Allocator, buffer: *const Buffer, text: []const u8, ttf: Ttf) !void {
    var layout_helper = LayoutHelper.init(alloc, text, ttf, 512, 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    var black: [800 * 4]u8 align(4) = @splat(0xff);
    buffer.draw(.xywh(400, 100, 500, 1), black[0..]);
    const black_ptr: *[200]u32 = @ptrCast(&black);
    for (tl.glyphs, 0..) |g, i| {
        black_ptr.* = switch (i % 3) {
            0 => @splat(0xff000000 | (@as(u32, g.char) << 0)),
            1 => @splat(0xff000000 | (@as(u32, g.char) << 8)),
            2 => @splat(0xff000000 | (@as(u32, g.char) << 16)),
            else => unreachable,
        };
        //const height = g.pixel_y2 - g.pixel_y1;
        //const y_base: isize = 0 - height - g.pixel_y1;
        const glyph = try ttf.glyphForChar(alloc, g.char) orelse continue;

        const canvas, _ = try glyph.renderSize(alloc, 14, ttf.head.units_per_em);
        buffer.drawFont(.xywh(
            @intCast(400 + g.pixel_x1),
            @intCast(100 - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
    }
}

fn drawColors(size: usize, buffer: Buffer, colors: Buffer) !void {
    for (0..colors.raw.len / 4) |i| {
        const ratio: usize = @intCast(i * 100 / (colors.raw.len / 4));
        const ratio2: usize = @intCast((i % size) * 100 / size);
        const a: u8 = 0xff;
        const r: u8 = @truncate(0xff * ratio2 / 100);
        const g: u8 = @truncate(0xff * ratio / 100);
        const b: u8 = 0xff - r;
        colors.raw[i * 4 ..][0..4].* = .{ b, g, r, a };
        const b2: u8 = 0xff - g;
        buffer.raw[i * 4 ..][0..4].* = .{ r, b2, g, a };
    }
}

test {
    _ = &Buffer;
    _ = &LayoutHelper;
    _ = &Ttf;
    _ = &@import("Glyph.zig");
    _ = &listeners;
}

const Buffer = @import("Buffer.zig");
const LayoutHelper = @import("LayoutHelper.zig");
const Ttf = @import("ttf.zig");
const listeners = @import("listeners.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
