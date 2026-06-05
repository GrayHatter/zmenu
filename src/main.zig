const ZMenu = struct {
    charcoal: Charcoal,
    running: bool = true,

    pub fn init() !ZMenu {
        return .{
            .charcoal = try .init(),
        };
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
};

var zmenu: ZMenu = .{
    .charcoal = undefined,
};

pub const Theme = struct {
    bg: u32,
    text: u32,
    p: u32,
    s: u32,
    t: u32,

    bg_alpha: u8 = 0xef,

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
};

pub var theme: Theme = .init(ARGB, .eerie_black, .silver, .sinopia, .cornsilk, .avocado);

var environ: std.process.Environ = undefined;
// TODO remove
var _io: Io = undefined;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    _io = init.io;
    const io = _io;
    environ = init.minimal.environ;
    var args = init.minimal.args.iterate();

    zmenu = try .init();
    try zmenu.charcoal.connect();
    defer zmenu.raze();

    // Primary size
    const box: Buffer.Box = .wh(600, 300);
    // Resize here first to trick wl into the position we want
    var buffer: Buffer = try zmenu.charcoal.createBufferCapacity(box, box.add(.wh(0, 1000)), "buffer");
    defer buffer.raze();
    try zmenu.charcoal.wayland.rename("zmenu");

    var root: Root = .{};
    Root.cmd_box.alloc = alloc;
    Root.cmd_box.key_buffer = try .initCapacity(alloc, 4096);
    ui_key_buffer = &Root.cmd_box.key_buffer;
    Root.options.history.alloc = alloc;
    Root.options.exec.alloc = alloc;

    try zmenu.charcoal.ui.init(&root.component, &buffer, box, null);
    defer zmenu.charcoal.ui.raze(alloc);

    const home_dir: std.Io.Dir = h: {
        while (args.next()) |env| {
            if (std.mem.startsWith(u8, env, "HOME=")) {
                if (env[5..].len == 0) continue;
                if (Io.Dir.openDirAbsolute(io, env[5..], .{})) |dir| {
                    break :h dir;
                } else |err| {
                    std.debug.print(
                        "Unable to open home dir specified by $HOME '{s}' error {}\n",
                        .{ env[5..], err },
                    );
                    break :h std.Io.Dir.cwd();
                }
            }
        }
        break :h std.Io.Dir.cwd();
    };

    args = init.minimal.args.iterate();
    const paths: []const ?[]const u8 = b: {
        var path_env: ?[]const u8 = null;
        while (args.next()) |env| {
            if (std.mem.startsWith(u8, env, "PATH=")) {
                path_env = env[5..];
                break;
            }
        }
        const path_count = std.mem.count(u8, path_env orelse "", ":");
        if (path_env == null or path_count == 0) break :b &[_]?[]const u8{"/usr/bin"};
        const paths = try alloc.alloc(?[]const u8, path_count + 1);
        var itr = std.mem.tokenizeScalar(u8, path_env.?, ':');
        for (paths) |*p| {
            p.* = itr.next();
        }
        break :b paths;
    };
    sys_exes = try .initCapacity(alloc, 8192);
    var thread = try std.Thread.spawn(.{}, scanPaths, .{ &sys_exes, paths, alloc, io });
    defer thread.join();

    const font: []u8 = try alloc.dupe(u8, @embedFile("font.ttf"));
    defer alloc.free(font);
    const ttf = try Ttf.load(@alignCast(font));

    glyph_cache = .init(&ttf, 0.01866);
    defer glyph_cache.raze(alloc);

    user_config = loadRc(home_dir, alloc, io) catch |err| b: {
        std.debug.print("error loading rc {}\n", .{err});
        break :b .{};
    };

    if (user_config.history) {
        command_history = loadHistory(home_dir, alloc, io) catch |err| b: {
            std.debug.print("error loading history {}\n", .{err});
            break :b &.{};
        };
    }
    if (user_config.theme.background) |bg| theme.bg = @intFromEnum(bg);
    if (user_config.theme.text) |tx| theme.text = @intFromEnum(tx);
    if (user_config.theme.primary) |pr| theme.p = @intFromEnum(pr);
    if (user_config.theme.secondary) |sd| theme.s = @intFromEnum(sd);
    if (user_config.theme.tertiary) |tr| theme.t = @intFromEnum(tr);

    zmenu.charcoal.ui.active_buffer = &buffer;
    try zmenu.charcoal.runRateLimit(.fps(60), io);

    if (ui_key_buffer.items.len > 2 and user_config.history) {
        try writeOutHistory(home_dir, command_history, ui_key_buffer.items, io);
    } else if (write_history) {
        try writeOutHistory(home_dir, command_history, "", io);
    }
}

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub var write_history: bool = false;
pub var glyph_cache: Ttf.GlyphCache = undefined;
var sys_exes: ArrayList(PathExec) = .empty;
pub var ui_key_buffer: *const ArrayList(u8) = undefined;
var ttf_ptr: *const Ttf = undefined;
pub var command_history: []Command = &.{};
var user_config: Config = .{};

