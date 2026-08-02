pub const std_options: std.Options = .{
    .log_level = .info,
};

pub var write_history: bool = false;
pub var command_history: []Command = &.{};
pub var theme: Theme = .init(ARGB, .eerie_black, .silver, .sinopia, .cornsilk, .avocado);
var sys_exes: ArrayList(PathExec) = .empty;
var user_config: Config = .{};
var environ: std.process.Environ = undefined;
// TODO remove
var _io: Io = undefined;

pub const Config = struct {
    history: bool = true,
    theme: Theme.Typed(ARGB) = .{},
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    _io = init.io;
    const io = _io;
    environ = init.minimal.environ;

    var charcoal: Charcoal = try .init();
    try charcoal.connect();
    defer charcoal.raze();

    // Primary size
    const box: Box = .wh(600, 300);
    // Resize here first to trick wl into the position we want
    var buffer: Buffer = try charcoal.createBufferCapacity(box, box.add(.wh(0, 1000)), "buffer");
    defer buffer.raze();
    try charcoal.wayland.rename("zmenu");
    // lol, I'm sorry

    sys_exes = try .initCapacity(alloc, 8192);

    var args = init.minimal.args.iterate();
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
        if (init.minimal.environ.createMap(alloc)) |env| {
            if (env.get("PATH")) |path| {
                path_env = path;
            }
        } else |_| unreachable;

        // we check args first to allow them to override env
        while (args.next()) |env| {
            if (startsWith(u8, env, "PATH=")) {
                path_env = env[5..];
                break;
            }
        } else if (init.minimal.environ.createMap(alloc)) |env| {
            if (env.get("PATH")) |path| path_env = path;
        } else |_| unreachable;
        const path_count = std.mem.count(u8, path_env orelse "", ":");
        if (path_env == null or path_count == 0) break :b &[_]?[]const u8{"/usr/bin"};
        const paths = try alloc.alloc(?[]const u8, path_count + 1);
        var itr = std.mem.tokenizeScalar(u8, path_env.?, ':');
        for (paths) |*p| {
            p.* = itr.next();
        }
        break :b paths;
    };
    var thread = try io.concurrent(scanPaths, .{ &sys_exes, paths, alloc, io });
    defer thread.await(io);

    try drawing.init(alloc);
    defer drawing.raze();

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

    var root: Root = .{
        .char = &charcoal,
    };
    try charcoal.ui.init(&root.component, &buffer, box, alloc);
    defer charcoal.ui.raze(alloc);
    try charcoal.runRateLimit(.fps(60), io);

    if (root.cmd_box.key_buffer.items.len > 2 and user_config.history) {
        try writeOutHistory(home_dir, command_history, root.cmd_box.key_buffer.items, io);
    } else if (write_history) {
        try writeOutHistory(home_dir, command_history, "", io);
    }
}

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
    var next: Command = .{ .count = 1, .text = new };
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
        for (cmds) |c|
            if (c.count > 0) try w.print("{}::{s}\n", .{ c.count, c.text });

        if (next.count > 0 and next.text.len > 0) try w.print("{}::{s}\n", .{ next.count, next.text });
        try w.flush();
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

