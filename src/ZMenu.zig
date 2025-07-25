charcoal: Charcoal,
running: bool = true,

const ZMenu = @This();

pub fn init() !ZMenu {
    return .{
        .charcoal = try .init(),
    };
}

pub fn connect(zm: *ZMenu) !void {
    try zm.charcoal.connect();
}

pub fn raze(zm: *ZMenu) void {
    zm.charcoal.raze();
}

pub fn iterate(zm: *ZMenu) !void {
    try zm.charcoal.iterate();
}

/// I'm not a fan of this API either, but it lives here until I can decide
/// where it belongs.
pub fn end(zm: *ZMenu) void {
    zm.running = false;
    zm.charcoal.running = false;
}

test "root" {
    _ = &std.testing.refAllDecls(@This());
    _ = &Ui;
    _ = &charcoal_;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

//const Buffer = @import("Buffer.zig");
//const Keymap = @import("Keymap.zig");
//const ui = @import("ui.zig");
const charcoal_ = @import("charcoal");
const Charcoal = charcoal_.Charcoal;
const Buffer = charcoal_.Buffer;
const Keymap = charcoal_.Keymap;
const Ui = charcoal_.Ui;
