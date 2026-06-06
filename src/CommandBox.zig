component: Ui.Component,
key_buffer: ArrayList(u8) = .empty,

const CommandBox = @This();

pub const new: CommandBox = .{ .component = .{ .vtable = .auto(CommandBox), .children = &.{} } };

pub const raze = null;
pub const mAxis = null;
pub const mClick = null;
pub const mMove = null;
pub const tick = null;

pub fn init(comp: *Ui.Component, _: Box, a: ?Allocator) !void {
    const cmd: *CommandBox = @fieldParentPtr("component", comp);
    cmd.key_buffer = try .initCapacity(a.?, 4096);
}

pub fn background(_: *Ui.Component, b: *Buffer, box: Box) void {
    var merge = box.add(.xywh(35, 30, -35 * 2, 40 - @as(isize, @intCast(box.h))));
    b.drawRectangleRoundedFill(ARGB, merge, 10, main.theme.rgb(ARGB, .background));
    b.drawRectangleRounded(ARGB, merge, 10, main.theme.rgb(ARGB, .primary));
    merge.merge(.vector(1));
    b.drawRectangleRounded(ARGB, merge, 9, main.theme.rgb(ARGB, .primary));
    merge.merge(.vector(1));
    b.drawRectangleRounded(ARGB, merge, 8, main.theme.rgb(ARGB, .primary));
    merge.merge(.vector(1));
    b.drawRectangleRounded(ARGB, merge, 7, main.theme.rgb(ARGB, .primary));
}

pub fn draw(comp: *Ui.Component, buffer: *Buffer, box: Box) void {
    defer comp.draw_needed = false;
    if (!comp.draw_needed) return;

    var merge: Box = .xywh(35, 30, 600 - 35 * 2, 40);
    merge.merge(.vector(3));
    buffer.drawRectangleRoundedFill(ARGB, merge, 6, main.theme.rgb(ARGB, .background));

    const cmd: *CommandBox = @fieldParentPtr("component", comp);
    if (cmd.key_buffer.items.len > 0) {
        drawing.text(
            buffer,
            cmd.key_buffer.items,
            .xywh(45, 55, box.w - 80, box.h - 80),
            main.theme.rgb(ARGB, .text),
        ) catch @panic("draw the textbox failed :<");
    }
}

pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
    defer comp.draw_needed = true;
    for (comp.children) |child| _ = child.keyPress(evt);

    if (evt.up) return false;
    const cmd: *CommandBox = @fieldParentPtr("component", comp);
    switch (evt.key) {
        .char => |chr| cmd.key_buffer.appendAssumeCapacity(chr),
        .ctrl => |ctrl| switch (ctrl) {
            .delete_word => {
                while (cmd.key_buffer.items.len > 0 and cmd.key_buffer.items[cmd.key_buffer.items.len - 1] == ' ') {
                    _ = cmd.key_buffer.pop();
                }
                while (cmd.key_buffer.items.len > 0 and cmd.key_buffer.items[cmd.key_buffer.items.len - 1] != ' ') {
                    _ = cmd.key_buffer.pop();
                }
            },
            .backspace => {
                _ = cmd.key_buffer.pop();
                return true;
            },
            .enter => {},
            .escape => {},
            else => {},
        },
        .focus => {},
    }
    return false;
}

const Charcoal = @import("charcoal");
const Buffer = Charcoal.Buffer;
const Box = Buffer.Box;
const Ui = Charcoal.Ui;
const ARGB = Buffer.ARGB;
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const drawing = @import("drawing.zig");
const main = @import("main.zig");
