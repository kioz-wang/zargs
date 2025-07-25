const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_type = b.createModule(.{
        .root_source_file = b.path("src/type.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_fmt = b.addModule("fmt", .{
        .root_source_file = b.path("src/io/fmt.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_fmt.addImport("ztype", mod_type);

    const mod_par = b.addModule("par", .{
        .root_source_file = b.path("src/io/par.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_par.addImport("ztype", mod_type);

    const mod_helper = b.createModule(.{
        .root_source_file = b.path("src/helper.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_helper.addImport("fmt", mod_fmt);
    mod_helper.addImport("ztype", mod_type);

    const mod_iter = b.createModule(.{
        .root_source_file = b.path("src/iter.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_command = b.createModule(.{
        .root_source_file = b.path("src/command/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_command.addImport("ztype", mod_type);
    mod_command.addImport("fmt", mod_fmt);
    mod_command.addImport("par", mod_par);
    mod_command.addImport("helper", mod_helper);
    mod_command.addImport("iter", mod_iter);

    const mod_zargs = b.addModule("zargs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_zargs.addImport("fmt", mod_fmt);
    mod_zargs.addImport("par", mod_par);
    mod_zargs.addImport("helper", mod_helper);
    mod_zargs.addImport("command", mod_command);

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
            });
            ex_exe.root_module.addImport("zargs", mod_zargs);
            ex_exe.root_module.addImport("par", mod_par);
            const ex_install = b.addInstallArtifact(ex_exe, .{});
            ex_install.step.dependOn(&ex_exe.step);

            examples_step.dependOn(&ex_install.step);

            const ex_run_cmd = b.addRunArtifact(ex_exe);
            ex_run_cmd.step.dependOn(&ex_install.step);
            if (b.args) |args| {
                ex_run_cmd.addArgs(args);
            }
            const ex_run_step = b.step(e.name[0..std.mem.indexOfAny(u8, e.name, ".").?], b.fmt("Run example {s}", .{exe_name}));
            ex_run_step.dependOn(&ex_run_cmd.step);
        }
    }

    const test_step = b.step("test", "Run unit tests");
    const test_filters: []const []const u8 = b.option(
        []const []const u8,
        "test_filter",
        "Skip tests that do not match any of the specified filters",
    ) orelse &.{};
    const mods_utest = [_]*std.Build.Module{ mod_type, mod_fmt, mod_par, mod_helper, mod_iter, mod_command };
    for (mods_utest) |unit| {
        test_step.dependOn(&b.addRunArtifact(
            b.addTest(.{
                .root_module = unit,
                .filters = test_filters,
            }),
        ).step);
    }

    const doc = b.addObject(.{
        .name = "doc",
        .root_module = mod_zargs,
    });
    const docs_install = b.addInstallDirectory(.{
        .source_dir = doc.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&docs_install.step);
}
