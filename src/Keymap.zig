data: ?[]const u8 = null,

const Keymap = @This();

pub const Control = enum(u16) {
    escape = 1,
    ctrl_left = 29,
    shift_left = 42,
    shift_right = 54,
    backspace = 14,
    enter = 28,
    meta = 125,

    arrow_up = 103,
    arrow_down = 108,
    arrow_left = 105,
    arrow_right = 106,
    tab = 15,

    ascii_char,

    UNKNOWN = 0,
};

pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,

    pub fn init(code: u32) Modifiers {
        return .{
            .shift = code & 1 > 0,
            .ctrl = code & 4 > 0,
            .alt = code & 8 > 0,
        };
    }
};

pub fn init() Keymap {
    return .{};
}

pub fn initFd(fd: anytype, size: u32) !Keymap {
    const prot = std.posix.PROT.READ | std.posix.PROT.WRITE;
    const data = std.posix.mmap(null, size, prot, .{ .TYPE = .PRIVATE }, fd, 0) catch unreachable;

    if (false) std.debug.print("{s}\n", .{data});
    _ = try parse(data);
    return .{
        .data = data,
    };
}

pub fn raze(k: Keymap) void {
    if (k.data) |d| std.posix.munmap(@alignCast(d));
}

fn parse(_: []const u8) !void {
    // lol you thought
    return error.NotImplemented;
}

pub fn ascii(_: Keymap, key: u32, mods: Modifiers) ?u8 {
    const code: [4]?u8 = switch (key) {
        40 => .{ '\'', '"', '\'', '\'' },
        51 => .{ ',', '<', ',', ',' },
        52 => .{ '.', '>', '.', '.' },
        25 => .{ 'p', 'P', 'p', 'p' },
        21 => .{ 'y', 'Y', 'y', 'y' },
        33 => .{ 'f', 'F', 'f', 'f' },
        34 => .{ 'g', 'G', 'g', 'g' },
        46 => .{ 'c', 'C', 'c', 'c' },
        19 => .{ 'r', 'R', 'r', 'r' },
        38 => .{ 'l', 'L', 'l', 'l' },
        30 => .{ 'a', 'A', 'a', 'a' },
        24 => .{ 'o', 'O', 'o', 'o' },
        18 => .{ 'e', 'E', 'e', 'e' },
        22 => .{ 'u', 'U', 'u', 'u' },
        57 => .{ ' ', ' ', ' ', ' ' },
        23 => .{ 'i', 'I', 'i', 'i' },
        32 => .{ 'd', 'D', 'd', 'd' },
        35 => .{ 'h', 'H', 'h', 'h' },
        20 => .{ 't', 'T', 't', 't' },
        49 => .{ 'n', 'N', 'n', 'n' },
        31 => .{ 's', 'S', 's', 's' },
        39 => .{ ';', ':', ';', ';' },
        53 => .{ '/', '|', '/', '/' },
        13 => .{ '=', '+', '=', '=' },
        12 => .{ '-', '_', '-', '-' },
        16 => .{ 'q', 'Q', 'q', 'q' },
        36 => .{ 'j', 'J', 'j', 'j' },
        37 => .{ 'k', 'K', 'k', 'k' },
        45 => .{ 'x', 'X', 'x', 'x' },
        48 => .{ 'b', 'B', 'b', 'b' },
        50 => .{ 'm', 'M', 'm', 'm' },
        17 => .{ 'w', 'W', null, 'w' },
        47 => .{ 'v', 'V', 'v', 'v' },
        44 => .{ 'z', 'Z', 'z', 'z' },
        2 => .{ '1', '!', '1', '1' },
        3 => .{ '2', '@', '2', '2' },
        4 => .{ '3', '#', '3', '3' },
        5 => .{ '4', '$', '4', '4' },
        6 => .{ '5', '%', '5', '5' },
        7 => .{ '6', '^', '6', '6' },
        8 => .{ '7', '&', '7', '7' },
        9 => .{ '8', '*', '8', '8' },
        10 => .{ '9', '(', '9', '9' },
        11 => .{ '0', ')', '0', '0' },

        15 => .{ null, null, null, null }, // Tab,
        42 => .{ null, null, null, null }, // Left Shift,
        54 => .{ null, null, null, null }, // Right Shift,
        29 => .{ null, null, null, null }, // Left Ctrl,
        97 => .{ null, null, null, null }, // Right Ctrl,
        56 => .{ null, null, null, null }, // Left Alt,
        14 => .{ null, null, null, null }, // Backspace,
        28 => .{ null, null, null, null }, // Enter,
        125 => .{ null, null, null, null }, // Meta,
        103 => .{ null, null, null, null }, // Up,
        108 => .{ null, null, null, null }, // Down,
        105 => .{ null, null, null, null }, // Left,
        106 => .{ null, null, null, null }, // Right,
        1 => .{ null, null, null, null }, //
        else => {
            std.debug.print("Unable to translate ascii {}\n", .{key});
            return null;
        },
    };
    return if (mods.shift)
        code[1]
    else if (mods.ctrl)
        code[2]
    else if (mods.alt)
        code[3]
    else
        code[0];
}

pub fn ctrl(_: Keymap, key: u32) Control {
    return switch (key) {
        2...11 => .ascii_char,
        29 => .ctrl_left,
        42 => .shift_left, // Left Shift
        54 => .shift_right, // Right Shift
        14 => .backspace, // Backspace
        28 => .enter, // Enter
        125 => .meta, // Meta
        1 => .escape,
        103 => .arrow_up,
        108 => .arrow_down,
        105 => .arrow_left,
        106 => .arrow_right,
        15 => .tab,
        else => {
            std.debug.print("Unable to translate  ctrl {}\n", .{key});
            return .UNKNOWN;
        },
    };
}

const std = @import("std");
