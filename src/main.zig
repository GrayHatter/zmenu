pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var zm: ZMenu = try .init();

    const box: Buffer.Box = .wh(600, 300);
    try zm.connect();
    try zm.charcoal.wayland.resize(box);
    defer zm.raze();
    root_zmenu = &zm;

    const shm = zm.charcoal.wayland.shm orelse return error.NoWlShm;
    var buffer: Buffer = try .initCapacity(shm, .wh(600, 800), .wh(600, 2000), "zmenu-buffer1");
    defer buffer.raze();

    var root: Ui.Component = .{
        .vtable = .auto(UiRoot),
        .box = box,
        .children = &UiRoot.ui_children,
    };
    try zm.charcoal.ui.init(&root, alloc, box);
    defer zm.charcoal.ui.raze(alloc);

    root.background(&buffer, box);
    const surface = zm.charcoal.wayland.surface orelse return error.NoSurface;
    surface.attach(buffer.buffer, 0, 0);
    surface.commit();
    try zm.charcoal.wayland.roundtrip();

    try buffer.resize(.wh(600, 300));
    try zm.charcoal.wayland.roundtrip();

    const home_dir: std.fs.Dir = h: {
        for (std.os.environ) |envZ| {
            const env = std.mem.span(envZ);
            if (std.mem.startsWith(u8, env, "HOME=")) {
                if (env[5..].len == 0) continue;
                if (std.fs.openDirAbsolute(env[5..], .{})) |dir| {
                    break :h dir;
                } else |err| {
                    std.debug.print(
                        "Unable to open home dir specified by $HOME '{s}' error {}\n",
                        .{ env[5..], err },
                    );
                    break :h std.fs.cwd();
                }
            }
        }
        break :h std.fs.cwd();
    };

    const paths: []const ?[]const u8 = b: {
        var path_env: ?[]const u8 = null;
        for (std.os.environ) |envZ| {
            const env = std.mem.span(envZ);
            if (std.mem.startsWith(u8, env, "PATH=")) {
                path_env = env[5..];
                break;
            }
        }
        const path_count = std.mem.count(u8, path_env orelse "", ":");
        if (path_env == null or path_count == 0) break :b &[_]?[]const u8{"/usr/bin"};
        const paths = try alloc.alloc(?[]const u8, path_count);
        var itr = std.mem.tokenizeScalar(u8, path_env.?, ':');
        for (paths) |*p| {
            p.* = itr.next();
        }
        break :b paths;
    };
    sys_exes = try .initCapacity(alloc, 4096);
    var thread = try std.Thread.spawn(.{}, scanPaths, .{ alloc, &sys_exes, paths });
    defer thread.join();

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.init(@alignCast(font));
    ttf_ptr = &ttf;

    glyph_cache = .init(14);
    defer glyph_cache.raze(alloc);

    command_history = loadHistory(home_dir, alloc) catch |err| b: {
        std.debug.print("error loading history {}\n", .{err});
        break :b &.{};
    };

    _ = root.draw(&buffer, box);
    surface.attach(buffer.buffer, 0, 0);
    surface.damageBuffer(0, 0, @intCast(box.w), @intCast(box.h));
    surface.commit();

    zm.charcoal.ui.active_buffer = &buffer;
    try zm.charcoal.run();

    if (ui_key_buffer.items.len > 2) {
        try writeOutHistory(home_dir, command_history, ui_key_buffer.items);
    }
}

pub const std_options: std.Options = .{
    .log_level = .info,
};

var glyph_cache: Glyph.Cache = undefined;
var sys_exes: std.ArrayListUnmanaged([]const u8) = undefined;
var ui_key_buffer: *const std.ArrayListUnmanaged(u8) = undefined;
var ttf_ptr: *const Ttf = undefined;
var root_zmenu: *ZMenu = undefined;
var command_history: []Command = undefined;

pub const Config = struct {
    history: bool = true,
};