pub const Config = struct {
    history: bool = true,
    theme: struct {
        background: ?ARGB = null,
        text: ?ARGB = null,
        primary: ?ARGB = null,
        secondary: ?ARGB = null,
        tertiary: ?ARGB = null,
    } = .{},
};

// TODO support other color formats
fn parseHexColor(str: []const u8) !ARGB {
    var value = str[mem.indexOfScalar(u8, str, '#') orelse return error.InvalidFormat ..];
    value = std.mem.trim(u8, value, "# \n\t");

    if (value.len < 6) {
        if (value.len != 3) return error.InvalidColor;

        return .rgb(
            std.fmt.parseInt(u8, &[2]u8{ value[0], value[0] }, 16) catch return error.InvalidColor,
            std.fmt.parseInt(u8, &[2]u8{ value[1], value[1] }, 16) catch return error.InvalidColor,
            std.fmt.parseInt(u8, &[2]u8{ value[2], value[2] }, 16) catch return error.InvalidColor,
        );
    }
    var color: ARGB = .rgb(
        std.fmt.parseInt(u8, value[0..2], 16) catch return error.InvalidColor,
        std.fmt.parseInt(u8, value[2..4], 16) catch return error.InvalidColor,
        std.fmt.parseInt(u8, value[4..6], 16) catch return error.InvalidColor,
    );
    if (value.len >= 8) {
        color = color.alpha(std.fmt.parseInt(u8, value[6..8], 16) catch return error.InvalidColor);
    }
    return color;
}

