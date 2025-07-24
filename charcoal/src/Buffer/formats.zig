pub const ARGB = enum(u32) {
    transparent = 0x00000000,
    white = 0xffffffff,
    black = 0xff000000,
    red = 0xffff0000,
    green = 0xff00ff00,
    blue = 0xff0000ff,
    purple = 0xffaa11ff, // I *feel* like this is more purpley
    cyan = 0xff00ffff,

    bittersweet_shimmer = 0xffbc4749,
    parchment = 0xfff2e8cf,

    ash_gray = 0xffcad2c5,
    cambridge_blue = 0xff84a98c,
    hookers_green = 0xff52796f,
    dark_slate_gray = 0xff354f52,
    charcoal = 0xff2f3e46,

    _,

    pub const MASK = struct {
        pub const A = 0xff000000;
        pub const R = 0x00ff0000;
        pub const G = 0x0000ff00;
        pub const B = 0x000000ff;
    };

    pub const SHIFT = struct {
        pub const A = 0x18;
        pub const R = 0x10;
        pub const G = 0x08;
        pub const B = 0x00;
    };

    pub fn rgb(r: u8, g: u8, b: u8) ARGB {
        const color: u32 = (0xff000000 |
            @as(u32, r) << SHIFT.R |
            @as(u32, g) << SHIFT.G |
            @as(u32, b) << SHIFT.B);

        return @enumFromInt(color);
    }

    pub fn int(color: ARGB) u32 {
        return @intFromEnum(color);
    }

    pub fn hex(i: u32) ARGB {
        return @enumFromInt(i);
    }

    pub fn fromBytes(bytes: [4]u8) ARGB {
        return @enumFromInt(@as(*align(1) const u32, @ptrCast(&bytes)).*);
    }

    pub fn alpha(src: ARGB, trans: u8) ARGB {
        const color: u32 = @intFromEnum(src);
        const mask: u32 = 0x00ffffff | (@as(u32, trans) << 24);
        return @enumFromInt(color & mask);
    }

    pub fn mix(src: ARGB, dest: *u32) void {
        const alp: u32 = (src.int() & MASK.A) >> SHIFT.A;
        const red: u32 = (src.int() & MASK.R) >> SHIFT.R;
        const gre: u32 = (src.int() & MASK.G) >> SHIFT.G;
        const blu: u32 = (src.int() & MASK.B) >> SHIFT.B;

        const r: u32 = (dest.* & MASK.R) >> SHIFT.R;
        const g: u32 = (dest.* & MASK.G) >> SHIFT.G;
        const b: u32 = (dest.* & MASK.B) >> SHIFT.B;

        //aOut = aA + (aB * (255 - aA) / 255);
        const color: u32 = 0xff000000 |
            (((red * alp + r * (0xff - alp)) / (0xff * 1)) << 0x10 & MASK.R) |
            (((gre * alp + g * (0xff - alp)) / (0xff * 1)) << 0x08 & MASK.G) |
            (((blu * alp + b * (0xff - alp)) / (0xff * 1)) << 0x00 & MASK.B);
        dest.* = color;
    }
};

pub const BGRA = enum(u32) {
    transparent = 0x00000000,
    white = 0xffffffff,
    black = 0x000000ff,
    _,

    pub fn rgb(r: u8, g: u8, b: u8) ARGB {
        comptime unreachable; // wrong shifts
        const color: u32 = (0xff000000 |
            @as(u32, r) << 16 |
            @as(u32, g) << 8 |
            @as(u32, b));

        return @enumFromInt(color);
    }
    pub fn int(color: BGRA) u32 {
        return @intFromEnum(color);
    }

    pub fn fromBytes(bytes: [4]u8) BGRA {
        return @enumFromInt(@as(*align(1) const u32, @ptrCast(&bytes)).*);
    }
};