fn loadRc(a: Allocator) !Config {
    const rc = std.fs.cwd().readFileAlloc(a, ".zmenurc", 0x1ffff) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer a.free(rc);
    // split lines
    // parse line
    // return options

    return .{};
}

pub const Command = struct {
    count: usize,
    time: i64 = 0,
    text: []const u8,

    pub fn raze(c: Command, a: Allocator) void {
        a.free(c.text);
    }
};

fn loadHistory(dir: std.fs.Dir, a: Allocator) ![]Command {
    const history = dir.readFileAlloc(a, ".zmenu_history", 0x1ffff) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer a.free(history);

    const count = std.mem.count(u8, history, "\n");
    const cmds: []Command = try a.alloc(Command, count);

    var itr = std.mem.splitScalar(u8, history, '\n');
    for (cmds) |*cmd| {
        const line = itr.next() orelse return error.IteratorFailed;
        if (std.mem.indexOfScalar(u8, line, ':')) |i| {
            const text_i = std.mem.indexOfScalarPos(u8, line, i + 1, ':') orelse i;
            cmd.* = .{
                .count = std.fmt.parseInt(usize, line[0..i], 10) catch return error.InvalidHitCount,
                .text = try a.dupe(u8, line[text_i + 1 ..]),
            };
        } else return error.InvalidHistoryLine;
    }
    return cmds;
}

fn writeOutHistory(dir: std.fs.Dir, cmds: []Command, new: []const u8) !void {
    var next: Command = .{
        .count = 1,
        .text = new,
    };
    for (cmds) |*cmd| {
        if (std.mem.eql(u8, cmd.text, new)) {
            cmd.count += 1;
            next.count = 0;
            break;
        }
    }
    std.mem.sort(Command, cmds, {}, struct {
        pub fn inner(_: void, l: Command, r: Command) bool {
            return !(l.count <= r.count);
        }
    }.inner);

    var file = try dir.createFile(".zmenu_history.new", .{});
    var w = file.writer();
    for (cmds) |c| try w.print("{}::{s}\n", .{ c.count, c.text });
    if (next.count > 0) try w.print("{}::{s}\n", .{ next.count, next.text });
    file.close();
    try dir.rename(".zmenu_history.new", ".zmenu_history");
}

/// Paths must be absolute
fn scanPaths(a: Allocator, list: *std.ArrayListUnmanaged([]const u8), paths: []const ?[]const u8) void {
    for (paths) |path0| {
        const path = path0 orelse continue;
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue, // It's expected that some dirs will go missing
            else => {
                std.debug.print("Unable to open path '{s}' because {}\n", .{ path, err });
                continue;
            },
        };
        defer dir.close();
        var ditr = dir.iterate();

        while (ditr.next() catch |err| {
            std.debug.print("Unable to iterate on path '{s}' because {}\n", .{ path, err });
            break;
        }) |file| switch (file.kind) {
            .file => list.append(a, a.dupe(u8, file.name) catch @panic("OOM")) catch @panic("OOM"),
            else => {},
        };
        std.Thread.yield() catch {};
    }
}

