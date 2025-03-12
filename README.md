# zargs

> other language: [中文简体](README.zh-CN.md)

Another Comptime-argparse for Zig! Let's start to build your command line!

```zig
const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;

pub fn main() !void {
    comptime var cmd: Command = .{ .name = "demo", .use_subCmd = "action", .description = "This is a simple demo" };
    _ = cmd.opt("verbose", u32, .{ .short = 'v' }).optArg("output", []const u8, .{ .short = 'o', .long = "out" });
    comptime var install: Command = .{ .name = "install" };
    comptime var remove: Command = .{ .name = "remove" };
    _ = cmd.subCmd(install.posArg("name", []const u8, .{}).*).subCmd(remove.posArg("name", []const u8, .{}).*);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var it = try TokenIter.init(allocator, .{});
    defer it.deinit();
    _ = try it.next();

    const args = cmd.parse(&it) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    switch (args.action) {
        .install => |a| {
            std.debug.print("Installing {s}\n", .{a.name});
        },
        .remove => |a| {
            std.debug.print("Removing {s}\n", .{a.name});
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
```

## Background

As a system level programming language, there should be an elegant solution for parsing command line arguments.

I've basically looked at various open source implementations on the web, both runtime parsing and compile-time parsing. Developing in a language with strong compile-time capabilities should minimize runtime overhead. For compile-time, I see two routes:
- Given a parameter structure, and additional parameter descriptions (help messages, etc.), then reflect the parser
- directly describe all the information about the parameter, then reflect the parameter structure and the parser

I think the latter is much cleaner to use, and what's there is basically the former, hence `zargs`.

## Installation

> `v0.13.x` only supports [zig 0.13.0](https://github.com/ziglang/zig/releases/tag/0.13.0), support for [zig 0.14.0](https://github.com/ziglang/zig/releases/tag/0.14.0) will be started with `v0.14.0` (see [release v0.14.0](https://github.com/kioz-wang/zargs/milestone/1))

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

After importing the `zargs`, you will obtain the iterator (`TokenIter`), command builder (`Command`), and universal parsing function (`parseAny`):

```zig
const zargs = @import("zargs");
```

> For more information and usage details about these three powerful tools, please refer to the [documentation](#APIs).

## Features

### Versatile iterators

Flexible for real and test scenarios

- System iterator (`init`): get real command line arguments.
- General iterator (`initGeneral`): splits command line arguments from a one-line string.
- Line iterator (`initLine`): same as regular iterator, but you can specify delimiters.
- List iterator (`initList`): iterates over a list of strings.

Short option prefixes (`-`), long option prefixes (`--`), connectors (`=`), option terminators (`--`) can be customized for iterators (see [presentation](#presentation) for usage scenarios).

### Options, Arguments, Subcommands

#### Terminology

- Option (`opt`)
    - Single Option (`singleOpt`)
        - Boolean Option (`boolOpt`), `T == bool`
        - Accumulative Option (`repeatOpt`), `@typeInfo(T) == .int`
    - Option with Argument (`argOpt`)
        - Option with Single Argument (`singleArgOpt`), T
        - Option with Fixed Number of Arguments (`arrayArgOpt`), `[n]const T`
        - Option with Variable Number of Arguments (`multiArgOpt`), `[]const T`
- Argument (`arg`)
    - Option Argument (`optArg`) (equivalent to Option with Argument)
    - Positional Argument (`posArg`)
        - Single Positional Argument (`singlePosArg`), T
        - Fixed Number of Positional Arguments (`arrayPosArg`), `[n]const T`
- Subcommand (`subCmd`)

#### Matching and Parsing

Matching and parsing are driven by an iterator. For options, the option is always matched first, and if it takes an argument, the argument is then parsed. For positional arguments, parsing is attempted directly.

For arguments, T must be the smallest parsable unit: `[]const u8` -> T

- `.int`
- `.float`
- `.bool`
- `.enum`: By default, `std.meta.stringToEnum` is used, but the parser method takes precedence.
- `.struct`: A struct with a parser method.

If T is not parsable, a custom parser (`.parseFn`) can be defined for the argument. Obviously, a parser cannot be configured for a single option, as it would be meaningless.

#### Default Values and Optionality

Options and arguments can be configured with default values (`.default`). Once configured, the option or argument becomes optional.

Even if not explicitly configured, single options always have default values: boolean options default to `false`, and accumulative options default to `0`. Therefore, single options are always optional.

#### Callbacks

A callback (`.callBackFn`) can be configured, which will be executed after matching and parsing.

#### Subcommands

A command cannot have both positional arguments and subcommands simultaneously.

#### Representation

For the parser, except for accumulative options and options with a variable number of arguments, no option can appear more than once.

Various representations are primarily supported by the iterator.

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

```zig
comptime var cmd: Command = .{ .name = "demo" };
```

A command can be defined in a single line, with additional configurations like version, description, author, homepage, etc. Use chaining to add options (`opt`), options with arguments (`optArg`), positional arguments (`posArg`), or subcommands (`subCmd`).

#### CallBackFn for Command

```zig
comptime cmd.callBack(struct {
        const C = cmd;
        fn f(_: *C.Result()) void {
            std.debug.print("CallBack of {s}\n", .{ C.name });
        }
    }.f);
```

### Compile-Time Parser Generation

```zig
const args = try cmd.parse(&it);
```

Simply call `.parse` to generate the parser and argument structure. There is also `parseAlloc` which supports passing a memory allocator:

- Provides support for options with a variable number of arguments.
- Reallocates memory for each string to avoid dangling pointers.
- Use `cmd.destroy(&args, allocator)` to free memory.

#### Retrieving Remaining Command-Line Arguments

When the parser has completed its task, if you still need to handle the remaining arguments manually, you can call the iterator's `nextAllBase` method.

If further parsing of the arguments is required, you can use the `parseAny` function.

### Compile-Time Usage and Help Generation

```zig
_ = cmd.usage();
_ = cmd.help();
```

## APIs

See https://kioz-wang.github.io/zargs/

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

- [filepacker](https://github.com/kioz-wang/filepacker/blob/master/src/main.zig)

## License

[MIT](LICENSE) © Kioz Wang
