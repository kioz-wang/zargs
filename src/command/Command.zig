const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;
const Allocator = std.mem.Allocator;

const helper = @import("helper");
const BufferedList = helper.Collection.BufferedList;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const checker = ztype.checker;
const isSlice = checker.isSlice;
const TryOptional = checker.TryOptional;

const TokenIter = @import("token.zig").Iter;
const Config = @import("Config.zig");

const Argument = @import("Argument.zig");

const par = @import("par");
const any = @import("fmt").any;
const stringify = @import("fmt").stringify;

const CFormatter = @import("CFormatter.zig");

const Self = @This();

fn log(self: Self, comptime fmt: String, args: anytype) void {
    std.debug.print(comptimePrint("command({s}) {s}\n", .{ self.name[0], fmt }), args);
}

name: []const LiteralString,
meta: Meta = .{},

_args: []const Argument = &.{},
_cmds: []const Self = &.{},
_stat: struct {
    opt: u32 = 0,
    optArg: u32 = 0,
    posArg: u32 = 0,
    cmd: u32 = 0,
} = .{},
/// Use the built-in `help` option (short option `-h`, long option `--help`; if matched, output the help message and terminate the program).
///
/// It is enabled by default, but if a `opt` or `arg` named "help" is added, it will automatically be disabled.
_builtin_help: ?Argument = Argument.opt("help", bool)
    .help("Show this help then exit").short('h').long("help")
    ._checkOut(),
_config: Config = .{},

const Meta = struct {
    version: ?LiteralString = null,
    about: ?LiteralString = null,
    author: ?LiteralString = null,
    homepage: ?LiteralString = null,
    callbackFn: ?*const anyopaque = null,
    /// Use subcommands, specifying the name of the subcommand's enum union field.
    subName: ?LiteralString = null,
};

pub fn new(name: LiteralString) Self {
    return .{ .name = &.{name} };
}
pub fn version(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.meta.version = s;
    return cmd;
}
pub fn about(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.meta.about = s;
    return cmd;
}
pub fn homepage(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.meta.homepage = s;
    return cmd;
}
pub fn author(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.meta.author = s;
    return cmd;
}
pub fn alias(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.name = cmd.name ++ .{s};
    return cmd;
}
pub fn requireSub(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.meta.subName = s;
    return cmd;
}
pub fn arg(self: Self, argument: Argument) Self {
    var cmd = self;
    const a = argument._checkOut();
    cmd._checkIn(a);
    cmd._args = cmd._args ++ .{a};
    switch (argument.class) {
        .opt => cmd._stat.opt += 1,
        .optArg => cmd._stat.optArg += 1,
        .posArg => cmd._stat.posArg += 1,
    }
    return cmd;
}
pub fn sub(self: Self, cmd: Self) Self {
    if (self.meta.subName == null) {
        @compileError(comptimePrint("please call .requireSub(s) before .sub({s})", .{cmd.name}));
    }
    var c = self;
    for (cmd.name) |s| {
        c._checkInCmdName(s);
    }
    c._cmds = c._cmds ++ .{cmd};
    c._stat.cmd += 1;
    return c;
}
pub fn opt(
    self: Self,
    name: LiteralString,
    T: type,
    common: struct { help: ?LiteralString = null, short: ?u8 = null, long: ?String = null, default: ?T = null, callbackFn: ?fn (*T) void = null },
) Self {
    var argument = Argument.opt(name, T);
    argument.meta.help = common.help;
    if (common.short) |c| {
        argument.meta.short = &.{c};
    }
    if (common.long) |s| {
        argument.meta.long = &.{s};
    }
    if (common.default) |v| {
        argument.meta.default = @ptrCast(&v);
    }
    if (common.callbackFn) |f| {
        argument.meta.callbackFn = @ptrCast(&f);
    }
    return self.arg(argument);
}
pub fn optArg(
    self: Self,
    name: LiteralString,
    T: type,
    common: struct { help: ?LiteralString = null, short: ?u8 = null, long: ?String = null, argName: ?LiteralString = null, default: ?T = null, parseFn: ?par.Fn(T) = null, callbackFn: ?fn (*TryOptional(T)) void = null },
) Self {
    var argument = Argument.optArg(name, T);
    argument.meta.help = common.help;
    if (common.short) |c| {
        argument.meta.short = &.{c};
    }
    if (common.long) |s| {
        argument.meta.long = &.{s};
    }
    argument.meta.argName = common.argName;
    if (common.default) |v| {
        argument = argument.default(v);
    }
    if (common.parseFn) |f| {
        argument.meta.parseFn = @ptrCast(&f);
    }
    if (common.callbackFn) |f| {
        argument.meta.callbackFn = @ptrCast(&f);
    }
    return self.arg(argument);
}
pub fn posArg(
    self: Self,
    name: LiteralString,
    T: type,
    common: struct { help: ?LiteralString = null, argName: ?LiteralString = null, default: ?T = null, parseFn: ?par.Fn(T) = null, callbackFn: ?fn (*TryOptional(T)) void = null },
) Self {
    var argument = Argument.posArg(name, T);
    argument.meta.help = common.help;
    argument.meta.argName = common.argName;
    if (common.default) |v| {
        argument = argument.default(v);
    }
    if (common.parseFn) |f| {
        argument.meta.parseFn = @ptrCast(&f);
    }
    if (common.callbackFn) |f| {
        argument.meta.callbackFn = @ptrCast(&f);
    }
    return self.arg(argument);
}
pub fn config(self: Self, conf: Config) Self {
    conf.token.validate() catch |err| {
        @compileError(comptimePrint("command({s}) invalid config {}: {any}", .{ self.name, conf, err }));
    };
    var cmd = self;
    var cmds: []const Self = &.{};
    cmd._config = conf;
    for (cmd._cmds) |c| {
        cmds = cmds ++ .{c.config(conf)};
    }
    cmd._cmds = cmds;
    return cmd;
}