const UiRoot = struct {
    var ui_options_children = [_]Ui.Component{
        .{ .vtable = .auto(UiHistoryOptions), .children = &.{} },
        .{ .vtable = .auto(UiExecOptions), .children = &.{} },
    };

    var ui_children = [_]Ui.Component{
        .{ .vtable = .auto(UiCommandBox), .children = &.{} },
        .{ .vtable = .auto(UiOptions), .children = &ui_options_children },
    };

    pub fn background(_: *Ui.Component, b: *const Buffer, box: Buffer.Box) void {
        b.drawRectangleRoundedFill(Buffer.ARGB, box, 25, .alpha(.ash_gray, 0x7c));
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        for (comp.children) |*child| {
            _ = child.keyPress(evt);
            comp.damaged = child.damaged or comp.damaged;
        }
        if (evt.up) return true;
        switch (evt.key) {
            .char => {},
            .ctrl => |ctrl| switch (ctrl) {
                .enter => {
                    const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.children[0].state));
                    const history: *UiHistoryOptions = @alignCast(@ptrCast(comp.children[1].children[0].state));
                    const paths: *UiExecOptions = @alignCast(@ptrCast(comp.children[1].children[1].state));
                    if (history.cursor_idx > 0 or paths.cursor_idx > 0) {
                        const exe_string: ?[]const u8 = history.getExec(textbox.key_buffer.items) orelse
                            paths.getExec(textbox.key_buffer.items, history.drawn);
                        if (exe_string) |exe| {
                            if (std.posix.fork()) |pid| {
                                if (pid == 0) {
                                    exec(exe) catch {};
                                } else {
                                    textbox.key_buffer.clearRetainingCapacity();
                                    textbox.key_buffer.appendSliceAssumeCapacity(exe);
                                    root_zmenu.running = false;
                                }
                            } else |_| @panic("everyone knows fork can't fail");
                        }
                    } else if (textbox.key_buffer.items.len > 0) {
                        if (std.posix.fork()) |pid| {
                            if (pid == 0) {
                                exec(textbox.key_buffer.items) catch {};
                            } else {
                                root_zmenu.running = false;
                            }
                        } else |_| @panic("everyone knows fork can't fail");
                    }
                    return true;
                },
                .escape => {
                    comp.damaged = true;
                    const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.children[0].state));
                    const history: *UiHistoryOptions = @alignCast(@ptrCast(comp.children[1].children[0].state));
                    const paths: *UiExecOptions = @alignCast(@ptrCast(comp.children[1].children[1].state));
                    if (history.cursor_idx > 0 or paths.cursor_idx > 0) {
                        history.cursor_idx = 0;
                        paths.cursor_idx = 0;
                    } else if (textbox.key_buffer.items.len > 0) {
                        textbox.key_buffer.clearRetainingCapacity();
                    } else {
                        root_zmenu.end();
                    }
                    return true;
                },
                else => {},
            },
        }
        return false;
    }

    fn exec(cmd: []const u8) !noreturn {
        var argv = cmd;
        var argv_buf: [2048]u8 = undefined;
        if (cmd[0] != '/') {
            argv = try std.fmt.bufPrint(&argv_buf, "/usr/bin/{s}", .{cmd});
        }

        std.process.execve(
            std.heap.page_allocator,
            &[1][]const u8{argv},
            null,
        ) catch @panic("oopsies");
    }
};

const UiCommandBox = struct {
    alloc: Allocator,
    key_buffer: std.ArrayListUnmanaged(u8),

    pub fn init(comp: *Ui.Component, a: Allocator, _: Buffer.Box) Ui.Component.InitError!void {
        const textbox: *UiCommandBox = try a.create(UiCommandBox);
        textbox.* = .{
            .alloc = a,
            .key_buffer = try .initCapacity(a, 4096),
        };
        comp.state = textbox;
        ui_key_buffer = &textbox.key_buffer;
    }

    pub fn raze(comp: *Ui.Component, a: Allocator) void {
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        textbox.key_buffer.deinit(a);
        a.destroy(textbox);
    }

    pub fn draw(comp: *Ui.Component, buffer: *const Buffer, root: Buffer.Box) void {
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        var box = root;
        box = .xywh(35, 30, 600 - 35 * 2, 40);
        buffer.drawRectangleRoundedFill(Buffer.ARGB, box, 10, .ash_gray);
        buffer.drawRectangleRounded(Buffer.ARGB, box, 10, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 9, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 8, .hookers_green);
        box.add(.scale(1));
        buffer.drawRectangleRounded(Buffer.ARGB, box, 7, .hookers_green);

        if (textbox.key_buffer.items.len > 0) {
            drawText(
                textbox.alloc,
                &glyph_cache,
                buffer,
                ui_key_buffer.items,
                ttf_ptr.*,
                .xywh(45, 55, root.w - 80, root.h - 80),
                .charcoal,
            ) catch @panic("draw the textbox failed :<");
        }
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        if (evt.up) return false;
        const textbox: *UiCommandBox = @alignCast(@ptrCast(comp.state));
        switch (evt.key) {
            .char => |chr| {
                comp.damaged = true;
                textbox.key_buffer.appendAssumeCapacity(chr);
            },
            .ctrl => |ctrl| switch (ctrl) {
                .backspace => {
                    comp.damaged = true;
                    _ = textbox.key_buffer.pop();
                    return true;
                },
                .enter => {},
                .escape => {},
                else => {},
            },
        }
        return false;
    }
};

