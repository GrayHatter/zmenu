const debug_wl = false;

const Wayland = @import("charcoal.zig").Wayland;
const Ui = @import("charcoal.zig").Ui;

pub const Listeners = struct {
    pub fn registry(r: *wl.Registry, event: wl.Registry.Event, ptr: *Wayland) void {
        switch (event) {
            .global => |global| {
                if (orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                    ptr.compositor = r.bind(global.name, wl.Compositor, @min(global.version, wl.Compositor.generated_version)) catch return;
                } else if (orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                    ptr.output = r.bind(global.name, wl.Output, @min(global.version, wl.Output.generated_version)) catch return;
                    ptr.output.?.setListener(*Wayland, outputEvent, ptr);
                } else if (orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                    ptr.shm = r.bind(global.name, wl.Shm, @min(global.version, wl.Shm.generated_version)) catch return;
                } else if (orderZ(u8, global.interface, Xdg.WmBase.interface.name) == .eq) {
                    ptr.wm_base = r.bind(global.name, Xdg.WmBase, @min(global.version, Xdg.WmBase.generated_version)) catch return;
                } else if (orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                    ptr.seat = r.bind(global.name, wl.Seat, @min(global.version, wl.Seat.generated_version)) catch return;
                    ptr.seat.?.setListener(*Wayland, seatEvent, ptr);
                } else if (orderZ(u8, global.interface, Zwp.LinuxDmabufV1.interface.name) == .eq) {
                    ptr.dmabuf = r.bind(global.name, Zwp.LinuxDmabufV1, @min(global.version, Zwp.LinuxDmabufV1.generated_version)) catch return;
                    ptr.dmabuf.?.setListener(*Wayland, dmabufEvent, ptr);
                } else {
                    if (debug_wl) std.debug.print("extra global {s}\n", .{global.interface});
                }
            },
            .global_remove => {},
        }
    }

    fn outputEvent(_: *wl.Output, event: wl.Output.Event, _: *Wayland) void {
        if (debug_wl) switch (event) {
            .geometry => |geo| {
                std.debug.print("geo {}\n", .{geo});
                std.debug.print("    make {s}\n", .{std.mem.span(geo.make)});
                std.debug.print("    model {s}\n", .{std.mem.span(geo.model)});
            },
            .mode => |mode| {
                std.debug.print("    mode {}\n", .{mode.flags});
                std.debug.print("    width {}\n", .{mode.width});
                std.debug.print("    height {}\n", .{mode.height});
                std.debug.print("    refresh {}\n", .{mode.refresh});
            },
            .scale => |scale| std.debug.print("    scale {}\n", .{scale.factor}),
            .name => |nameZ| std.debug.print("    name {s}\n", .{std.mem.span(nameZ.name)}),
            .description => |descZ| std.debug.print("    description {s}\n", .{std.mem.span(descZ.description)}),
            .done => std.debug.print("done\n", .{}),
        };
    }

    pub fn xdgSurfaceEvent(xdg_surface: *Xdg.Surface, event: Xdg.Surface.Event, _: *Wayland) void {
        switch (event) {
            .configure => |configure| xdg_surface.ackConfigure(configure.serial),
        }
    }

    pub fn xdgToplevelEvent(_: *Xdg.Toplevel, event: Xdg.Toplevel.Event, ptr: *Wayland) void {
        switch (event) {
            .close => ptr.quit(),
            .configure_bounds, .wm_capabilities, .configure => ptr.configure(event),
        }
    }

    fn dmabufEvent(_: *Zwp.LinuxDmabufV1, evt: Zwp.LinuxDmabufV1.Event, _: *Wayland) void {
        // Only sent in version 1
        switch (evt) {
            .format => |format| {
                // /include/uapi/drm/drm_fourcc.h
                const a: u8 = @truncate(format.format & 0xff);
                const b: u8 = @truncate((format.format >> 8) & 0xff);
                const c: u8 = @truncate((format.format >> 16) & 0xff);
                const d: u8 = @truncate((format.format >> 24) & 0xff);
                std.debug.print("dma format {} '{c}:{c}:{c}:{c}'\n", .{ format.format, a, b, c, d });
            },
            .modifier => |mod| {
                std.debug.print("dma modifier {}\n", .{mod});
            },
        }
    }

    fn seatEvent(s: *wl.Seat, evt: wl.Seat.Event, ptr: *Wayland) void {
        switch (evt) {
            .capabilities => |cap| {
                if (cap.capabilities.pointer) {
                    ptr.hid.pointer = s.getPointer() catch return;
                    ptr.hid.pointer.?.setListener(*Ui, pointerEvent, ptr.getUi());
                }
                if (cap.capabilities.keyboard) {
                    ptr.hid.keyboard = s.getKeyboard() catch return;
                    ptr.hid.keyboard.?.setListener(*Ui, keyEvent, ptr.getUi());
                }
            },
            .name => |name| if (debug_wl) std.debug.print("name {s}\n", .{std.mem.span(name.name)}),
        }
    }

    fn keyEvent(_: *wl.Keyboard, evt: wl.Keyboard.Event, ptr: *Ui) void {
        switch (evt) {
            .key, .modifiers, .enter, .leave => ptr.event(.{ .key = evt }),
            .keymap => ptr.newKeymap(evt),
            //.repeat_info => {},
            else => {
                if (debug_wl) std.debug.print("keyevent other {}\n", .{evt});
            },
        }
    }

    fn pointerEvent(_: *wl.Pointer, evt: wl.Pointer.Event, ptr: *Ui) void {
        switch (evt) {
            .enter => |enter| {
                if (debug_wl) std.debug.print(
                    "ptr enter x {d: <8} y {d: <8}\n",
                    .{ enter.surface_x.toInt(), enter.surface_y.toInt() },
                );
                ptr.event(.{ .pointer = evt });
            },
            .leave => |leave| if (debug_wl) std.debug.print("ptr leave {}\n", .{leave}),
            .motion => |motion| {
                if (debug_wl) std.debug.print(
                    "mm        x {d: <8} y {d: <8}\n",
                    .{ motion.surface_x.toInt(), motion.surface_y.toInt() },
                );
                ptr.event(.{ .pointer = evt });
            }, //std.debug.print("pointer {}\n", .{t}),{},
            .button => |button| {
                if (debug_wl) std.debug.print("pointer press {}\n", .{button});
                ptr.event(.{ .pointer = evt });
            },
            .axis => |axis| {
                switch (axis.axis) {
                    .vertical_scroll => {},
                    .horizontal_scroll => {},
                    else => {
                        std.debug.print("pointer axis {}\n", .{axis});
                    },
                }
                ptr.event(.{ .pointer = evt });
            },
        }
    }
};

const std = @import("std");
const orderZ = std.mem.orderZ;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
const Zwp = wayland.client.zwp;