fn loadRc(dir: Io.Dir, a: Allocator, io: Io) !Config {
    const rc = dir.readFileAlloc(io, ".zmenurc", a, .limited(0x1ffff)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer a.free(rc);
    var cfg: Config = .{};

    var itr = mem.splitScalar(u8, rc, '\n');
    while (itr.next()) |lineW| {
        const line = mem.trim(u8, lineW, " \t\n");
        if (line.len == 0 or line[0] == '#') continue;
        if (mem.startsWith(u8, line, "background")) {
            cfg.theme.background = parseHexColor(line[10..]) catch null;
        } else if (mem.startsWith(u8, line, "text")) {
            cfg.theme.text = parseHexColor(line[4..]) catch null;
        } else if (mem.startsWith(u8, line, "primary")) {
            cfg.theme.primary = parseHexColor(line[7..]) catch null;
        } else if (mem.startsWith(u8, line, "secondary")) {
            cfg.theme.secondary = parseHexColor(line[9..]) catch null;
        } else if (mem.startsWith(u8, line, "tertiary")) {
            cfg.theme.tertiary = parseHexColor(line[8..]) catch null;
        } else if (mem.startsWith(u8, line, "history")) {
            if (line.len > 8) {
                const disabled = mem.indexOf(u8, line, " off") orelse mem.indexOf(u8, line, " disable");
                cfg.history = disabled == null;
            } else {
                cfg.history = true;
            }
        } else {}
    }
    return cfg;
}

pub const Command = struct {
    count: usize,
    time: i64 = 0,
    text: []const u8,

    pub fn raze(c: Command, a: Allocator) void {
        a.free(c.text);
    }

    pub fn match(cmd: Command, str: []const u8) bool {
        if (cmd.count == 0) return false;
        return str.len == 0 or std.mem.startsWith(u8, cmd.text, str);
    }
};

fn loadHistory(dir: Io.Dir, a: Allocator, io: Io) ![]Command {
    const history = dir.readFileAlloc(io, ".zmenu_history", a, .limited(0x1ffff)) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer a.free(history);

    const count = mem.count(u8, history, "\n");
    const cmds: []Command = try a.alloc(Command, count);

    var itr = mem.splitScalar(u8, history, '\n');
    for (cmds) |*cmd| {
        const line = itr.next() orelse return error.IteratorFailed;
        if (mem.indexOfScalar(u8, line, ':')) |i| {
            const text_i = mem.indexOfScalarPos(u8, line, i + 1, ':') orelse i;
            cmd.* = .{
                .count = std.fmt.parseInt(usize, line[0..i], 10) catch return error.InvalidHitCount,
                .text = try a.dupe(u8, line[text_i + 1 ..]),
            };
        } else return error.InvalidHistoryLine;
    }
    return cmds;
}

fn writeOutHistory(dir: Io.Dir, cmds: []Command, new: []const u8, io: Io) !void {
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

    {
        var file = try dir.createFile(io, ".zmenu_history.new", .{});
        defer file.close(io);
        var w_b: [4096]u8 = undefined;
        var file_w = file.writer(io, &w_b);
        const w = &file_w.interface;
        defer w.flush() catch unreachable;
        for (cmds) |c| {
            if (c.count > 0) try w.print("{}::{s}\n", .{ c.count, c.text });
        }
        if (next.count > 0 and next.text.len > 0) try w.print("{}::{s}\n", .{ next.count, next.text });
    }
    try dir.rename(".zmenu_history.new", dir, ".zmenu_history", io);
}

const PathExec = struct {
    path: []const u8,
    name: []const u8,
    arg0: []const u8,

    pub fn match(pe: PathExec, str: []const u8) bool {
        return str.len == 0 or std.mem.startsWith(u8, pe.name, str);
    }
};

/// Paths must be absolute
fn scanPaths(root_list: *ArrayList(PathExec), paths: []const ?[]const u8, a: Allocator, io: Io) void {
    var list = root_list.*;

    for (paths) |path0| {
        const path = path0 orelse continue;
        var dir = Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue, // It's expected that some dirs will go missing
            else => {
                std.debug.print("Unable to open path '{s}' because {}\n", .{ path, err });
                continue;
            },
        };
        defer dir.close(io);
        var ditr = dir.iterate();

        while (ditr.next(io) catch |err| {
            std.debug.print("Unable to iterate on path '{s}' because {}\n", .{ path, err });
            break;
        }) |file| switch (file.kind) {
            .file => {
                const full = std.fs.path.join(a, &[2][]const u8{
                    path,
                    file.name,
                }) catch @panic("OOM");
                list.append(a, .{
                    .arg0 = full,
                    .name = full[full.len - file.name.len ..],
                    .path = path,
                }) catch @panic("OOM");
            },
            else => {},
        };
        std.Thread.yield() catch {};
    }
    root_list.* = list;
}

