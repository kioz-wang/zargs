# zargs

> 其他语言版本：[en](README.md)

另一个 Zig 编译时参数解析器！开始构建你的命令行吧！

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
const ztype = @import("ztype");
const String = ztype.String;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .about("Remove something")
        .alias("rm").alias("uninstall").alias("del")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", String, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo intended to be showcased in the README.")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", u32).short('v').help("help of verbose"))
        .arg(Arg.optArg("logfile", ?ztype.OpenLazy(.fileCreate, .{ .read = true })).long("log").help("Store log into a file"))
        .sub(Command.new("install")
            .about("Install something")
            .arg(Arg.optArg("count", u32).default(10)
                .short('c').short('n').short('t')
                .long("count").long("cnt")
                .ranges(Ranges(u32).new().u(5, 7).u(13, null)).choices(&.{ 10, 11 }))
            .arg(Arg.posArg("name", String).rawChoices(&.{ "gcc", "clang" }))
            .arg(Arg.optArg("output", String).short('o').long("out"))
            .arg(Arg.optArg("vector", ?@Vector(3, i32)).long("vec")))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var args = cmd.config(.{ .style = .classic }).parse(allocator) catch |e|
        zargs.exitf(e, 1, "\n{s}\n", .{cmd.usageString()});
    defer cmd.destroy(&args, allocator);
    if (args.logfile) |logfile| std.debug.print("Store log into {f}\n", .{logfile});
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

版本号格式为 `vx.y.z[-alpha.n]`：
- x：目前固定为 0，当项目稳定时，将升为 1；之后，当出现不兼容改动时，将增加 1
- y：代表支持的 zig 版本，如`vx.14.z`支持 [zig 0.14.0](https://github.com/ziglang/zig/releases/tag/0.14.0)
- z：迭代版本，包含新特性或其他重要改动的版本（见 [milestones](https://github.com/kioz-wang/zargs/milestones)）
- n: 小版本，包含修复或其他小改动的版本

### 导入核心模块

在你的 `build.zig` 中使用 `addImport`（比如）：

```zig
const exe = b.addExecutable(.{
    .name = "your_app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    }),
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

在源代码中导入后，你将获得以下支持：
- 命令和参数构建器：`Command`, `Arg`
- 多样的迭代器支持：`TokenIter`
- 便捷的退出函数：`exit`, `exitf`

> 详见[文档](#APIs)

```zig
const zargs = @import("zargs");
```

### 导入其他模块

除了核心模块 `zargs`，我还导出了 `fmt` 和 `par` 模块。

#### fmt

`any`，提供了更灵活更强大的格式化方案。

`stringify`，如果一个类包含形如`fname(self, writer)`的方法，那么可以这样得到编译时字符串：

```zig
pub fn getString(self: Self) *const [stringify(self, "fname").count():0]u8 {
    return stringify(self, "fname").literal();
}
```

`comptimeUpperString`，将编译时字符串转为大写。

#### par

`any`，将字符串解析为任何你想要的类型实例。

对于 `struct`，需要实现 `pub fn parse(s: String, a_maybe: ?Allocator) ?Self`。对于 `enum`，默认使用 `std.meta.stringToEnum` 解析，如果实现了 `parse`，那么优先使用。

`destroy`，释放解析到的类型实例。

安全释放，对于解析时未发生内存分配的实例，不会产生实际的释放行为。对于 `struct` 和 `enum`，当实现了 `pub fn destroy(self: Self, a: Allocator) void` 时，才会产生实际的释放行为。

#### ztype

提供 `String`, `LiteralString` 和 `checker`。

为来自`std`的一些结构体提供封装：
- `Open/OpenLazy(...)`：`std.fs.File/Dir`
    - 用法详见[ex-06](examples/ex-06.copy.zig)
- `...`

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
    - `true`：'y', 't', "yes", "true"（忽略大小写）
    - `false`：'n', 'f', "no", "false"（忽略大小写）
- `.enum`：默认使用 `std.meta.stringToEnum`，但 parse 方法优先
- `.struct`：带 parse 方法的结构体
- `.vector`
    - 仅支持基类型为 `.int`, `.float` 和 `.bool` 的
    - `@Vector{1,1}`：`[\(\[\{][ ]*1[ ]*[;:,][ ]*1[ ]*[\)\]\}]`
    - `@Vector{true,false}`：`[\(\[\{][ ]*y[ ]*[;:,][ ]*no[ ]*[\)\]\}]`

如果 T 不存在相关联的默认解析器或`parse`方法，可以为参数自定义解析器（`.parseFn`）。显然，无法为单选项配置解析器，因为这是无意义的。

#### 默认值与可选

选项和参数可配置默认值（`.default`），配置后，该选项和参数就变为可选。

- 即便没有显式配置，单选项也总有默认值：布尔选项默认为 `false`，累加选项默认为 `0`
- 具有可选类型 `?T` 的选项或参数不可显式配置：强制默认为 `null`

> 单选项、具有可选类型的带单参数选项或具有可选类型的单位置参数，总是可选的。

默认值需要在编译期确定。对于带参数选项（`argOpt`）和位置参数（`posArg`），如果无法在编译期确定值（比如在`Windows`上的`std.fs.cwd()`），那么可以配置默认输入（`.rawDefault`），这将在解析器中完成默认值的确定。

#### 取值范围

可以为参数配置值取值范围（`.ranges`, `.choices`），这将在解析后执行有效性检查。

> 不会对默认值执行有效性检查（这是一个特性？😄）

如果为参数构造值取值范围太麻烦，那么可以为参数配置`rawChoices`，这会在解析前进行过滤。

##### 范围

当 T 实现了 `compare` 时，可以为该参数配置值范围。

> 详见 [helper](src/helper.zig).Compare.compare

##### 可选项

当 T 实现了 `equal` 时，可以为该参数配置值可选项。

> 详见 [helper](src/helper.zig).Compare.equal

#### 回调

可配置回调（`.callbackFn`），这将在匹配和解析后执行。

#### 子命令

一个命令不可同时存在位置参数和子命令。

#### 表现形式

对解析器来说，除了累加选项和带不定数量参数的选项，任何选项都不可以重复出现。

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

当然，如果需要，你也可以分步骤构建。只要声明为 `comptime var cmd = Command.new(...)` 即可。

#### 为命令添加回调

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

可为迭代器自定义短选项前缀（`-`）、长选项前缀（`--`）、连接符（`=`）、选项终止符（`--`）（参考[ex-05](examples/ex-05.custom_config.zig)）。

### 编译时生成 usage 和 help

```zig
_ = cmd.usageString();
_ = cmd.helpString();
```

## APIs

See https://kioz-wang.github.io/zargs/#doc

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

- [zpacker](https://github.com/kioz-wang/zpacker/blob/master/src/main.zig)
- [zterm](https://github.com/kioz-wang/zterm/blob/master/cli/main.zig)

## License

[MIT](LICENSE) © Kioz Wang
