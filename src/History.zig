component: Ui.Component,
alloc: Allocator = undefined,
cursor_idx: usize = 0,
limit: usize = 10,
drawn: usize = 0,
found: usize = 0,

const History = @This();

pub const background = null;
pub const mAxis = null;
pub const mClick = null;
pub const mMove = null;
pub const tick = null;

pub fn init(_: *Ui.Component, _: Buffer.Box, _: ?Allocator) Ui.Component.InitError!void {
    //const options: *History = try a.?.create(History);
}

pub fn raze(comp: *Ui.Component, a: ?Allocator) void {
    const h: *History = @fieldParentPtr("component", comp);
    a.?.destroy(h);
}

pub fn draw(comp: *Ui.Component, buffer: *Buffer, box: Buffer.Box) void {
    const h: *History = @fieldParentPtr("component", comp);

    const drawn, const found = drawHistory(
        h.alloc,
        buffer,
        h.cursor_idx,
        h.limit,
        main.command_history,
        main.ui_key_buffer.items,
        box,
    ) catch @panic("drawing failed");
    h.drawn = drawn;
    h.found = found;
    comp.draw_needed = false;
}

pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
    const histopt: *History = @fieldParentPtr("component", comp);
    if (evt.up) return false;
    comp.draw_needed = true;
    switch (evt.key) {
        .ctrl => |ctrl| {
            switch (ctrl) {
                .arrow_up => histopt.cursor_idx -|= 1,
                .arrow_down => histopt.cursor_idx +|= 1,
                .tab => {
                    if (evt.mods.shift)
                        histopt.cursor_idx -|= 1
                    else
                        histopt.cursor_idx +|= 1;
                },
                .delete => {
                    if (evt.mods.shift and evt.mods.ctrl and
                        histopt.cursor_idx <= histopt.drawn and histopt.cursor_idx > 0)
                    {
                        histopt.deleteHistoryLine();
                    }
                },
                else => return false,
            }
            comp.draw_needed = true;
            return true;
        },
        else => {},
    }
    //std.debug.print("exec keyevent {}\n", .{evt});
    return false;
}

fn deleteHistoryLine(hist: *History) void {
    var idx: usize = 0;
    for (main.command_history) |*cmd| {
        const str = main.ui_key_buffer.items;
        if (cmd.match(str)) {
            idx += 1;
            if (idx == hist.cursor_idx) {
                std.debug.print("deleting this history row '{s}'\n", .{cmd.text});
                cmd.count = 0;
                main.write_history = true;
                break;
            }
        }
    }
}

fn drawHistory(
    a: Allocator,
    buf: *Buffer,
    highlighted: usize,
    limit: usize,
    cmds: []main.Command,
    prefix: []const u8,
    box: Buffer.Box,
) !struct { usize, usize } {
    //buf.drawRectangleFill(ARGB, box.add(.xy(-5, 0)), theme.rgba(ARGB, .background));
    var drawn: usize = 0;
    var found: usize = 0;
    for (cmds) |cmd| {
        const y = box.y + 20 + 20 * (drawn);
        if (cmd.match(prefix)) {
            found += 1;
            if (drawn >= limit) continue;
            try drawing.text(
                a,
                &main.glyph_cache,
                buf,
                cmd.text,
                .xywh(box.x + 5, y, box.w, 25),
                main.theme.rgb(ARGB, .text),
            );
            drawn += 1;
            if (drawn == highlighted) {
                buf.drawRectangleRounded(
                    ARGB,
                    .xywh(box.x, y - 19, box.w, 25),
                    10,
                    main.theme.rgb(ARGB, .primary),
                );
                buf.drawRectangleRounded(
                    ARGB,
                    .xywh(box.x + 1, y - 18, box.w - 2, 25 - 2),
                    9,
                    main.theme.rgb(ARGB, .primary),
                );
            }
        }
    }
    return .{ drawn, found };
}

pub fn getExec(hist: *History, str: []const u8) ?[]const u8 {
    var idx: usize = 0;
    if (hist.cursor_idx > main.command_history.len) return null;
    for (main.command_history) |cmd| {
        if (cmd.match(str)) {
            idx += 1;
            if (idx == hist.cursor_idx) {
                return cmd.text;
            }
        }
    }
    return null;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Charcoal = @import("charcoal");
const Buffer = Charcoal.Buffer;
const Ui = Charcoal.Ui;
const ARGB = Buffer.ARGB;

const main = @import("main.zig");
const drawing = @import("drawing.zig");