fn _checkInName(self: *const Self, argument: Argument) void {
    if (self.meta.subName) |s| {
        if (argument.class == .posArg) {
            @compileError(comptimePrint("{} conflicts with subName", .{argument}));
        }
        if (std.mem.eql(u8, s, argument.name)) {
            @compileError(comptimePrint("name of {} conflicts with subName({s})", .{ argument, s }));
        }
    }
    for (self._args) |a| {
        if (std.mem.eql(u8, argument.name, a.name)) {
            @compileError(comptimePrint("name of {} conflicts with {}", .{ argument, a }));
        }
    }
}
fn _checkInShort(self: *const Self, c: u8) void {
    if (self._builtin_help) |a| {
        for (a.meta.short) |_c| {
            if (_c == c) {
                @compileError(comptimePrint("short_prefix({c}) conflicts with builtin {}", .{ c, a }));
            }
        }
    }
    for (self._args) |a| {
        if (a.class == .opt or a.class == .optArg) {
            for (a.meta.short) |_c| {
                if (_c == c) {
                    @compileError(comptimePrint("short_prefix({c}) conflicts with {}", .{ c, a }));
                }
            }
        }
    }
}
fn _checkInLong(self: *const Self, s: String) void {
    if (self._builtin_help) |a| {
        for (a.meta.long) |_l| {
            if (std.mem.eql(u8, _l, s)) {
                @compileError(comptimePrint("long_prefix({s}) conflicts with builtin {}", .{ s, a }));
            }
        }
    }
    for (self._args) |a| {
        if (a.class == .opt or a.class == .optArg) {
            for (a.meta.long) |_l| {
                if (std.mem.eql(u8, _l, s)) {
                    @compileError(comptimePrint("long_prefix({s}) conflicts with {}", .{ s, a }));
                }
            }
        }
    }
}
fn _checkIn(self: *Self, argument: Argument) void {
    self._checkInName(argument);
    if (argument.class == .opt or argument.class == .optArg) {
        if (self._builtin_help) |a| {
            if (std.mem.eql(u8, argument.name, a.name)) {
                self._builtin_help = null;
            }
        }
        for (argument.meta.short) |c| self._checkInShort(c);
        for (argument.meta.long) |s| self._checkInLong(s);
    }
}
fn _checkInCmdName(self: *const Self, name: LiteralString) void {
    for (self._cmds) |c| {
        for (c.name) |s| {
            if (std.mem.eql(u8, s, name)) {
                @compileError(comptimePrint("name({s}) conflicts with subcommand({s})", .{ name, s }));
            }
        }
    }
}

