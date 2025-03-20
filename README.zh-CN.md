# zargs

> 其他语言版本：[en](README.md)

另一个 Zig 编译时参数解析器！开始构建你的命令行吧！

```zig
const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", []const u8, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo intended to be showcased in the README.")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", u32)
            .short('v')
            .help("help of verbose"))
        .arg(Arg.optArg("logfile", ?[]const u8)
            .long("log")
            .help("Store log into a file"))
        .sub(Command.new("install")
            .arg(Arg.posArg("name", []const u8))
            .arg(
            Arg.optArg("output", []const u8)
                .short('o')
                .long("out"),
        ))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args = cmd.parse(allocator) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    defer cmd.destroy(&args, allocator);
    if (args.logfile) |logfile| {
        std.debug.print("Store log into {s}\n", .{logfile});
    }
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

## 背景

作为一门系统级编程语言，应当有一个优雅的命令行参数解析方案。

`zargs` 参考了[Py3 argparse](https://docs.python.org/3.13/library/argparse.html)和[Rust clap](https://docs.rs/clap/latest/clap/)的API风格，在编辑时给出参数的所有信息，在编译时反射出参数结构体和解析器，以及其他一切需要的东西，且支持在运行时为参数动态分配内存。

## 安装

### 获取

获取主线上的最新版本：

```bash
zig fetch --save git+https://github.com/kioz-wang/zargs
```

获取特定的版本（比如 `v0.14.3`）：

```bash
zig fetch --save https://github.com/kioz-wang/zargs/archive/refs/tags/v0.14.3.tar.gz
```

#### 版本说明

> 见 https://github.com/kioz-wang/zargs/releases

版本号格式为 `vx.y.z`：
- x：目前固定为 0，当项目稳定时，将升为 1；之后，当出现不兼容改动时，将增加 1
- y：代表支持的 zig 版本，如`vx.14.z`支持 [zig 0.14.0](https://github.com/ziglang/zig/releases/tag/0.14.0)
- z：迭代版本，其中偶数为包含新特性或其他重要改动的版本（见 [milestones](https://github.com/kioz-wang/zargs/milestones)），奇数为包含修复或其他小改动的版本

### 导入

在你的 `build.zig` 中使用 `addImport`（比如）：

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

在源代码中导入后，你将获得迭代器（`TokenIter`）、命令构建器（`Command`）、通用解析函数（`parseAny`）：

```zig
const zargs = @import("zargs");
```

> 有关以上三大利器的更多信息和用法，请翻阅[文档](#APIs)。

## 特性

### 选项、参数、子命令

#### 术语

- 选项（`opt`）
    - 单选项（`singleOpt`）
        - 布尔选项（`boolOpt`），`T == bool`
        - 累加选项（`repeatOpt`），`@typeInfo(T) == .int`
    - 带参数选项（`argOpt`）
        - 带单参数选项（`singleArgOpt`），T，`?T`
        - 带固定数量参数的选项（`arrayArgOpt`），`[n]T`
        - 带不定数量参数的选项（`multiArgOpt`），`[]T`
- 参数（`arg`）
    - 带选项参数（`optArg`）（等同于带参数选项）
    - 位置参数（`posArg`）
        - 单位置参数（`singlePosArg`），T，`?T`
        - 固定数量的位置参数（`arrayPosArg`），`[n]T`
- 子命令（`subCmd`）

#### 匹配和解析

匹配和解析由迭代器驱动。对选项来说，总是先匹配选项，如果带参数，再尝试解析参数；对位置参数来说，直接尝试解析。

对参数来说，T 必须是可解析的最小单元：`[]const u8` -> T

- `.int`
- `.float`
- `.bool`
- `.enum`：默认使用 `std.meta.stringToEnum`，但 parse 方法优先
- `.struct`：带 parse 方法的结构体

如果 T 不可解析，可以为参数自定义解析器（`.parseFn`）。显然，无法为单选项配置解析器，因为这是无意义的。

#### 默认值与可选

选项和参数可配置默认值（`.default`），配置后，该选项和参数就变为可选。

- 即便没有显式配置，单选项也总有默认值：布尔选项默认为 `false`，累加选项默认为 `0`
- 具有可选类型 `?T` 的选项或参数不可显式配置：强制默认为 `null`

> 单选项、具有可选类型的带单参数选项或具有可选类型的单位置参数，总是可选的。

#### 回调

可配置回调（`.callBackFn`），这将在匹配和解析后执行。

#### 子命令

一个命令不可同时存在位置参数和子命令。

#### 表现形式

对解析器来说，除了累加选项和带不定数量参数的选项，任何选项都不可以重复出现。

各种表现形式主要由迭代器负责支持。

选项又分为短选项和长选项：
- 短选项：`-v`
- 长选项：`--verbose`

带单参数选项可以使用连接符连接选项和参数：
- 短选项：`-o=hello`, `-o hello`
- 长选项：`--output=hello`, `--output hello`

> 不允许丢弃短选项的连接符或空白符，因为这是一种可读性很差的写法！

带固定数量参数的选项，不可使用连接符，且必须一次性给出所有参数，以长选项为例：
```bash
--files f0 f1 f2 # [3]const T
```

带不定数量参数的选项和带单参数选项一样，但可以重复出现，比如：
```bash
--file f0 -v --file=f1 --greet # []const T
```

多个短选项可以共用一个前缀，但如果某个选项带参数，则必须放在最后，比如：
```bash
-Rns
-Rnso hello
-Rnso=hello
```

出现位置参数后，解析器将告知迭代器只返回位置参数，即便参数可能具有选项前缀，比如：
```bash
-o hello a b -v # -o 是带单参数选项，所以 a,b,-v 都是位置参数
```

可以使用选项终止符告知迭代器只返回位置参数，比如：
```bash
--output hello -- a b -v
```

可以使用双引号避免迭代器歧义，比如为了传入负数 `-1`，必须使用双引号：
```bash
--num \"-1\"
```

> 由于 shell 会移除双引号，所以还需要使用转义符！ 如果使用了连接符，则不需要转义：`--num="-1"`。

### 编译时命令构建

如文章开始处的示例，通过链式调用可在一行语句中完成命令构建。

#### 为命令添加回调

```zig
comptime cmd.callBack(struct {
        const C = cmd;
        fn f(_: *C.Result()) void {
            std.debug.print("CallBack of {s}\n", .{ C.name });
        }
    }.f);
