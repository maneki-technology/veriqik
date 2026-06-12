const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "veriqik",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Veriqik prototype");
    run_step.dependOn(&run_cmd.step);

    const fast_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const fast_exe = b.addExecutable(.{
        .name = "veriqik-fast",
        .root_module = fast_mod,
    });
    const run_fast_cmd = b.addRunArtifact(fast_exe);
    if (b.args) |args| run_fast_cmd.addArgs(args);
    const run_fast_step = b.step("run-fast", "Run the Veriqik prototype with ReleaseFast optimization");
    run_fast_step.dependOn(&run_fast_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
