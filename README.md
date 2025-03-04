# zargs
Another Comptime-argparse for Zig! Let's start to build your command line!

## Installation

### fetch

Get the latest version:

```bash
zig fetch --save git+https://github.com/kioz-wang/zargs
```

Get a tagged version (e.g. `v0.13.0`):

```bash
# See: https://github.com/kioz-wang/zargs/releases
zig fetch --save https://github.com/kioz-wang/zargs/archive/refs/tags/v0.13.0.tar.gz
```

### import

Use `addImport` in your `build.zig` (e.g.):

```zig
const exe = b.addExecutable(.{
    .name = "your_app",
    .root_source_file = b.path("src/main.zig"),
    .target = b.standardTargetOptions(.{}),
    .optimize = b.standardOptimizeOption(.{}),
});
exe.root_module.addImport("zargs", b.dependency("zargs", .{}).module("zargs"));
b.installArtifact(exe);

const run_cmd = b.addRunArtifact(exe);
run_cmd.step.dependOn(b.getInstallStep());
if (b.args) |args| {
    run_cmd.addArgs(args);
}

const run_step = b.step("run", "Run the app");
run_step.dependOn(&run_cmd.step);
```

## Features

TBD

## APIs

TBD

## Examples

Look at [code](example/main.zig)

More examples are coming!