const EnumField = std.builtin.Type.EnumField;
const UnionField = std.builtin.Type.UnionField;

fn SubCmdUnion(self: Self) type {
    var e: []const EnumField = &.{};
    var u: []const UnionField = &.{};
    for (self._cmds, 0..) |c, i| {
        e = e ++ .{EnumField{ .name = c.name[0], .value = i }};
        u = u ++ .{UnionField{ .name = c.name[0], .type = c.Result(), .alignment = @alignOf(c.Result()) }};
    }
    @setEvalBranchQuota(5000); // TODO why?
    const E = @Type(.{ .@"enum" = .{
        .tag_type = std.math.IntFittingRange(0, e.len - 1),
        .fields = e,
        .decls = &.{},
        .is_exhaustive = true,
    } });
    const U = @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = E,
        .fields = u,
        .decls = &.{},
    } });
    return U;
}

fn subCmdField(self: Self) std.builtin.Type.StructField {
    const U = self.SubCmdUnion();
    return .{
        .alignment = @alignOf(U),
        .default_value_ptr = null,
        .is_comptime = false,
        .name = self.meta.subName.?,
        .type = U,
    };
}

pub fn Result(self: Self) type {
    var r = @typeInfo(struct {}).@"struct";
    for (self._args) |m| {
        r.fields = r.fields ++ .{m._toField()};
    }
    if (self.meta.subName) |s| {
        if (self._stat.cmd == 0) {
            @compileError(comptimePrint("please call .sub(cmd) to add subcommands because subName({s}) is given", .{s}));
        }
        r.fields = r.fields ++ .{self.subCmdField()};
    }
    return @Type(.{ .@"struct" = r });
}

pub fn callBack(self: Self, f: fn (*self.Result()) void) Self {
    var cmd = self;
    cmd.meta.callbackFn = @ptrCast(&f);
    return cmd;
}

fn _match(self: Self, t: String) bool {
    for (self.name) |s| {
        if (std.mem.eql(u8, s, t)) return true;
    }
    return false;
}

const Error = error{
    RepeatOpt,
    UnknownOpt,
    MissingOptArg,
    InvalidOptArg,
    MissingPosArg,
    InvalidPosArg,
    MissingSubCmd,
    UnknownSubCmd,
    Allocator,
    TokenIter,
};

fn _errCastIter(self: Self, cap: TokenIter.Error) Error {
    self.log("Error <{any}> from TokenIter", .{cap});
    return Error.TokenIter;
}

fn _errCastArg(self: Self, cap: Argument.Error, is_pos: bool) Error {
    return switch (cap) {
        Argument.Error.Allocator => blk: {
            self.log("Error <{any}> from Allocator", .{cap});
            break :blk Error.Allocator;
        },
        Argument.Error.Invalid => if (is_pos) Error.InvalidPosArg else Error.InvalidOptArg,
        Argument.Error.Missing => if (is_pos) Error.MissingPosArg else Error.MissingOptArg,
        else => unreachable,
    };
}

pub fn parse(self: Self, a: Allocator) !self.Result() {
    var it = try TokenIter.init(a, .{});
    defer it.deinit();
    _ = try it.next();
    return self.parseFrom(&it, a);
}

