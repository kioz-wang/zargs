# zargs

> other language: [中文简体](README.zh-CN.md)

Another Comptime-argparse for Zig! Let's start to build your command line!

![badge x86_64-linux](https://gist.githubusercontent.com/kioz-wang/ba3b3d2a170d085a3598421203a4988b/raw/027e2590a6ade0e6db60a725a01d651c33bea83a/ci-badge.zargs.x86_64-linux.svg)
![badge aarch64-linux](https://gist.githubusercontent.com/kioz-wang/ba3b3d2a170d085a3598421203a4988b/raw/027e2590a6ade0e6db60a725a01d651c33bea83a/ci-badge.zargs.aarch64-linux.svg)
![badge x86_64-windows](https://gist.githubusercontent.com/kioz-wang/ba3b3d2a170d085a3598421203a4988b/raw/027e2590a6ade0e6db60a725a01d651c33bea83a/ci-badge.zargs.x86_64-windows.svg)
![badge x86_64-macos](https://gist.githubusercontent.com/kioz-wang/ba3b3d2a170d085a3598421203a4988b/raw/027e2590a6ade0e6db60a725a01d651c33bea83a/ci-badge.zargs.x86_64-macos.svg)
![badge aarch64-macos](https://gist.githubusercontent.com/kioz-wang/ba3b3d2a170d085a3598421203a4988b/raw/027e2590a6ade0e6db60a725a01d651c33bea83a/ci-badge.zargs.aarch64-macos.svg)

![asciicast](.asset/demo.gif)

```zig
const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;
const Ranges = zargs.Ranges;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .about("Remove something")
        .alias("rm").alias("uninstall").alias("del")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", []const u8, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo intended to be showcased in the README.")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", u32).short('v').help("help of verbose"))
        .arg(Arg.optArg("logfile", ?[]const u8).long("log").help("Store log into a file"))
        .sub(Command.new("install")
            .about("Install something")
            .arg(Arg.optArg("count", u32).default(10)
                .short('c').short('n').short('t')
                .long("count").long("cnt")
                .ranges(Ranges(u32).new().u(5, 7).u(13, null)).choices(&.{ 10, 11 }))
            .arg(Arg.posArg("name", []const u8).rawChoices(&.{ "gcc", "clang" }))
            .arg(Arg.optArg("output", []const u8).short('o').long("out"))
            .arg(Arg.optArg("vector", ?@Vector(3, i32)).long("vec")))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args = cmd.config(.{ .style = .classic }).parse(allocator) catch |e|
        zargs.exitf(e, 1, "\n{s}\n", .{cmd.usageString()});
    defer cmd.destroy(&args, allocator);
    if (args.logfile) |logfile| std.debug.print("Store log into {s}\n", .{logfile});
    switch (args.action) {
        .install => |a| {
            std.debug.print("Installing {s}\n", .{a.name});
        },
        .remove => |a| {
            std.debug.print("Removing {s}\n", .{a.name});
            std.debug.print("{any}\n", .{a});
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
```

## Background

As a system level programming language, there should be an elegant solution for parsing command line arguments.

`zargs` draws inspiration from the API styles of [Py3 argparse](https://docs.python.org/3.13/library/argparse.html) and [Rust clap](https://docs.rs/clap/latest/clap/). It provides all parameter information during editing, reflects the parameter structure and parser at compile time, along with everything else needed, and supports dynamic memory allocation for parameters at runtime.

## Installation

### fetch

Get the latest version:

```bash
zig fetch --save git+https://github.com/kioz-wang/zargs
```

To fetch a specific version (e.g., `v0.14.3`):

```bash
zig fetch --save https://github.com/kioz-wang/zargs/archive/refs/tags/v0.14.3.tar.gz
```

#### Version Notes

> See https://github.com/kioz-wang/zargs/releases

The version number follows the format `vx.y.z[-alpha.n]`:
- **x**: Currently fixed at 0. It will increment to 1 when the project stabilizes. Afterward, it will increment by 1 for any breaking changes.
- **y**: Represents the supported Zig version. For example, `vx.14.z` supports [Zig 0.14.0](https://github.com/ziglang/zig/releases/tag/0.14.0).
- **z**: Iteration version, indicating releases with new features or significant changes (see [milestones](https://github.com/kioz-wang/zargs/milestones)).
- **n**: Minor version, indicating releases with fixes or minor updates.

### Importing Core Module

In your `build.zig`, use `addImport` (for example):

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

After importing in your source code, you will gain access to the following features:

- Command and argument builders: `Command`, `Arg`
- Versatile iterator support: `TokenIter`
- Convenient exit functions: `exit`, `exitf`

> See the [documentation](#APIs) for details.

```zig
const zargs = @import("zargs");
```

### Importing other modules

In addition to the core module `zargs`, I also exported the `fmt` and `par` modules.

#### fmt

`any`, which provides a more flexible and powerful formatting scheme.

`stringify`, if a class contains a method such as `fname(self, writer)`, then you can obtain a compile-time string like this:

```zig
pub fn getString(self: Self) *const [stringify(self, “fname”).count():0]u8 {
    return stringify(self, “fname”).literal();
}
```

`comptimeUpperString` converts a compile-time string to uppercase.

#### par

`any`, parses the string into any type instance you want.

For `struct`, you need to implement `pub fn parse(s: String, a_maybe: ?Allocator) ?Self`. For `enum`, the default parser is `std.meta.stringToEnum`, but if `parse` is implemented, it will be used instead.

`destroy`, releases the parsed type instance.

Safe release: for instances where no memory allocation occurred during parsing, no actual release action is performed. For `struct` and `enum`, actual release actions are performed only when `pub fn destroy(self: Self, a: Allocator) void` is implemented.

## Features

### Options, Arguments, Subcommands

#### Terminology

- Option (`opt`)
    - Single Option (`singleOpt`)
        - Boolean Option (`boolOpt`), `T == bool`
        - Accumulative Option (`repeatOpt`), `@typeInfo(T) == .int`
    - Option with Argument (`argOpt`)
        - Option with Single Argument (`singleArgOpt`), T, `?T`
        - Option with Fixed Number of Arguments (`arrayArgOpt`), `[n]T`
        - Option with Variable Number of Arguments (`multiArgOpt`), `[]T`
- Argument (`arg`)
    - Option Argument (`optArg`) (equivalent to Option with Argument)
    - Positional Argument (`posArg`)
        - Single Positional Argument (`singlePosArg`), T, `?T`
        - Fixed Number of Positional Arguments (`arrayPosArg`), `[n]T`
- Subcommand (`subCmd`)

#### Matching and Parsing

Matching and parsing are driven by an iterator. For options, the option is always matched first, and if it takes an argument, the argument is then parsed. For positional arguments, parsing is attempted directly.

For arguments, T must be the smallest parsable unit: `[]const u8` -> T

- `.int`
- `.float`
- `.bool`
    - `true`: 'y', 't', "yes", "true" (case insensitive)
    - `false`: 'n', 'f', "no", "false" (case insensitive)
- `.enum`: Uses `std.meta.stringToEnum` by default, but `parse` method takes priority
- `.struct`: Struct with `parse` method
- `.vector`
    - Only supports base types of `.int`, `.float`, and `.bool`
    - `@Vector{1,1}`: `[\(\[\{][ ]*1[ ]*[;:,][ ]*1[ ]*[\)\]\}]`
    - `@Vector{true,false}`: `[\(\[\{][ ]*y[ ]*[;:,][ ]*no[ ]*[\)\]\}]`
- `std.fs.File/Dir`

If type T has no associated default parser or `parse` method, you can specify a custom parser (`.parseFn`) for the parameter. Obviously, single-option parameters cannot have parsers as it would be meaningless.

#### Default Values and Optionality

Options and arguments can be configured with default values (`.default`). Once configured, the option or argument becomes optional.

- Even if not explicitly configured, single options always have default values: boolean options default to `false`, and accumulative options default to `0`.
- Options or arguments with an optional type `?T` cannot be explicitly configured: they are forced to default to `null`.

> Single options, options with a single argument of optional type, or single positional arguments of optional type are always optional.

Default values must be determined at comptime. For `argOpt`, if the value cannot be determined at comptime (e.g., `std.fs.cwd()` at `Windows`), you can configure the default input (`.rawDefault`), which will determine the default value in the perser.

#### Value Ranges

Value ranges (`.ranges`, `.choices`) can be configured for arguments, which are validated after parsing.

> Default values are not validated (intentional feature? 😄)

If constructing value ranges is cumbersome, `.rawChoices` can be used to filter values before parsing.

##### Ranges

When `T` implements compare, value `.ranges` can be configured for the argument.
Choices

> See [helper](src/helper.zig).Compare.compare

##### Choices

When `T` implements equal, value `.choices` can be configured for the argument.

> See [helper](src/helper.zig).Compare.equal

#### Callbacks

A callback (`.callbackFn`) can be configured, which will be executed after matching and parsing.

#### Subcommands

A command cannot have both positional arguments and subcommands simultaneously.

#### Representation

For the parser, except for accumulative options and options with a variable number of arguments, no option can appear more than once.

Options are further divided into short options and long options:
- **Short Option**: `-v`
- **Long Option**: `--verbose`

Options with a single argument can use a connector to link the option and the argument:
- **Short Option**: `-o=hello`, `-o hello`
- **Long Option**: `--output=hello`, `--output hello`

> Dropping the connector or whitespace for short options is not allowed, as it results in poor readability!

For options with a fixed number of arguments, connectors cannot be used, and all arguments must be provided at once. For example, with a long option:
```bash
--files f0 f1 f2 # [3]const T
```

Options with a variable number of arguments are similar to options with a single argument but can appear multiple times, e.g.:
```bash
--file f0 -v --file=f1 --greet # []const T
```

Multiple short options can share a prefix, but if an option takes an argument, it must be placed last, e.g.:
```bash
-Rns
-Rnso hello
-Rnso=hello
```

Once a positional argument appears, the parser informs the iterator to only return positional arguments, even if the arguments might have an option prefix, e.g.:
```bash
-o hello a b -v # -o is an option with a single argument, so a, b, -v are all positional arguments
```

An option terminator can be used to inform the iterator to only return positional arguments, e.g.:
```bash
--output hello -- a b -v
```

Double quotes can be used to avoid iterator ambiguity, e.g., to pass a negative number `-1`, double quotes must be used:
```bash
--num \"-1\"
```

> Since the shell removes double quotes, escape characters are also required! If a connector is used, escaping is unnecessary: `--num="-1"`.

### Compile-Time Command Construction

As shown in the example at the beginning of the article, command construction can be completed in a single line of code through chaining.

Of course, if needed, you can also build it step by step. Simply declare it as `comptime var cmd = Command.new(...)`.

#### CallBackFn for Command

```zig
const install = Command.new("install");
const _demo = Command.new("demo").requireSub("action")
    .sub(install.callBack(struct {
        fn f(_: *install.Result()) void {
            std.debug.print("CallBack of {s}\n", .{install.name});
        }
    }.f));
const demo = _demo.callBack(struct {
    fn f(_: *_demo.Result()) void {
        std.debug.print("CallBack of {s}\n", .{_demo.name});
    }
}.f);
```

### Compile-Time Parser Generation

```zig
const args = try cmd.parse(allocator);
defer cmd.destroy(&args, allocator);
```

Simply call `parse` to generate the parser and argument structure. This method internally creates a system iterator, which is destroyed after use.

Additionally, `parseFrom` supports passing a custom iterator and optionally avoids using a memory allocator. If no allocator is used, there is no need to defer destroy.

#### Retrieving Remaining Command-Line Arguments

When the parser has completed its task, if you still need to handle the remaining arguments manually, you can call the iterator's `nextAllBase` method.

If further parsing of the arguments is required, you can use the `parseAny` function.

#### Versatile iterators

Flexible for real and test scenarios

- System iterator (`init`): get real command line arguments.
- General iterator (`initGeneral`): splits command line arguments from a one-line string.
- Line iterator (`initLine`): same as regular iterator, but you can specify delimiters.
- List iterator (`initList`): iterates over a list of strings.

Short option prefixes (`-`), long option prefixes (`--`), connectors (`=`), option terminators (`--`) can be customized for iterators (see [ex-05](examples/ex-05.custom_config.zig)).

### Compile-Time Usage and Help Generation

```zig
_ = cmd.usageString();
_ = cmd.helpString();
```

## APIs

See https://kioz-wang.github.io/zargs/#doc

## Examples

### builtin

> Look at [here](examples/)

To build all examples:

```bash
zig build examples
```

To list all examples (all step prefixed `ex-` are examples):

```bash
zig build -l
```

To execute an example:

```bash
zig build ex-01.add -- -h
```

### more

> Welcome to submit PRs to link your project that use `zargs`!

More real-world examples are coming!

- [zpacker](https://github.com/kioz-wang/zpacker/blob/master/src/main.zig)
- [zterm](https://github.com/kioz-wang/zterm/blob/master/cli/main.zig)

## License

[MIT](LICENSE) © Kioz Wang