pub const Root = struct {
    component: Ui.Component = .{ .vtable = .auto(Root), .children = &.{} },
    tik: usize = 0,
    char: *Charcoal,
    cmd_box: CommandBox = .new,
    options: Options = .new,
    kids: [2]*Ui.Component = undefined,
    m_enabled: bool = false,

    pub const mAxis = null;
    pub const mClick = null;
    pub const raze = null;

    pub fn init(comp: *Ui.Component, box: Box, a: ?Allocator) !void {
        const root: *Root = @fieldParentPtr("component", comp);
        root.cmd_box = .new;
        root.options = .new;

        root.kids = .{ &root.cmd_box.component, &root.options.component };
        comp.children = &root.kids;

        for (comp.children) |c| try c.init(box, a);
    }

    pub fn tick(comp: *Ui.Component, t: usize) void {
        const root: *Root = @fieldParentPtr("component", comp);
        root.tik = t;
    }

    pub fn draw(comp: *Ui.Component, buf: *Buffer, box: Box) void {
        defer comp.draw_needed = false;
        //if (comp.draw_needed) comp.background(buf, box);
        for (comp.children) |child| child.draw(buf, box);
    }

    pub fn background(comp: *Ui.Component, b: *Buffer, box: Box) void {
        defer comp.draw_needed = true;
        b.drawRectangleRoundedFill(ARGB, box, 25, theme.rgba(ARGB, .background));
        for (comp.children) |c| c.background(b, box);
    }

    pub fn mMove(comp: *Ui.Component, mmove: Ui.Event.MMove, box: Box) void {
        const root: *Root = @fieldParentPtr("component", comp);
        if (!root.m_enabled) return;
        if (root.tik < 100) return;
        const options_box = box.add(Options.size);
        if (mmove.withinBox(options_box)) |new| {
            root.options.component.mMove(new, box);
            comp.draw_needed |= root.cmd_box.component.draw_needed or root.options.component.draw_needed;
        }
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        defer comp.draw_needed = true;
        for (comp.children) |child| _ = child.keyPress(evt);
        if (evt.up) return true;

        const root: *Root = @fieldParentPtr("component", comp);
        switch (evt.key) {
            .char => {},
            .ctrl => |ctrl| switch (ctrl) {
                .enter => {
                    if (root.options.history.cursor_idx > 0 or root.options.exec.cursor_idx > 0) {
                        const exe_string: ?[]const u8 = root.options.history.getExec(root.cmd_box.key_buffer.items) orelse
                            root.options.exec.getExec(root.cmd_box.key_buffer.items, root.options.history.drawn);
                        if (exe_string) |exe| {
                            const pid = std.posix.system.fork();
                            if (pid < 0) @panic("everyone knows fork can't fail");
                            if (pid == 0) {
                                exec(exe, _io) catch {};
                            }
                            root.cmd_box.key_buffer.clearRetainingCapacity();
                            root.cmd_box.key_buffer.appendSliceAssumeCapacity(exe);
                            root.char.quit();
                        }
                    } else if (root.cmd_box.key_buffer.items.len > 0) {
                        const pid = std.posix.system.fork();
                        if (pid < 0) @panic("everyone knows fork can't fail");
                        if (pid == 0) {
                            exec(root.cmd_box.key_buffer.items, _io) catch {};
                        }
                        root.char.quit();
                    }
                    return true;
                },
                .escape => {
                    comp.draw_needed = true;
                    if (root.options.history.cursor_idx > 0 or root.options.exec.cursor_idx > 0) {
                        root.options.history.cursor_idx = 0;
                        root.options.exec.cursor_idx = 0;
                    } else if (root.cmd_box.key_buffer.items.len > 0) {
                        root.cmd_box.key_buffer.clearRetainingCapacity();
                    } else {
                        root.char.quit();
                    }
                    return true;
                },
                .arrow_left, .arrow_right => {
                    if (root.options.history.cursor_idx > 0 or root.options.exec.cursor_idx > 0) {
                        const exe_string: ?[]const u8 = root.options.history.getExec(root.cmd_box.key_buffer.items) orelse
                            root.options.exec.getExec(root.cmd_box.key_buffer.items, root.options.history.drawn);
                        if (exe_string) |exe| {
                            root.cmd_box.key_buffer.clearRetainingCapacity();
                            root.cmd_box.key_buffer.appendSliceAssumeCapacity(exe);
                            comp.draw_needed = true;
                            root.options.history.cursor_idx = 0;
                            root.options.exec.cursor_idx = 0;
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

    const State = enum {
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
        tkn: switch (State.start) {
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
        const e = std.process.replace(io, .{
            .argv = &.{argv},
            .expand_arg0 = .expand,
            .environ_map = null,
        });
        @panic(@errorName(e));
    }
};

const CommandBox = @import("CommandBox.zig");

pub const Options = struct {
    component: Ui.Component,
    history: History,
    exec: Exec,
    kids: [2]*Ui.Component = undefined,

    pub const new: Options = .{
        .component = .{ .vtable = .auto(Options), .children = &.{} },
        .history = .{ .component = .{ .vtable = .auto(Options.History), .children = &.{} } },
        .exec = .{ .component = .{ .vtable = .auto(Options.Exec), .children = &.{} } },
    };

    pub const size: Box.Delta = .xywh(35, 70, -70, -75);
    pub const option_size = 20;

    pub const background = null;
    pub const mAxis = null;
    pub const mClick = null;
    pub const raze = null;
    pub const tick = null;

    pub fn init(comp: *Ui.Component, b: Box, a: ?Allocator) error{ OutOfMemory, UnableToInit }!void {
        const opt: *Options = @fieldParentPtr("component", comp);
        opt.* = Options.new;

        opt.kids = .{ &opt.history.component, &opt.exec.component };
        comp.children = &opt.kids;
        opt.exec.history_count = &opt.history.drawn;

        for (comp.children) |c| try c.init(b, a);
    }

    pub fn draw(comp: *Ui.Component, buf: *Buffer, box: Box) void {
        if (!comp.draw_needed) return;
        defer comp.draw_needed = false;

        const history_box: Box = box.add(size);
        buf.drawRectangleFill(ARGB, history_box.add(.wh(0, 1)), theme.rgba(ARGB, .background));

        const count: usize = (box.h - -size.h) / 20;
        const opt: *Options = @fieldParentPtr("component", comp);
        const root: *Root = @fieldParentPtr("options", opt);
        opt.history.limit = if (root.cmd_box.key_buffer.items.len > 0) 3 else count;
        opt.history.component.draw(buf, history_box);

        const path_box = history_box.add(
            .xywh(0, @intCast(20 * (opt.history.drawn)), 0, -20 * @as(isize, @intCast(opt.history.drawn))),
        );

        const cursor: usize = @min(@max(opt.history.cursor_idx, opt.exec.cursor_idx), opt.history.drawn + opt.exec.drawn);
        opt.history.cursor_idx = cursor;
        opt.exec.cursor_idx = cursor;
        opt.exec.component.draw(buf, path_box);
    }

    pub fn keyPress(comp: *Ui.Component, evt: Ui.Event.Key) bool {
        defer comp.draw_needed = true;
        const opt: *Options = @fieldParentPtr("component", comp);
        for (comp.children) |c| _ = c.keyPress(evt);

        const cursor: usize = @min(@max(opt.history.cursor_idx, opt.exec.cursor_idx), opt.history.drawn + opt.exec.drawn);
        opt.history.cursor_idx = cursor;
        opt.exec.cursor_idx = cursor;
        return true;
    }

    pub fn mMove(comp: *Ui.Component, mmove: Ui.Event.MMove, box: Box) void {
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
        cursor_idx: usize = 0,
        history_count: *usize = undefined,
        drawn: usize = 0,
        found: usize = 0,

        pub const background = null;
        pub const mAxis = null;
        pub const mClick = null;
        pub const mMove = null;
        pub const tick = null;
        pub const raze = null;

        pub fn init(_: *Ui.Component, _: Box, _: ?Allocator) Ui.Component.InitError!void {
            //std.debug.print("called\n", .{});
        }

        pub fn draw(comp: *Ui.Component, buf: *Buffer, box: Box) void {
            defer comp.draw_needed = false;
            const ex: *Exec = @fieldParentPtr("component", comp);
            const opts: *Options = @fieldParentPtr("exec", ex);
            const root: *Root = @fieldParentPtr("options", opts);

            ex.drawn, ex.found = drawPathlist(
                buf,
                ex.cursor_idx -| ex.history_count.*,
                9 -| ex.history_count.*,
                sys_exes.items,
                root.cmd_box.key_buffer.items,
                box,
            ) catch @panic("drawing failed");
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
            buf: *Buffer,
            highlighted: usize,
            allowed: usize,
            bins: []const PathExec,
            prefix: []const u8,
            box: Box,
        ) !struct { usize, usize } {
            var drawn: usize = 0;
            var found: usize = 0;
            if (prefix.len == 0 or bins.len == 0)
                return .{ drawn, found };

            var hl_box = box.add(.xywh(0, 0, 0, 25 - @as(isize, @intCast(box.h))));
            for (bins) |bin| {
                if (bin.match(prefix)) {
                    found += 1;
                    if (drawn > allowed) continue;
                    try drawing.text(buf, bin.name, hl_box.add(.xy(5, 20)), theme.rgb(ARGB, .tertiary));
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

test {
    _ = &Buffer;
    _ = &Ui;
    _ = &CommandBox;
    _ = &Options.History;
    _ = &Options.Exec;
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

const Theme = @import("Theme.zig");
const drawing = @import("drawing.zig");
