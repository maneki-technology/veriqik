const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const veriqik = b.addModule("veriqik", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const executable = b.addExecutable(.{
        .name = "veriqik",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "veriqik", .module = veriqik },
            },
        }),
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run Veriqik");
    run_step.dependOn(&run_command.step);

    const module_tests = b.addTest(.{
        .root_module = veriqik,
    });
    const run_module_tests = b.addRunArtifact(module_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_module_tests.step);
}