const UiOptions = struct {
    pub fn draw(comp: *Ui.Component, buffer: *const Buffer, box: Buffer.Box) void {
        const history_box: Buffer.Box = .xywh(45, 70, box.w - 70, box.h - 95);
        buffer.drawRectangleFill(Buffer.ARGB, history_box, .alpha(.ash_gray, 0x7c));

        const hist: *UiHistoryOptions = @alignCast(@ptrCast(comp.children[0].state));
        comp.children[0].draw(buffer, history_box);

        var path_box = history_box;
        path_box.y += 20 * hist.drawn;
        path_box.h -= 20 * hist.drawn;
        const path: *UiExecOptions = @alignCast(@ptrCast(comp.children[1].state));
        path.history_count = hist.drawn;

        const cursor: usize = @min(@max(hist.cursor_idx, path.cursor_idx), hist.drawn + path.drawn);
        hist.cursor_idx = cursor;
        path.cursor_idx = cursor;
        comp.children[1].draw(buffer, path_box);
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        for (comp.children) |*c| {
            comp.damaged = c.damaged or comp.damaged;
            _ = c.keyPress(evt);
        }

        const hist: *UiHistoryOptions = @alignCast(@ptrCast(comp.children[0].state));
        const path: *UiExecOptions = @alignCast(@ptrCast(comp.children[1].state));
        const cursor: usize = @min(@max(hist.cursor_idx, path.cursor_idx), hist.drawn + path.drawn);
        hist.cursor_idx = cursor;
        path.cursor_idx = cursor;
        return true;
    }
};

const UiHistoryOptions = struct {
    alloc: Allocator,
    cursor_idx: usize = 0,
    drawn: usize = 0,
    found: usize = 0,

    pub fn init(comp: *Ui.Component, a: Allocator, _: Buffer.Box) Ui.Component.InitError!void {
        const options: *UiHistoryOptions = try a.create(UiHistoryOptions);
        options.* = .{
            .alloc = a,
        };
        comp.state = options;
    }

    pub fn raze(comp: *Ui.Component, a: Allocator) void {
        a.destroy(@as(*UiHistoryOptions, @alignCast(@ptrCast(comp.state))));
    }

    pub fn draw(comp: *Ui.Component, buffer: *const Buffer, box: Buffer.Box) void {
        const hist: *UiHistoryOptions = @alignCast(@ptrCast(comp.state));

        const drawn, const found = drawHistory(
            hist.alloc,
            buffer,
            hist.cursor_idx,
            command_history,
            ui_key_buffer.items,
            box,
        ) catch @panic("drawing failed");
        hist.drawn = drawn;
        hist.found = found;
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        if (evt.up) return false;
        const histopt: *UiHistoryOptions = @alignCast(@ptrCast(comp.state));
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
                    else => return false,
                }
                comp.damaged = true;
                return true;
            },
            else => {},
        }
        //std.debug.print("exec keyevent {}\n", .{evt});
        return false;
    }

    fn drawHistory(
        a: Allocator,
        buf: *const Buffer,
        highlighted: usize,
        cmds: []Command,
        prefix: []const u8,
        box: Buffer.Box,
    ) !struct { usize, usize } {
        var fillbox = box;
        fillbox.x -|= 5;
        buf.drawRectangleFill(Buffer.ARGB, fillbox, .alpha(.ash_gray, 0x7c));
        var drawn: usize = 0;
        var found: usize = 0;
        for (cmds) |cmd| {
            const y = box.y + 20 + 20 * (drawn);
            if (prefix.len == 0 or std.mem.startsWith(u8, cmd.text, prefix)) {
                found += 1;
                if (drawn > 4) continue;
                try drawText(a, &glyph_cache, buf, cmd.text, ttf_ptr.*, .xywh(box.x, y, box.w, 25), .charcoal);
                drawn += 1;
                if (drawn == highlighted) {
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y - 19, box.w, 25), 10, .hookers_green);
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y - 18, box.w - 2, 25 - 2), 9, .hookers_green);
                }
            }
        }
        return .{ drawn, found };
    }

    fn getExec(hist: *UiHistoryOptions, str: []const u8) ?[]const u8 {
        var idx: usize = 0;
        if (hist.cursor_idx > command_history.len) return null;
        for (command_history) |cmd| {
            if (std.mem.startsWith(u8, cmd.text, str)) {
                idx += 1;
                if (idx == hist.cursor_idx) {
                    return cmd.text;
                }
            }
        }
        return null;
    }
};

