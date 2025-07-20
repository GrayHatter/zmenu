pub const ZMenu = struct {
    wayland: Wayland,
    keymap: Keymap = .{},
    running: bool = true,
    key_buffer: std.ArrayListUnmanaged(u8),

    pub const Wayland = struct {
        display: *wl.Display,
        registry: *wl.Registry,

        compositor: ?*wl.Compositor = null,
        shm: ?*wl.Shm = null,
        wm_base: ?*Xdg.WmBase = null,
        surface: ?*wl.Surface = null,
        xdgsurface: ?*Xdg.Surface = null,
        toplevel: ?*Xdg.Toplevel = null,

        dmabuf: ?*Zwp.LinuxDmabufV1 = null,

        seat: ?*wl.Seat = null,
        pointer: ?*wl.Pointer = null,
        keyboard: ?*wl.Keyboard = null,

        pub fn roundtrip(w: *Wayland) !void {
            if (w.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        }
    };

    pub const Event = union(enum) {
        key: wl.Keyboard.Event,
        pointer: wl.Pointer.Event,
    };

    pub fn init(a: Allocator) !ZMenu {
        const display = try wl.Display.connect(null);
        const registry = try display.getRegistry();
        return .{
            .wayland = .{
                .display = display,
                .registry = registry,
            },
            .key_buffer = try .initCapacity(a, 100),
        };
    }

    pub fn initWayland(zm: *ZMenu) !void {
        zm.wayland.registry.setListener(*ZMenu, listeners.registry, zm);
        if (zm.wayland.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn initDmabuf(zm: *ZMenu) !void {
        const dmabuf = zm.wayland.dmabuf orelse return error.NoDMABUF;
        if (zm.wayland.surface) |surface| {
            const feedback = try dmabuf.getSurfaceFeedback(surface);
            std.debug.print("dma feedback {}\n", .{feedback});
        } else {
            const feedback = try dmabuf.getDefaultFeedback();
            std.debug.print("dma feedback {}\n", .{feedback});
        }
        // TODO implement listener/processor

        try zm.wayland.roundtrip();
    }

    /// I'm not a fan of this API either, but it lives here until I can decide
    /// where it belongs.
    pub fn wlEvent(zm: *ZMenu, event: Event) void {
        switch (event) {
            .key => |k| switch (k) {
                .key => |key| switch (key.state) {
                    .pressed => {
                        // todo bounds checking
                        if (zm.keymap.ascii(key.key)) |c| {
                            zm.key_buffer.appendAssumeCapacity(c);
                        } else switch (zm.keymap.ctrl(key.key)) {
                            .backspace => _ = zm.key_buffer.pop(),
                            else => {},
                        }
                    },
                    .released => {},
                    else => |unk| {
                        std.debug.print("unexpected keyboard key state {} \n", .{unk});
                    },
                },
                else => {},
            },
            .pointer => |_| {},
        }
    }

    pub fn end(zm: *ZMenu) void {
        zm.running = false;
    }

    pub fn configure(_: *ZMenu, evt: Xdg.Toplevel.Event) void {
        if (false) std.debug.print("toplevel conf {}\n", .{evt});
    }

    pub fn newKeymap(zm: *ZMenu, evt: wl.Keyboard.Event) void {
        if (false) std.debug.print("newKeymap {} {}\n", .{ evt.keymap.fd, evt.keymap.size });
        if (Keymap.initFd(evt.keymap.fd, evt.keymap.size)) |km| {
            zm.keymap = km;
        } else |_| {
            // TODO don't ignore error
        }
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var zm: ZMenu = try .init(alloc);
    try zm.initWayland();
    try zm.wayland.roundtrip();

    const size = 900;

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

    const shm = zm.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, size, size, "zmenu-buffer1");
    defer buffer.raze();
    const colors: Buffer = try .init(shm, size, size, "zmenu-buffer2");
    defer colors.buffer.destroy();
    try drawColors(size, buffer, colors);

    colors.drawRectangle(Buffer.ARGB, .xywh(50, 50, 50, 50), .green);
    colors.drawRectangleFill(Buffer.ARGB, .xywh(100, 75, 50, 50), .purple);
    colors.drawCircle(Buffer.ARGB, .xywh(200, 200, 50, 50), .purple);
    colors.drawCircle(Buffer.ARGB, .xywh(800, 100, 50, 50), .purple);

    colors.drawCircleFill(Buffer.ARGB, .xywh(300, 200, 50, 50), .purple);
    colors.drawCircleFill(Buffer.ARGB, .xywh(700, 100, 50, 50), .purple);

    colors.drawPoint(Buffer.ARGB, .xy(300, 200), .black);

    colors.drawCircleCentered(Buffer.ARGB, .radius(700, 100, 11), .cyan);
    colors.drawPoint(Buffer.ARGB, .xy(700, 100), .black);
    try zm.wayland.roundtrip();

    surface.attach(colors.buffer, 0, 0);
    surface.commit();
    try zm.wayland.roundtrip();

    //zm.wayland.toplevel.?.setMaxSize(size, size);

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(alloc, font);

    var glyph_cache: Glyph.Cache = .init(14);
    defer glyph_cache.raze(alloc);

    var i: usize = 0;
    var draw_count: usize = 0;
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
        if (zm.key_buffer.items.len != draw_count) {
            @branchHint(.unlikely);
            draw_count = zm.key_buffer.items.len;
            try drawBackground0(buffer, .wh(900, 300));
            try drawText(alloc, &glyph_cache, &buffer, zm.key_buffer.items, ttf, 50, 50);
            surface.attach(buffer.buffer, 0, 0);
            surface.damageBuffer(0, 0, size, 150);
            surface.commit();
        }
    }
}

fn drawText(
    alloc: Allocator,
    cache: *Glyph.Cache,
    buffer: *const Buffer,
    text: []const u8,
    ttf: Ttf,
    x: u32,
    y: u32,
) !void {
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

    for (tl.glyphs) |g| {
        const canvas, _ = (try cache.get(alloc, ttf, g.char)).*;
        buffer.drawFont(Buffer.ARGB, .black, .xywh(
            @intCast(@as(i32, @intCast(x)) + g.pixel_x1),
            @intCast(@as(i32, @intCast(y)) - g.pixel_y1),
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
    _ = &@import("Glyph.zig");
    _ = &listeners;
}

const Buffer = @import("Buffer.zig");
const LayoutHelper = @import("LayoutHelper.zig");
const Ttf = @import("ttf.zig");
const Glyph = @import("Glyph.zig");
const listeners = @import("listeners.zig").Listeners(ZMenu);
const Keymap = @import("Keymap.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
const Zwp = wayland.client.zwp;
