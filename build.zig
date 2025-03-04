const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zargs", .{
        .root_source_file = b.path("src/command.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
    });
    exe.root_module.addImport("zargs", mod);
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const run_ut = b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("src/command.zig"),
        .target = target,
        .optimize = optimize,
    }));
    run_ut.skip_foreign_checks = true;
    test_step.dependOn(&run_ut.step);

    const doc = b.addObject(.{
        .name = "doc",
        .root_source_file = b.path("src/command.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs_install = b.addInstallDirectory(.{
        .source_dir = doc.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&docs_install.step);
}
