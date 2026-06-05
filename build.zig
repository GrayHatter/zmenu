const std = @import("std");
const Build = std.Build;

const Scanner = @import("wayland").Scanner;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const no_bin = b.option(bool, "no-bin", "do not emit binary") orelse false;
    const testing_debug = b.option(bool, "testing-debug", "enable additional testing debugging") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "timings", testing_debug);

    const charcoal = b.dependency("charcoal", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "zmenu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "charcoal", .module = charcoal.module("charcoal") },
            },
        }),
    });
    exe.root_module.addImport("charcoal", charcoal.module("charcoal"));
    exe.root_module.addOptions("config", options);

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    tests.filters = b.option([]const []const u8, "test-filter", "run matching tests") orelse &.{};

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