```

### 编译时生成解析器

```zig
const args = try cmd.parse(allocator);
defer cmd.destroy(&args, allocator);
```

仅调用 `parse` 即可生成解析器和参数结构体，该方法会在内部创建一个系统迭代器，用完后销毁。

另有 `parseFrom` 支持传入自定义迭代器，且可选择不使用内存分配器。如不使用内存分配器，则不必 defer `destroy`。

#### 获取剩余的命令行参数

当解析器完成任务后，如果仍需要自行处理余下的参数，可以调用迭代器的 `nextAllBase` 方法。

如果仍需要对参数进行解析，可以使用 `parseAny` 函数。

#### 多样的迭代器

可灵活用于真实和测试场景

- 系统迭代器（`init`）：获取真实的命令行参数
- 常规迭代器（`initGeneral`）：从单行字符串中分割命令行参数
- 行迭代器（`initLine`）：和常规迭代器一样，但可以指定分隔符
- 列表迭代器（`initList`）：从给定的字符串列表中迭代

可为迭代器自定义短选项前缀（`-`）、长选项前缀（`--`）、连接符（`=`）、选项终止符（`--`）（使用场景见[表现形式](#表现形式)）。

### 编译时生成 usage 和 help

```zig
_ = cmd.usage();
_ = cmd.help();
```

## APIs

见 https://kioz-wang.github.io/zargs/#doc.command.Command

## 例程

### 内置

> 查看 [这里](examples/)

构建所有例程：

```bash
zig build examples
```

列出所有例程（所有 `ex-` 开头的 step 都是例程）：

```bash
zig build -l
```

运行某个例程：

```bash
zig build ex-01.add -- -h
```

### 更多

> 欢迎提交 PR 链接您使用了 `zargs` 的项目！

更多真实案例：

- [filepacker](https://github.com/kioz-wang/filepacker/blob/master/src/main.zig)

## License

[MIT](LICENSE) © Kioz Wang
