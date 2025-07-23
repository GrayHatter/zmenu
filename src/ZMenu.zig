wayland: Wayland,
keymap: Keymap = .{},
running: bool = true,

ui_root: ?*ui.Component = null,

const ZMenu = @This();

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
    hid: struct {
        pointer: ?*wl.Pointer = null,
        keyboard: ?*wl.Keyboard = null,
        mods: u32 = 0,
    } = .{},

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

        w.resize(box) catch {
            // Resizing is optional, but the round trip is not
            try w.roundtrip();
        };
    }

    pub fn raze(w: *Wayland) void {
        if (w.toplevel) |tl| tl.destroy();
        if (w.xdgsurface) |s| s.destroy();
        if (w.surface) |s| s.destroy();
    }

    pub fn roundtrip(w: *Wayland) !void {
        if (w.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn iterate(w: *Wayland) !void {
        switch (w.display.dispatch()) {
            .SUCCESS => {},
            else => |wut| {
                std.debug.print("Wayland Dispatch failed {}\n", .{wut});
            },
        }
    }

    pub fn resize(w: *Wayland, box: Buffer.Box) !void {
        if (w.toplevel) |tl| {
            tl.setMaxSize(@intCast(box.w), @intCast(box.h));
            tl.setMinSize(@intCast(box.w), @intCast(box.h));
        }
        if (w.surface) |s| s.commit();
        try w.roundtrip();
    }
};

pub const Event = union(enum) {
    key: wl.Keyboard.Event,
    pointer: wl.Pointer.Event,
};

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

pub fn raze(zm: *ZMenu) void {
    zm.wayland.raze();
    zm.keymap.raze();
}

pub fn iterate(zm: *ZMenu) !void {
    try zm.wayland.iterate();
    if (zm.ui_root) |uiroot| {
        uiroot.tick();
    }
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
    const debug_events = false;
    switch (event) {
        .key => |k| switch (k) {
            .key => |key| {
                switch (key.state) {
                    .pressed => {},
                    .released => {},
                    else => |unk| {
                        if (debug_events) std.debug.print("unexpected keyboard key state {} \n", .{unk});
                    },
                }
                const uiroot = zm.ui_root orelse return;
                const mods: Keymap.Modifiers = .init(zm.wayland.hid.mods);
                _ = uiroot.keyPress(.{
                    .up = key.state == .released,
                    .key = if (zm.keymap.ascii(key.key, mods)) |asc|
                        .{ .char = asc }
                    else
                        .{ .ctrl = zm.keymap.ctrl(key.key) },
                    .mods = mods,
                });
            },
            .modifiers => {
                zm.wayland.hid.mods = k.modifiers.mods_depressed;
                if (debug_events) std.debug.print("mods {}\n", .{k.modifiers});
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
    const debug = false;
    switch (evt) {
        .configure => |conf| if (debug) std.debug.print("toplevel conf {}\n", .{conf}),
        .configure_bounds => |bounds| if (debug) std.debug.print("toplevel bounds {}\n", .{bounds}),
        .wm_capabilities => |caps| if (debug) std.debug.print("toplevel caps {}\n", .{caps}),
        .close => unreachable,
    }
}

pub fn newKeymap(zm: *ZMenu, evt: wl.Keyboard.Event) void {
    if (false) std.debug.print("newKeymap {} {}\n", .{ evt.keymap.fd, evt.keymap.size });
    if (Keymap.initFd(evt.keymap.fd, evt.keymap.size)) |km| {
        zm.keymap = km;
    } else |_| {
        // TODO don't ignore error
    }
}

test {
    _ = &listeners;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("Buffer.zig");
const Keymap = @import("Keymap.zig");
const ui = @import("ui.zig");

const listeners = @import("listeners.zig").Listeners(ZMenu);

const wayland_ = @import("wayland");
const wl = wayland_.client.wl;
const Xdg = wayland_.client.xdg;
const Zwp = wayland_.client.zwp;
