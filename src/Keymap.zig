data: ?[]const u8 = null,

const Keymap = @This();

pub const Control = enum(u16) {
    escape = 1,
    shift_left = 42,
    shift_right = 54,
    backspace = 14,
    enter = 28,
    meta = 125,
    ascii_char,

    UNKNOWN = 0,
};

pub fn init() Keymap {
    return .{};
}

pub fn initFd(fd: anytype, size: u32) !Keymap {
    const data = std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch unreachable;

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

pub fn ascii(_: Keymap, key: u32) ?u8 {
    return switch (key) {
        40 => '\'',
        51 => ',',
        52 => '.',
        25 => 'p',
        21 => 'y',
        33 => 'f',
        34 => 'g',
        46 => 'c',
        19 => 'r',
        38 => 'l',
        30 => 'a',
        24 => 'o',
        18 => 'e',
        22 => 'u',
        57 => ' ',
        23 => 'i',
        32 => 'd',
        35 => 'h',
        20 => 't',
        49 => 'n',
        31 => 's',
        39 => ';',
        53 => '/',
        13 => '=',
        12 => '-',
        16 => 'q',
        36 => 'j',
        37 => 'k',
        45 => 'x',
        48 => 'b',
        50 => 'm',
        17 => 'w',
        47 => 'v',
        44 => 'z',
        2 => '1',
        3 => '2',
        4 => '3',
        5 => '4',
        6 => '5',
        7 => '6',
        8 => '7',
        9 => '8',
        10 => '9',
        11 => '0',
        42 => null, // Left Shift
        54 => null, // Right Shift
        14 => null, // Backspace
        28 => null, // Enter
        125 => null, // Meta
        1 => null, // Escape
        else => {
            std.debug.print("Unable to translate ascii {}\n", .{key});
            return null;
        },
    };
}

pub fn ctrl(_: Keymap, key: u32) Control {
    return switch (key) {
        2...11 => .ascii_char,
        42 => .shift_left, // Left Shift
        54 => .shift_right, // Right Shift
        14 => .backspace, // Backspace
        28 => .enter, // Enter
        125 => .meta, // Meta
        1 => .escape,
        else => {
            std.debug.print("Unable to translate  ctrl {}\n", .{key});
            return .UNKNOWN;
        },
    };
}

const std = @import("std");
