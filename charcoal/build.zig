const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/linux-dmabuf/linux-dmabuf-v1.xml");

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 7);
    scanner.generate("zwp_linux_dmabuf_v1", 5);
    //scanner.generate("zwp_linux_buffer_params_v1", 5);
    //scanner.generate("zwp_linux_dmabuf_feedback_v1", 5);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const charcoal = b.addModule("charcoal", .{
        .root_source_file = b.path("src/charcoal.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .link_libc = true,
    });

    charcoal.addImport("wayland", wayland);
    charcoal.linkSystemLibrary("wayland-client", .{});

    const charcoal_tests = b.addTest(.{ .root_module = charcoal });
    const run_charcoal_tests = b.addRunArtifact(charcoal_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_charcoal_tests.step);
}