pub fn parseFrom(self: Self, it: *TokenIter, a_maybe: ?Allocator) Error!self.Result() {
    var matched: BufferedList(self._stat.opt + self._stat.optArg, String) = .{};
    matched.init();

    var r = helper.initStruct(self.Result());

    it.reinit(self._config.token);

    while (it.view() catch |e| return self._errCastIter(e)) |t| {
        switch (t) {
            .opt => {
                var hit = false;
                if (self._builtin_help) |a| {
                    if (a._match(t)) {
                        helper.exitf(null, 0, "{s}", .{self.helpString()});
                    }
                }
                inline for (self._args) |a| {
                    if (a.class == .posArg) continue;
                    hit = a._consume(&r, it, a_maybe) catch |e| return self._errCastArg(e, false);
                    if (hit) {
                        if (matched.pushOnce(a.name) == null) {
                            if ((a.class == .opt and a.T != bool) or (a.class == .optArg and isSlice(a.T))) break;
                            self.log("match {} again with {}", .{ a, t.opt });
                            return Error.RepeatOpt;
                        }
                        break;
                    }
                }
                if (hit) continue;
                self.log("unknown option {}", .{t.opt});
                return Error.UnknownOpt;
            },
            .posArg, .arg => {
                it.fsm_to_pos();
                break;
            },
            else => unreachable,
        }
    }
    inline for (self._args) |a| {
        if (a.class != .optArg) continue;
        if (a.meta.default == null) {
            if (!isSlice(a.T) and !matched.contain(a.name)) {
                if (a.meta.rawDefault) |s| {
                    @field(r, a.name) = a.parseValue(s, a_maybe) orelse return Error.InvalidOptArg;
                } else {
                    self.log("requires {} but not found", .{a});
                    return Error.MissingOptArg;
                }
            }
        }
    }
    inline for (self._args) |a| {
        if (a.class != .posArg) continue;
        if (a.meta.default == null) {
            _ = a._consume(&r, it, a_maybe) catch |e| return self._errCastArg(e, true);
        }
    }
    inline for (self._args) |a| {
        if (a.class != .posArg) continue;
        if (a.meta.default != null) {
            if ((it.view() catch |e| return self._errCastIter(e)) == null) break;
            _ = a._consume(&r, it, a_maybe) catch |e| return self._errCastArg(e, true);
        }
    }
    if (self.meta.subName) |s| {
        if ((it.view() catch |e| return self._errCastIter(e)) == null) {
            self.log("requires subcommand but not found", .{});
            return Error.MissingSubCmd;
        }
        const t = (it.viewMust() catch unreachable).as_posArg().posArg;
        var hit = false;
        inline for (self._cmds) |c| {
            if (c._match(t)) {
                _ = it.next() catch unreachable;
                @field(r, s) = @unionInit(self.SubCmdUnion(), c.name[0], try c.parseFrom(it, a_maybe));
                hit = true;
                break;
            }
        }
        if (!hit) {
            self.log("unknown subcommand {s}", .{(it.viewMust() catch unreachable).as_posArg().posArg});
            return Error.UnknownSubCmd;
        }
    }
    if (self.meta.callbackFn) |f| {
        const p: *const fn (*self.Result()) void = @ptrCast(@alignCast(f));
        p(&r);
    }
    return r;
}

pub fn destroy(self: Self, r: *self.Result(), a_maybe: ?Allocator) void {
    inline for (self._args) |a| {
        a._destroy(r, a_maybe);
    }
    if (self.meta.subName) |s| {
        inline for (self._cmds) |c| {
            if (std.enums.nameCast(std.meta.Tag(self.SubCmdUnion()), c.name[0]) == @field(r, s)) {
                c.destroy(&@field(@field(r, s), c.name[0]), a_maybe);
                break;
            }
        }
    }
}
fn formatter(self: Self) CFormatter {
    return .init(self);
}
pub fn usageString(self: Self) *const [stringify(self.formatter(), "usage").count():0]u8 {
    return stringify(self.formatter(), "usage").literal();
}
pub fn helpString(self: Self) *const [stringify(self.formatter(), "help").count():0]u8 {
    return stringify(self.formatter(), "help").literal();
}