const UiExecOptions = struct {
    alloc: Allocator,
    cursor_idx: usize = 0,
    history_count: usize = 0,
    drawn: usize = 0,
    found: usize = 0,

    pub fn init(comp: *Ui.Component, a: Allocator, _: Buffer.Box) Ui.Component.InitError!void {
        const options: *UiExecOptions = try a.create(UiExecOptions);
        options.* = .{
            .alloc = a,
        };
        comp.state = options;
    }

    pub fn raze(comp: *Ui.Component, a: Allocator) void {
        a.destroy(@as(*UiExecOptions, @alignCast(@ptrCast(comp.state))));
    }

    pub fn draw(comp: *Ui.Component, buffer: *const Buffer, box: Buffer.Box) void {
        const exoptions: *UiExecOptions = @alignCast(@ptrCast(comp.state));

        const drawn, const found = drawPathlist(
            exoptions.alloc,
            buffer,
            exoptions.cursor_idx -| exoptions.history_count,
            9 - exoptions.history_count,
            sys_exes.items,
            ui_key_buffer.items,
            box,
        ) catch @panic("drawing failed");
        exoptions.drawn = drawn;
        exoptions.found = found;
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        if (evt.up) return false;
        const exoptions: *UiExecOptions = @alignCast(@ptrCast(comp.state));
        switch (evt.key) {
            .ctrl => |ctrl| {
                switch (ctrl) {
                    .arrow_up => exoptions.cursor_idx -|= 1,
                    .arrow_down => exoptions.cursor_idx +|= 1,
                    .tab => {
                        if (evt.mods.shift)
                            exoptions.cursor_idx -|= 1
                        else
                            exoptions.cursor_idx +|= 1;
                    },
                    else => return false,
                }
                comp.damaged = true;
                return true;
            },
            else => {},
        }
        return true;
    }

    fn drawPathlist(
        a: Allocator,
        buf: *const Buffer,
        highlighted: usize,
        allowed: usize,
        bins: []const []const u8,
        prefix: []const u8,
        box: Buffer.Box,
    ) !struct { usize, usize } {
        if (prefix.len == 0 or bins.len == 0) return .{ 0, 0 };
        var drawn: usize = 0;
        var found: usize = 0;
        for (bins) |bin| {
            const y = box.y + 20 + 20 * (drawn);
            if (prefix.len == 0 or std.mem.startsWith(u8, bin, prefix)) {
                found += 1;
                if (drawn > allowed) continue;
                try drawText(a, &glyph_cache, buf, bin, ttf_ptr.*, .xywh(box.x, y, box.w, 25), .dark_slate_gray);
                drawn += 1;
                if (drawn == highlighted) {
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y - 19, box.w, 25), 10, .hookers_green);
                    buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y - 18, box.w - 2, 25 - 2), 9, .hookers_green);
                }
            }
        }
        if (highlighted > drawn and drawn > 0) {
            const y = box.y + 20 * (drawn - 1);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 5, y + 1, box.w, 25), 10, .hookers_green);
            buf.drawRectangleRounded(Buffer.ARGB, .xywh(box.x - 4, y + 2, box.w - 2, 25 - 2), 9, .hookers_green);
        }
        return .{ drawn, found };
    }
    fn getExec(exc: *UiExecOptions, str: []const u8, hdrawn: usize) ?[]const u8 {
        const cursor = exc.cursor_idx -| hdrawn;
        if (cursor == 0) return null;
        if (cursor > exc.drawn) return null;
        var idx: usize = 0;
        for (sys_exes.items) |exe| {
            if (std.mem.startsWith(u8, exe, str)) {
                idx += 1;
                if (idx == cursor) {
                    return exe;
                }
            }
        }
        return null;
    }
};