const Root = struct {
    component: Ui.Component = .{
        .vtable = .auto(Root),
        .children = &.{ &cmd_box.component, &options.component },
    },
    m_enabled: bool = false,

    var cmd_box: CommandBox = .{
        .component = .{ .vtable = .auto(CommandBox), .children = &.{} },
        .alloc = undefined,
    };
    var options: Options = .{
        .component = .{ .vtable = .auto(Options), .children = &.{} },
        .history = .{ .component = .{ .vtable = .auto(Options.History), .children = &.{} } },
        .exec = .{
            .component = .{ .vtable = .auto(Options.Exec), .children = &.{} },
            .alloc = undefined,
        },
    };

    pub const draw = null;
    pub const init = null;
    pub const mAxis = null;
    pub const mClick = null;
    pub const raze = null;
    pub const tick = null;

    pub fn background(_: *Ui.Component, b: *Buffer, box: Buffer.Box) void {
        b.drawRectangleRoundedFill(ARGB, box, 25, theme.rgba(ARGB, .background));
    }

    pub fn mMove(comp: *Ui.Component, mmove: Ui.Event.MMove, box: Buffer.Box) void {
        const root: *Root = @fieldParentPtr("component", comp);
        if (!root.m_enabled) return;
        const options_box = box.add(Options.size);
        //const mbox = Buffer.Box.zero.add(.xy(@intCast(mmove.pos.x), @intCast(mmove.pos.y)));
        if (mmove.withinBox(options_box)) |new| {
            comp.children[1].mMove(new, box);
            comp.draw_needed = comp.children[1].draw_needed or comp.draw_needed;
        }
        //for (comp.children) |*c| c.mMove(mmove, box);
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        for (comp.children) |child| {
            _ = child.keyPress(evt);
            comp.draw_needed = child.draw_needed or comp.draw_needed;
        }
        if (evt.up) return true;

        const textbox: *CommandBox = &cmd_box;
        //const root: *Root = @fieldParentPtr("component", comp);
        const history: *Options.History = &options.history;
        const paths: *Options.Exec = &options.exec;
        switch (evt.key) {
            .char => {},
            .ctrl => |ctrl| switch (ctrl) {
                .enter => {
                    if (history.cursor_idx > 0 or paths.cursor_idx > 0) {
                        const exe_string: ?[]const u8 = history.getExec(textbox.key_buffer.items) orelse
                            paths.getExec(textbox.key_buffer.items, history.drawn);
                        if (exe_string) |exe| {
                            const pid = std.posix.system.fork();
                            if (pid < 0) @panic("everyone knows fork can't fail");
                            if (pid == 0) {
                                exec(exe, _io) catch {};
                            }
                            textbox.key_buffer.clearRetainingCapacity();
                            textbox.key_buffer.appendSliceAssumeCapacity(exe);
                            zmenu.end();
                        }
                    } else if (textbox.key_buffer.items.len > 0) {
                        const pid = std.posix.system.fork();
                        if (pid < 0) @panic("everyone knows fork can't fail");
                        if (pid == 0) {
                            exec(textbox.key_buffer.items, _io) catch {};
                        }
                        zmenu.end();
                    }
                    return true;
                },
                .escape => {
                    comp.draw_needed = true;
                    if (history.cursor_idx > 0 or paths.cursor_idx > 0) {
                        history.cursor_idx = 0;
                        paths.cursor_idx = 0;
                    } else if (textbox.key_buffer.items.len > 0) {
                        textbox.key_buffer.clearRetainingCapacity();
                    } else {
                        zmenu.end();
                    }
                    return true;
                },
                .arrow_left, .arrow_right => {
                    if (history.cursor_idx > 0 or paths.cursor_idx > 0) {
                        const exe_string: ?[]const u8 = history.getExec(textbox.key_buffer.items) orelse
                            paths.getExec(textbox.key_buffer.items, history.drawn);
                        if (exe_string) |exe| {
                            textbox.key_buffer.clearRetainingCapacity();
                            textbox.key_buffer.appendSliceAssumeCapacity(exe);
                            comp.draw_needed = true;
                            history.cursor_idx = 0;
                            paths.cursor_idx = 0;
                        }
                    }
                    return true;
                },
                else => {},
            },
            .focus => {},
        }
        return false;
    }

    const state = enum {
        start,
        new_word,
        word,
        whitespace,
    };

    fn tokenize(a: Allocator, path: []const u8, str: []const u8) ![*:null]const ?[*:0]const u8 {
        var start: usize = 0;
        var idx: usize = 0;
        var list: ArrayList(?[*:0]const u8) = .empty;
        if (str.len == 0) return &.{};
        tkn: switch (state.start) {
            .start => {
                while (idx < str.len and str[idx] != ' ') idx += 1;
                try list.append(a, try std.fs.path.joinZ(a, &[2][]const u8{ path, str[start..idx] }));
                if (idx < str.len) continue :tkn .whitespace;
                break :tkn;
            },
            .new_word => {
                start = idx;
                continue :tkn .word;
            },
            .word => {
                while (idx < str.len and str[idx] != ' ') idx += 1;
                try list.append(a, try a.dupeZ(u8, str[start..idx]));
                if (idx < str.len) continue :tkn .whitespace;
                break :tkn;
            },
            .whitespace => {
                while (idx < str.len and str[idx] == ' ') idx += 1;
                if (idx < str.len) continue :tkn .new_word;
                break :tkn;
            },
        }
        //try list.append(a, null);
        return try list.toOwnedSliceSentinel(a, null);
    }

    fn exec(cmd: []const u8, io: Io) !noreturn {
        if (cmd[0] != '/') {
            for (sys_exes.items) |arg| {
                if (startsWith(u8, cmd, arg.name)) {
                    const args = try tokenize(std.heap.page_allocator, arg.path, cmd);
                    for (std.mem.span(args)) |arg2| {
                        std.debug.print("arg {s}\n", .{arg2.?});
                    }
                    _ = std.os.linux.execve(args[0].?, args, @ptrCast(environ.block.slice.ptr));
                    unreachable;
                }
            }
        }
        var argv_buf: [2048]u8 = undefined;
        const argv = try std.fmt.bufPrint(&argv_buf, "/usr/bin/{s}", .{cmd});
        std.process.replace(io, .{
            .argv = &[1][]const u8{argv},
            .expand_arg0 = .no_expand,
            .environ_map = null,
        }) catch @panic("oopsies");
    }
};