const _test = struct {
    test "Compile Errors" {
        // TODO https://github.com/ziglang/zig/issues/513
        return error.SkipZigTest;
    }

    test "Parse Error without subcommand" {
        const cmd = Self.new("cmd")
            .arg(Argument.optArg("int", i32).long("int").help("Required integer"))
            .arg(Argument.optArg("files", []const String).short('f').long("file").help("Multiple files"))
            .arg(Argument.posArg("pos", u32).help("Required position argument"));
        {
            var it = try TokenIter.initList(&.{"-"}, .{});
            try testing.expectError(Error.TokenIter, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"--int="}, .{});
            try testing.expectError(Error.MissingOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"--int=a"}, .{});
            try testing.expectError(Error.InvalidOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{ "--int=1", "--int", "2" }, .{});
            try testing.expectError(Error.RepeatOpt, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"-t"}, .{});
            try testing.expectError(Error.UnknownOpt, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"--"}, .{});
            try testing.expectError(Error.MissingOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{ "--int=1", "--" }, .{});
            try testing.expectError(Error.MissingPosArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{ "--int=1", "--", "a" }, .{});
            try testing.expectError(Error.InvalidPosArg, cmd.parseFrom(&it, null));
        }
    }

    test "Parse Error with subcommand" {
        const cmd = Self.new("cmd").requireSub("sub")
            .arg(Argument.opt("verbose", u8).short('v'))
            .sub(Self.new("subcmd0"))
            .sub(Self.new("subcmd1").alias("alias0"));
        {
            var it = try TokenIter.initList(&.{"-v"}, .{});
            try testing.expectError(Error.MissingSubCmd, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"subcmd2"}, .{});
            try testing.expectError(Error.UnknownSubCmd, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&.{"alias0"}, .{});
            try testing.expectEqual(
                cmd.Result(){ .sub = .{ .subcmd1 = .{} } },
                try cmd.parseFrom(&it, null),
            );
        }
    }

    test "Parse with callBack" {
        comptime var cmd = Self.new("cmd")
            .arg(Argument.opt("verbose", u8).short('v'))
            .arg(Argument.optArg("count", u32).short('c').default(3).callbackFn(struct {
                fn f(v: *u32) void {
                    v.* *= 10;
                }
            }.f))
            .arg(Argument.posArg("pos", String));
        const R = cmd.Result();
        cmd = cmd.callBack(struct {
            fn f(r: *R) void {
                std.debug.print("verbose is {d}\n", .{r.verbose});
                r.*.verbose += 10;
            }
        }.f);
        {
            var it = try TokenIter.initLine("-c 2 -vv hello", null, .{});
            const args = try cmd.parseFrom(&it, null);
            try testing.expectEqualDeep(
                R{ .verbose = 12, .count = 20, .pos = "hello" },
                args,
            );
        }
        {
            var it = try TokenIter.initLine("-v hello", null, .{});
            const args = try cmd.parseFrom(&it, null);
            try testing.expectEqualDeep(
                R{ .verbose = 11, .count = 3, .pos = "hello" },
                args,
            );
        }
    }

    test "Parse struct with par and allocator" {
        const Mem = struct {
            buf: []u8,
            pub fn parse(s: String, a_maybe: ?Allocator) ?@This() {
                const a = a_maybe orelse return null;
                const len = par.any(usize, s, null) orelse return null;
                const buf = a.alloc(u8, len) catch return null;
                return .{ .buf = buf };
            }
            pub fn destroy(self: *@This(), a_maybe: ?Allocator) void {
                a_maybe.?.free(self.buf);
            }
        };
        const cmd = Self.new("cmd")
            .posArg("mem", [2]Mem, .{ .callbackFn = struct {
                fn f(v: *[2]Mem) void {
                    for (v.*) |m| {
                        const msg = "Hello World!";
                        const len = @min(m.buf.len, msg.len);
                        @memcpy(m.buf, msg[0..len]);
                    }
                }
            }.f })
            .optArg("number", []i32, .{ .short = 'i' })
            .optArg("message", []String, .{ .short = 'm' });
        const R = cmd.Result();
        var args: R = undefined;
        {
            var it = try TokenIter.initLine("-m hello -i 0xf -i 6 -m world 2 7", null, .{});
            args = try cmd.parseFrom(&it, testing.allocator);
        }
        try testing.expectEqual(0xf, args.number[0]);
        try testing.expectEqual(6, args.number[1]);
        args.number[1] *= 10;
        try testing.expectEqual(60, args.number[1]);
        try testing.expectEqualStrings("hello", args.message[0]);
        try testing.expectEqualStrings("world", args.message[1]);
        try testing.expectEqualStrings("He", args.mem[0].buf);
        try testing.expectEqualStrings("Hello W", args.mem[1].buf);
        defer cmd.destroy(&args, testing.allocator);
    }

    test "Parse with optional type" {
        const cmd = Self.new("cmd")
            .arg(Argument.optArg("integer", ?i32).long("int"))
            .arg(Argument.optArg("output", ?String).long("out"))
            .arg(Argument.posArg("message", ?String));
        const R = cmd.Result();
        {
            var it = try TokenIter.initLine("--int 3 --out hello world", null, .{});
            var args = try cmd.parseFrom(&it, testing.allocator);
            defer cmd.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(
                R{ .integer = 3, .output = "hello", .message = "world" },
                args,
            );
        }
        {
            var it = try TokenIter.initLine("", null, .{});
            var args = try cmd.parseFrom(&it, testing.allocator);
            defer cmd.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(
                R{ .integer = null, .output = null, .message = null },
                args,
            );
        }
    }

    test "Parse with custom config" {
        const _d = Self.new("D")
            .arg(Argument.opt("verbose", u32).short('v').long("verbose"))
            .arg(Argument.opt("ignore", bool).short('i').long("ignore"))
            .arg(Argument.optArg("output", String).long("out").short('o'))
            .arg(Argument.posArg("input", String));
        const _c = Self.new("C")
            .arg(Argument.opt("verbose", u32).short('v').long("verbose"))
            .arg(Argument.opt("ignore", bool).short('i').long("ignore"))
            .arg(Argument.optArg("output", String).long("out").short('o'));
        const _b = Self.new("B")
            .arg(Argument.opt("verbose", u32).short('v').long("verbose"))
            .arg(Argument.opt("ignore", bool).short('i').long("ignore"))
            .arg(Argument.optArg("output", String).long("out").short('o'));
        const _a = Self.new("A")
            .arg(Argument.opt("verbose", u32).short('v').long("verbose"))
            .arg(Argument.opt("ignore", bool).short('i').long("ignore"))
            .arg(Argument.optArg("output", String).long("out").short('o'));
        const R = _a.requireSub("sub").sub(
            _b.requireSub("sub").sub(
                _c.requireSub("sub").sub(_d),
            ),
        ).Result();
        const r = R{ .verbose = 2, .ignore = false, .output = "aa", .sub = .{
            .B = .{ .verbose = 1, .ignore = true, .output = "bb", .sub = .{
                .C = .{ .verbose = 1, .ignore = false, .output = "cc", .sub = .{
                    .D = .{ .verbose = 1, .ignore = true, .output = "dd", .input = "in" },
                } },
            } },
        } };
        const complex_config: Config = .{ .token = .{ .prefix = .{ .long = "+++", .short = "@" }, .terminator = "**", .connector = "=>" } };
        {
            const a = _a.requireSub("sub").sub(
                _b.requireSub("sub").sub(
                    _c.requireSub("sub").sub(_d),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out=bb C -vo cc -- D -vio=dd in", null, .{});
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.config(.{ .token = .{
                    .terminator = "##",
                    .connector = ":",
                } }).requireSub("sub").sub(
                    _c.config(complex_config).requireSub("sub").sub(_d),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C @v +++out=>cc ** D -vio=dd in", null, .{});
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.config(.{ .token = .{
                    .terminator = "##",
                    .connector = ":",
                } }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d.config(complex_config),
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C -vo=cc -- D @vio=>dd in", null, .{});
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.config(.{ .token = .{
                    .terminator = "##",
                    .connector = ":",
                } }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d,
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C -v --out=cc -- D -vio=dd in", null, .{ .connector = "=>" });
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.config(.{ .token = .{
                .terminator = "##",
                .connector = ":",
            } }).requireSub("sub").sub(
                _b.requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d.config(complex_config),
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo:aa ## B -vi --out=bb -- C -v --out=cc -- D @vio=>dd in", null, .{});
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.config(.{ .token = .{
                    .terminator = "##",
                    .connector = ":",
                } }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(_d).config(complex_config),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C @v +++out=>cc ** D @vio=>dd in", null, .{});
            var args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
    }

    test "Bug, destroy default String" {
        const cmd = Self.new("cmd").arg(Argument.posArg("pos", String).default("hello"));
        var it = try TokenIter.initList(&.{}, .{});
        var args = try cmd.parseFrom(&it, testing.allocator);
        cmd.destroy(&args, testing.allocator);
    }
};

test {
    _ = _test;
}