fn drawText(
    alloc: Allocator,
    cache: *Glyph.Cache,
    buffer: *const Buffer,
    text: []const u8,
    ttf: Ttf,
    box: Buffer.Box,
    color: Buffer.ARGB,
) !void {
    var layout_helper = LayoutHelper.init(alloc, text, ttf, @intCast(box.w), 14);
    defer layout_helper.glyphs.deinit();
    while (try layout_helper.step(ttf)) {}

    const tl: LayoutHelper.Text = .{
        .glyphs = try layout_helper.glyphs.toOwnedSlice(),
        .min_x = layout_helper.bounds.min_x,
        .max_x = layout_helper.bounds.max_x,
        .min_y = layout_helper.bounds.min_y,
        .max_y = layout_helper.bounds.max_y,
    };

    for (tl.glyphs) |g| {
        const canvas, _ = (try cache.get(alloc, ttf, g.char)).*;
        buffer.drawFont(Buffer.ARGB, color, .xywh(
            @intCast(@as(i32, @intCast(box.x)) + g.pixel_x1),
            @intCast(@as(i32, @intCast(box.y)) - g.pixel_y1),
            @intCast(canvas.width),
            @intCast(canvas.height),
        ), canvas.pixels);
    }
}

fn drawColors(size: usize, buffer: Buffer, colors: Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = @intCast(x * 0xff / size);
        const r_y: usize = @intCast(y * 0xff / size);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c = Buffer.ARGB.rgb(r, g, b);
        colors.draw(.xywh(x, y, 1, 1), &[1]u32{c.int()});
        const b2: u8 = 0xff - g;
        const c2 = Buffer.ARGB.rgb(r, g, b2);
        buffer.draw(.xywh(x, y, 1, 1), &[1]u32{@intFromEnum(c2)});
    };
}

fn drawBackground0(buf: Buffer, box: Buffer.Box) !void {
    for (box.y..box.y2()) |y| for (box.x..box.x2()) |x| {
        const r_y: usize = @intCast(y * 0xff / buf.width);
        const r_x: usize = @intCast(x * 0xff / buf.width);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = 0xff - g;
        const c = Buffer.ARGB.rgb(r, g, b);
        buf.drawPoint(Buffer.ARGB, .xy(x, y), c);
    };
}

test {
    _ = &Buffer;
    _ = &LayoutHelper;
    _ = &Ttf;
    _ = &ZMenu;
    _ = &Glyph;
}

const charcoal = @import("charcoal");
const Buffer = charcoal.Buffer;
const LayoutHelper = @import("LayoutHelper.zig");
const Ttf = @import("ttf.zig");
const Glyph = @import("Glyph.zig");
const ZMenu = @import("ZMenu.zig");
const Ui = charcoal.Ui;

const std = @import("std");
const Allocator = std.mem.Allocator;
