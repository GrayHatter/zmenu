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

        pub fn init(w: *Wayland, box: Buffer.Box) !void {
            const parent: *ZMenu = @fieldParentPtr("wayland", w);
            w.registry.setListener(*ZMenu, listeners.registry, parent);
            try w.roundtrip();

            const compositor = w.compositor orelse return error.NoWlCompositor;
            const wm_base = w.wm_base orelse return error.NoXdgWmBase;

            w.surface = try compositor.createSurface();
            w.xdgsurface = try wm_base.getXdgSurface(w.surface.?);
            w.toplevel = try w.xdgsurface.?.getToplevel(); //  orelse return error.NoToplevel;
            w.xdgsurface.?.setListener(*ZMenu, listeners.xdgSurfaceEvent, parent);
            w.toplevel.?.setListener(*ZMenu, listeners.xdgToplevelEvent, parent);
            w.toplevel.?.setMaxSize(@intCast(box.w), @intCast(box.h));
            w.toplevel.?.setMinSize(@intCast(box.w), @intCast(box.h));
            w.surface.?.commit();
            try w.roundtrip();
        }

        pub fn raze(w: *Wayland) void {
            if (w.toplevel) |tl| tl.destroy();
            if (w.xdgsurface) |s| s.destroy();
            if (w.surface) |s| s.destroy();
        }

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
            .key_buffer = try .initCapacity(a, 4096),
        };
    }

    pub fn raze(zm: *ZMenu, a: Allocator) void {
        zm.wayland.raze();
        zm.keymap.raze();
        zm.key_buffer.deinit(a);
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
                            .enter => {
                                if (zm.key_buffer.items.len > 0) {
                                    exec(zm.key_buffer.items) catch {};
                                }
                                zm.key_buffer.clearRetainingCapacity();
                            },

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

fn exec(cmd: []const u8) !noreturn {
    if (cmd[0] != '/') return error.InvalidArg0;
    std.process.execve(
        std.heap.page_allocator,
        &[1][]const u8{cmd},
        null,
    ) catch @panic("oopsies");
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var zm: ZMenu = try .init(alloc);
    const box: Buffer.Box = .wh(600, 180);

    try zm.wayland.init(box);
    defer zm.raze(alloc);

    const shm = zm.wayland.shm orelse return error.NoWlShm;
    const buffer: Buffer = try .init(shm, box, "zmenu-buffer1");
    defer buffer.raze();
    //try drawColors(size, buffer, colors);
    buffer.drawRectangleRoundedFill(Buffer.ARGB, box, 25, .alpha(.ash_gray, 0x8f));
    buffer.drawRectangleRoundedFill(Buffer.ARGB, .xywh(35, 30, 600 - 35 * 2, 40), 10, .ash_gray);
    buffer.drawRectangleRounded(Buffer.ARGB, .xywh(35, 30, 600 - 35 * 2, 40), 10, .hookers_green);
    buffer.drawRectangleRounded(Buffer.ARGB, .xywh(36, 31, 598 - 35 * 2, 38), 9, .hookers_green);

    try zm.wayland.roundtrip();

    const surface = zm.wayland.surface orelse return error.NoSurface;
    surface.attach(buffer.buffer, 0, 0);
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
    while (zm.running) : (i +%= 1) {
        switch (zm.wayland.display.dispatch()) {
            .SUCCESS => {},
            else => |w| {
                std.debug.print("wut {}\n", .{w});
                return error.DispatchFailed;
            },
        }
        if (i % 1000 == 0) {
            surface.attach(buffer.buffer, 0, 0);
            surface.damage(0, 0, @intCast(box.w), @intCast(box.h));
            surface.commit();
        }
        if (zm.key_buffer.items.len != draw_count) {
            @branchHint(.unlikely);
            draw_count = zm.key_buffer.items.len;
            //try drawBackground0(buffer, .wh(900, 300));
            if (draw_count > 0) {
                buffer.drawRectangleRoundedFill(Buffer.ARGB, .xywh(35, 30, 512 + 40, 40), 10, .ash_gray);
                buffer.drawRectangleRounded(Buffer.ARGB, .xywh(35, 30, 512 + 40, 40), 10, .hookers_green);
                buffer.drawRectangleRounded(Buffer.ARGB, .xywh(36, 31, 510 + 40, 38), 9, .hookers_green);
                try drawText(alloc, &glyph_cache, &buffer, zm.key_buffer.items, ttf, .xywh(45, 55, box.w - 80, box.h - 80));
            }
            surface.attach(buffer.buffer, 0, 0);
            surface.damageBuffer(0, 0, @intCast(box.w), @intCast(box.h));
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
