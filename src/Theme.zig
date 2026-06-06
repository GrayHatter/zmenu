bg: u32,
text: u32,
p: u32,
s: u32,
t: u32,

bg_alpha: u8 = 0xef,

const Theme = @This();

pub fn Typed(Type: type) type {
    return struct {
        background: ?Type = null,
        text: ?Type = null,
        primary: ?Type = null,
        secondary: ?Type = null,
        tertiary: ?Type = null,
    };
}

pub const Color = enum(u32) {
    background,
    text,
    primary,
    secondary,
    tertiary,

    _,
};

pub fn init(T: type, bg: T, text: T, p: T, s: T, t: T) Theme {
    return .{
        .bg = @intFromEnum(bg),
        .text = @intFromEnum(text),
        .p = @intFromEnum(p),
        .s = @intFromEnum(s),
        .t = @intFromEnum(t),
    };
}

pub fn rgba(th: Theme, T: type, color: Color) T {
    return switch (color) {
        .background => .alpha(@enumFromInt(th.bg), th.bg_alpha),
        .text => .alpha(@enumFromInt(th.text), th.bg_alpha),
        .primary => .alpha(@enumFromInt(th.p), th.bg_alpha),
        .secondary => .alpha(@enumFromInt(th.s), th.bg_alpha),
        .tertiary => .alpha(@enumFromInt(th.t), th.bg_alpha),
        else => .alpha(@enumFromInt(@intFromEnum(color)), th.bg_alpha),
    };
}

pub fn rgb(th: Theme, T: type, color: Color) T {
    return switch (color) {
        .background => @enumFromInt(th.bg),
        .text => @enumFromInt(th.text),
        .primary => @enumFromInt(th.p),
        .secondary => @enumFromInt(th.s),
        .tertiary => @enumFromInt(th.t),
        else => @enumFromInt(@intFromEnum(color)),
    };
}
