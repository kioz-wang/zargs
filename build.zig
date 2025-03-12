const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zargs", .{
        .root_source_file = b.path("src/command.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ex_dirname = "examples";
    const examples_step = b.step("examples", "Build examples");

    if ((std.fs.openDirAbsolute(b.build_root.path.?, .{}) catch unreachable).openDir(ex_dirname, .{ .iterate = true }) catch null) |d| {
        var it = d.iterate();
        const ex_prefix = "ex-";
        const ex_suffix = ".zig";
        while (it.next() catch null) |e| {
            if (e.kind != .file) {
                continue;
            }
            if (!std.mem.startsWith(u8, e.name, ex_prefix)) {
                continue;
            }
            if (!std.mem.endsWith(u8, e.name, ex_suffix)) {
                continue;
            }
            var exe_name = e.name[ex_prefix.len..];
            exe_name = exe_name[0..(exe_name.len - ex_suffix.len)];
            const ex_exe = b.addExecutable(.{
                .name = exe_name,
                .root_source_file = b.path(ex_dirname).path(b, e.name),
                .target = target,
                .optimize = optimize,
                .strip = true,
            });
            ex_exe.root_module.addImport("zargs", mod);
            const ex_install = b.addInstallArtifact(ex_exe, .{});
            ex_install.step.dependOn(&ex_exe.step);

            examples_step.dependOn(&ex_install.step);

            const ex_run_cmd = b.addRunArtifact(ex_exe);
            ex_run_cmd.step.dependOn(&ex_install.step);
            if (b.args) |args| {
                ex_run_cmd.addArgs(args);
            }
            const ex_run_step = b.step(e.name[0..(e.name.len - ex_suffix.len)], b.fmt("Run example {s}", .{exe_name}));
            ex_run_step.dependOn(&ex_run_cmd.step);
        }
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
