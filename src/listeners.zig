pub fn Listeners(T: type) type {
    return struct {
        pub fn registry(r: *wl.Registry, event: wl.Registry.Event, zm: *T) void {
            switch (event) {
                .global => |global| {
                    if (orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                        zm.wayland.compositor = r.bind(global.name, wl.Compositor, 1) catch return;
                    } else if (orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                        zm.wayland.shm = r.bind(global.name, wl.Shm, 1) catch return;
                    } else if (orderZ(u8, global.interface, Xdg.WmBase.interface.name) == .eq) {
                        zm.wayland.wm_base = r.bind(global.name, Xdg.WmBase, 1) catch return;
                    } else if (orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                        zm.wayland.seat = r.bind(global.name, wl.Seat, 1) catch return;
                        zm.wayland.seat.?.setListener(*T, seat, zm);
                    }
                },
                .global_remove => {},
            }
        }

        pub fn xdgSurface(xdg_surface: *Xdg.Surface, event: Xdg.Surface.Event, _: *T) void {
            switch (event) {
                .configure => |configure| xdg_surface.ackConfigure(configure.serial),
            }
        }

        pub fn xdgToplevel(_: *Xdg.Toplevel, event: Xdg.Toplevel.Event, zm: *T) void {
            switch (event) {
                .configure => zm.configure(event),
                .close => zm.end(),
                .configure_bounds => |bounds| std.debug.print("toplevel bounds {}\n", .{bounds}),
                .wm_capabilities => |caps| {
                    std.debug.print("toplevel caps {}\n", .{caps});
                },
            }
        }

        fn seat(s: *wl.Seat, evt: wl.Seat.Event, zm: *T) void {
            switch (evt) {
                .capabilities => |cap| {
                    if (cap.capabilities.pointer) {
                        zm.wayland.pointer = s.getPointer() catch return;
                        zm.wayland.pointer.?.setListener(*T, pointer, zm);
                    }
                    if (cap.capabilities.keyboard) {
                        zm.wayland.keyboard = s.getKeyboard() catch return;
                        zm.wayland.keyboard.?.setListener(*T, key_, zm);
                    }
                },
                .name => |name| std.debug.print("name {s}\n", .{std.mem.span(name.name)}),
            }
        }

        fn key_(_: *wl.Keyboard, evt: wl.Keyboard.Event, zm: *T) void {
            switch (evt) {
                .key => |key| switch (key.key) {
                    1 => zm.end(),
                    else => zm.wlEvent(.{ .key = evt }),
                },
                .keymap => zm.newKeymap(evt),
                .modifiers => |mods| {
                    if (mods.mods_depressed > 0) {
                        //std.debug.print("keymods {}\n", .{mods});
                    }
                },
                .enter => {},
                .leave => {},
                //.repeat_info => {},
                else => {
                    std.debug.print("keyevent other {}\n", .{evt});
                },
            }
        }

        fn pointer(_: *wl.Pointer, evt: wl.Pointer.Event, zm: *T) void {
            switch (evt) {
                .enter => |enter| {
                    std.debug.print(
                        "ptr enter x {d: <8} y {d: <8}\n",
                        .{ enter.surface_x.toInt(), enter.surface_y.toInt() },
                    );
                },
                .leave => |leave| std.debug.print("ptr leave {}\n", .{leave}),
                .motion => |motion| {
                    if (false) std.debug.print(
                        "mm        x {d: <8} y {d: <8}\n",
                        .{ motion.surface_x.toInt(), motion.surface_y.toInt() },
                    );
                }, //std.debug.print("pointer {}\n", .{t}),{},
                .button => |button| {
                    std.debug.print("pointer press {}\n", .{button});
                    if (button.state == .pressed) {
                        zm.wayland.toplevel.?.move(zm.wayland.seat.?, button.serial);
                    }
                },
                .axis => |axis| {
                    switch (axis.axis) {
                        .vertical_scroll => {},
                        .horizontal_scroll => {},
                        else => {
                            std.debug.print("pointer axis {}\n", .{axis});
                        },
                    }
                },
            }
        }
    };
}

const std = @import("std");
const orderZ = std.mem.orderZ;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
