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
    const exe_install = b.addInstallArtifact(exe, .{});
    exe_install.step.dependOn(&exe.step);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&exe_install.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run main example");
    run_step.dependOn(&run_cmd.step);

    const examples_step = b.step("examples", "Build examples");

    if (std.fs.cwd().openDir("example", .{ .iterate = true })) |d| {
        var it = d.iterate();
        const example_prefix = "ex-";
        const example_suffix = ".zig";
        while (it.next() catch null) |e| {
            if (e.kind != .file) {
                continue;
            }
            if (!std.mem.startsWith(u8, e.name, example_prefix)) {
                continue;
            }
            if (!std.mem.endsWith(u8, e.name, example_suffix)) {
                continue;
            }
            var exe_name = e.name[example_prefix.len..];
            exe_name = exe_name[0..(exe_name.len - example_suffix.len)];
            const example = b.addExecutable(.{
                .name = exe_name,
                .root_source_file = b.path("example").path(b, e.name),
                .target = target,
                .optimize = optimize,
                .strip = true,
            });
            example.root_module.addImport("zargs", mod);
            const example_install = b.addInstallArtifact(example, .{});
            example_install.step.dependOn(&example.step);

            examples_step.dependOn(&example_install.step);
        }
    } else |err| {
        std.log.err("NotFound examples {any}", .{err});
    }

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