const CommandBox = struct {
    component: Ui.Component,
    alloc: Allocator,
    key_buffer: ArrayList(u8) = .empty,

    pub const init = null;
    pub const raze = null;
    pub const mAxis = null;
    pub const mClick = null;
    pub const mMove = null;
    pub const tick = null;

    pub fn background(_: *Ui.Component, b: *Buffer, root: Box) void {
        var box = root.add(.xywh(35, 30, -35 * 2, 40 - @as(isize, @intCast(root.h))));
        b.drawRectangleRoundedFill(ARGB, box, 10, theme.rgb(ARGB, .background));
        b.drawRectangleRounded(ARGB, box, 10, theme.rgb(ARGB, .primary));
        box.merge(.vector(1));
        b.drawRectangleRounded(ARGB, box, 9, theme.rgb(ARGB, .primary));
        box.merge(.vector(1));
        b.drawRectangleRounded(ARGB, box, 8, theme.rgb(ARGB, .primary));
        box.merge(.vector(1));
        b.drawRectangleRounded(ARGB, box, 7, theme.rgb(ARGB, .primary));
    }

    pub fn draw(comp: *Ui.Component, buffer: *Buffer, root: Buffer.Box) void {
        if (!comp.draw_needed) return;
        const textbox: *CommandBox = @fieldParentPtr("component", comp);
        var box = root;
        box = .xywh(35, 30, 600 - 35 * 2, 40);
        box.merge(.vector(3));
        buffer.drawRectangleRoundedFill(ARGB, box, 6, theme.rgb(ARGB, .background));

        if (textbox.key_buffer.items.len > 0) {
            drawText(
                textbox.alloc,
                &glyph_cache,
                buffer,
                ui_key_buffer.items,
                .xywh(45, 55, root.w - 80, root.h - 80),
                theme.rgb(ARGB, .text),
            ) catch @panic("draw the textbox failed :<");
        }
        comp.draw_needed = false;
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        if (evt.up) return false;
        const textbox: *CommandBox = @fieldParentPtr("component", comp);
        comp.draw_needed = true;
        switch (evt.key) {
            .char => |chr| {
                comp.draw_needed = true;
                textbox.key_buffer.appendAssumeCapacity(chr);
            },
            .ctrl => |ctrl| switch (ctrl) {
                .delete_word => {
                    while (textbox.key_buffer.items.len > 0 and textbox.key_buffer.items[textbox.key_buffer.items.len - 1] == ' ') {
                        _ = textbox.key_buffer.pop();
                    }
                    while (textbox.key_buffer.items.len > 0 and textbox.key_buffer.items[textbox.key_buffer.items.len - 1] != ' ') {
                        _ = textbox.key_buffer.pop();
                    }
                    comp.draw_needed = true;
                },
                .backspace => {
                    comp.draw_needed = true;
                    _ = textbox.key_buffer.pop();
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
};

const Options = struct {
    component: Ui.Component,
    history: History,
    exec: Exec,

    pub const size: Buffer.Box.Delta = .xywh(35, 70, -70, -75);
    pub const option_size = 20;
    var children = [_]Ui.Component{
        .{ .vtable = .auto(History), .children = &.{} },
        .{ .vtable = .auto(Exec), .children = &.{} },
    };

    pub const background = null;
    pub const init = null;
    pub const mAxis = null;
    pub const mClick = null;
    pub const raze = null;
    pub const tick = null;

    pub fn draw(comp: *Ui.Component, buffer: *Buffer, box: Buffer.Box) void {
        const opt: *Options = @fieldParentPtr("component", comp);
        if (!comp.draw_needed)
            return;

        const history_box: Buffer.Box = box.add(size);
        buffer.drawRectangleFill(ARGB, history_box.add(.wh(0, 1)), theme.rgba(ARGB, .background));

        const count: usize = (box.h - -size.h) / 20;
        opt.history.limit = if (ui_key_buffer.items.len > 0) 3 else count;
        opt.history.component.draw(buffer, history_box);

        const path_box = history_box.add(.xywh(
            0,
            @intCast(20 * (opt.history.drawn)),
            0,
            -20 * @as(isize, @intCast(opt.history.drawn)),
        ));

        opt.exec.history_count = opt.history.drawn;

        const cursor: usize = @min(@max(opt.history.cursor_idx, opt.exec.cursor_idx), opt.history.drawn + opt.exec.drawn);
        opt.history.cursor_idx = cursor;
        opt.exec.cursor_idx = cursor;
        opt.exec.component.draw(buffer, path_box);
        comp.draw_needed = false;
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        const opt: *Options = @fieldParentPtr("component", comp);
        comp.draw_needed = true;
        for (comp.children) |c| {
            _ = c.keyPress(evt);
        }

        const cursor: usize = @min(@max(opt.history.cursor_idx, opt.exec.cursor_idx), opt.history.drawn + opt.exec.drawn);
        opt.history.cursor_idx = cursor;
        opt.exec.cursor_idx = cursor;
        return true;
    }

    pub fn mMove(comp: *Ui.Component, mmove: Ui.Event.MMove, box: Buffer.Box) void {
        const opt: *Options = @fieldParentPtr("component", comp);
        comp.draw_needed = true;
        const cursor_over: usize = ((@as(usize, @intCast(mmove.pos.y)) -| 3) / 20);
        opt.history.cursor_idx = cursor_over + 1;
        opt.exec.cursor_idx = cursor_over + 1;
        for (comp.children) |c| {
            c.mMove(mmove, box);
        }
    }

    const History = @import("History.zig");

    const Exec = struct {
        component: Ui.Component,
        alloc: Allocator,
        cursor_idx: usize = 0,
        history_count: usize = 0,
        drawn: usize = 0,
        found: usize = 0,

        pub const background = null;
        pub const mAxis = null;
        pub const mClick = null;
        pub const mMove = null;
        pub const tick = null;

        pub fn init(_: *Ui.Component, _: Buffer.Box, _: ?Allocator) Ui.Component.InitError!void {}

        pub fn raze(_: *Ui.Component, _: ?Allocator) void {
            //const exec: *Exec = @fieldParentPtr("component", comp);
        }

        pub fn draw(comp: *Ui.Component, buffer: *Buffer, box: Buffer.Box) void {
            const exoptions: *Exec = @fieldParentPtr("component", comp);

            const drawn, const found = drawPathlist(
                exoptions.alloc,
                buffer,
                exoptions.cursor_idx -| exoptions.history_count,
                9 -| exoptions.history_count,
                sys_exes.items,
                ui_key_buffer.items,
                box,
            ) catch @panic("drawing failed");
            exoptions.drawn = drawn;
            exoptions.found = found;
            comp.draw_needed = false;
        }

        pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
            const exoptions: *Exec = @fieldParentPtr("component", comp);
            if (evt.up) return false;
            comp.draw_needed = true;
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
                    comp.draw_needed = true;
                    return true;
                },
                else => {},
            }
            return true;
        }

        fn drawPathlist(
            a: Allocator,
            buf: *Buffer,
            highlighted: usize,
            allowed: usize,
            bins: []const PathExec,
            prefix: []const u8,
            box: Buffer.Box,
        ) !struct { usize, usize } {
            if (prefix.len == 0 or bins.len == 0) return .{ 0, 0 };
            var drawn: usize = 0;
            var found: usize = 0;

            var hl_box = box.add(.xywh(0, 0, 0, 25 - @as(isize, @intCast(box.h))));
            for (bins) |bin| {
                if (bin.match(prefix)) {
                    found += 1;
                    if (drawn > allowed) continue;
                    try drawText(a, &glyph_cache, buf, bin.name, hl_box.add(.xy(5, 20)), theme.rgb(ARGB, .tertiary));
                    drawn += 1;
                    if (drawn == highlighted) {
                        buf.drawRectangleRounded(
                            ARGB,
                            hl_box.add(.xywh(0, 1, 0, 0)),
                            10,
                            theme.rgb(ARGB, .primary),
                        );
                        buf.drawRectangleRounded(
                            ARGB,
                            hl_box.add(.xywh(1, 2, -2, -2)),
                            9,
                            theme.rgb(ARGB, .primary),
                        );
                    }
                    hl_box.merge(.xywh(0, 20, 0, 0));
                }
            }
            if (highlighted > drawn and drawn > 0) {
                buf.drawRectangleRounded(ARGB, hl_box.add(.xywh(0, 1, 0, 0)), 10, theme.rgb(ARGB, .primary));
                buf.drawRectangleRounded(ARGB, hl_box.add(.xywh(1, 2, -2, -2)), 9, theme.rgb(ARGB, .primary));
            }
            return .{ drawn, found };
        }

        fn getExec(exc: *Exec, str: []const u8, hdrawn: usize) ?[]const u8 {
            const cursor = exc.cursor_idx -| hdrawn;
            if (cursor == 0) return null;
            if (cursor > exc.drawn) return null;
            var idx: usize = 0;
            for (sys_exes.items) |exe| {
                if (std.mem.startsWith(u8, exe.name, str)) {
                    idx += 1;
                    if (idx == cursor) {
                        return exe.arg0;
                    }
                }
            }
            return null;
        }
    };
};

pub fn drawText(
    alloc: Allocator,
    cache: *Ttf.GlyphCache,
    buffer: *Buffer,
    text: []const u8,
    box: Buffer.Box,
    color: ARGB,
) !void {
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try cache.get(alloc, g);
        buffer.drawFont(ARGB, color, .xywh(
            @intCast(@as(i32, @intCast(box.x)) + glyph.off_x + next_x),
            @intCast(@as(i32, @intCast(box.y)) + glyph.off_y),
            @intCast(glyph.width),
            @intCast(glyph.height),
        ), glyph.pixels);
        next_x += @as(i32, @intCast(glyph.width)) + @as(i32, @intCast(glyph.off_x));
    }
}

fn drawColors(size: usize, buffer: Buffer, colors: Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = @intCast(x * 0xff / size);
        const r_y: usize = @intCast(y * 0xff / size);
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c = ARGB.rgb(r, g, b);
        colors.draw(.xywh(x, y, 1, 1), &[1]u32{c.int()});
        const b2: u8 = 0xff - g;
        const c2 = ARGB.rgb(r, g, b2);
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
        const c = ARGB.rgb(r, g, b);
        buf.drawPoint(ARGB, .xy(x, y), c);
    };
}

test {
    _ = &Buffer;
    _ = &ZMenu;
    _ = &Ui;
    _ = &std.testing.refAllDecls(@This());
}

const Charcoal = @import("charcoal");
const Buffer = Charcoal.Buffer;
const Box = Buffer.Box;
const Ttf = Charcoal.TrueType;
const Ui = Charcoal.Ui;
const ARGB = Buffer.ARGB;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const ArrayList = std.ArrayList;
const mem = std.mem;
const eql = mem.eql;
const startsWith = mem.startsWith;
