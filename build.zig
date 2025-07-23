const std = @import("std");
const Build = std.Build;

const Scanner = @import("wayland").Scanner;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const no_bin = b.option(bool, "no-bin", "do not emit binary") orelse false;

    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/linux-dmabuf/linux-dmabuf-v1.xml");

    // Pass the maximum version implemented by your wayland server or client.
    // Requests, events, enums, etc. from newer versions will not be generated,
    // ensuring forwards compatibility with newer protocol xml.
    // This will also generate code for interfaces created using the provided
    // global interface, in this example wl_keyboard, wl_pointer, xdg_surface,
    // xdg_toplevel, etc. would be generated as well.
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_seat", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 7);
    scanner.generate("zwp_linux_dmabuf_v1", 5);
    //scanner.generate("zwp_linux_buffer_params_v1", 5);
    //scanner.generate("zwp_linux_dmabuf_feedback_v1", 5);
    //scanner.generate("ext_session_lock_manager_v1", 1);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{ .name = "zmenu", .root_module = exe_mod });

    exe.root_module.addImport("wayland", wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};
    const tests = b.addTest(.{ .root_module = exe_mod, .filters = test_filters });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    {
        // test font
        const text_mod = b.createModule(.{
            .root_source_file = b.path("src/gui_demo.zig"),
            .target = target,
            .optimize = optimize,
        });

        const test_text = b.addExecutable(.{ .name = "text_test", .root_module = text_mod });

        test_text.root_module.addImport("wayland", wayland);
        test_text.linkLibC();
        test_text.linkSystemLibrary("wayland-client");

        const text_run_cmd = b.addRunArtifact(test_text);
        const text_run_step = b.step("demo", "Run gui demo test thing");
        text_run_step.dependOn(&text_run_cmd.step);
    }
}
