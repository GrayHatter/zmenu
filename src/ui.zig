pub const Component = struct {
    vtable: VTable,
    box: Buffer.Box = undefined,
    state: *anyopaque = undefined,
    children: []Component,

    pub fn init(comp: *Component, a: Allocator, box: Buffer.Box) InitError!void {
        if (comp.vtable.init) |func| try func(comp, a, box);
        for (comp.children) |*child| try child.init(a, box);
    }

    pub fn raze(comp: *Component, a: Allocator) void {
        if (comp.vtable.raze) |raze_| raze_(comp, a);
        for (comp.children) |*child| child.raze(a);
    }

    pub fn background(comp: *Component, buffer: *const Buffer, box: Buffer.Box) void {
        if (comp.vtable.background) |bg| bg(comp, buffer, box);
        for (comp.children) |*child| child.background(buffer, box);
    }

    pub fn draw(comp: *Component, buffer: *const Buffer, box: Buffer.Box) bool {
        if (comp.vtable.draw) |draw_| _ = draw_(comp, buffer, box);
        for (comp.children) |*child| _ = child.draw(buffer, box);

        return false;
    }

    pub fn keyPress(comp: *Component, evt: KeyEvent, box: Buffer.Box) bool {
        if (comp.vtable.keypress) |kp| kp(comp, evt, box);
        for (comp.children) |*child| child.keyPress(evt, box);

        return false;
    }

    pub fn mMove(comp: *Component, mmove: Mouse.Movement, box: Buffer.Box) void {
        if (comp.vtable.mmove) |mmove_| mmove_(comp, mmove, box);
        for (comp.children) |*child| background(child, mmove, box);
    }

    pub fn mClick(comp: *Component, mclick: Mouse.Click, box: Buffer.Box) bool {
        if (comp.vtable.mclick) |mclick_| mclick_(comp, mclick, box);
        for (comp.children) |*child| background(child, mclick, box);

        return false;
    }
};

pub const VTable = struct {
    init: ?Init,
    raze: ?Raze,
    background: ?Background,
    draw: ?Draw,
    keypress: ?KeyPress,
    mmove: ?MMove,
    mclick: ?MClick,
};

pub const Init = *const fn (*Component, Allocator, Buffer.Box) InitError!void;
pub const Raze = *const fn (*Component, Allocator) void;
pub const Background = *const fn (*Component, *const Buffer, Buffer.Box) void;
pub const Draw = *const fn (*Component, *const Buffer, Buffer.Box) bool;
pub const KeyPress = *const fn (*Component, KeyEvent) bool;
pub const MMove = *const fn (*Component, Mouse.Movement) void;
pub const MClick = *const fn (*Component, Mouse.Click) bool;

pub const InitError = error{
    OutOfMemory,
    UnableToInit,
};

pub const KeyEvent = struct {
    up: bool,
    key: union(enum) {
        char: u8,
        ctrl: Keymap.Control,
    },
    mods: Keymap.Modifiers,
};

pub const Mouse = struct {
    pub const Movement = struct {
        up: bool,
        x: isize,
        y: isize,
        mods: Keymap.Modifiers,
    };
    pub const Click = struct {
        up: bool,
        button: Button,
        x: isize,
        y: isize,
        mods: Keymap.Modifiers,
    };
    pub const Button = u8;
};

const Allocator = @import("std").mem.Allocator;
const Keymap = @import("Keymap.zig");
const Buffer = @import("Buffer.zig");
