const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;
const Allocator = std.mem.Allocator;

const helper = @import("helper");
const StringSet = helper.Collection.StringSet;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const Type = ztype.Type;
const isSlice = Type.isSlice;
const TryOptional = Type.TryOptional;

const TokenIter = @import("token.zig").Iter;
const Config = @import("token.zig").Config;

const Arg = @import("Arg.zig");

const par = @import("par");
const any = @import("fmt").any;
const stringify = @import("fmt").stringify;

const Self = @This();

fn log(self: Self, comptime fmt: String, args: anytype) void {
    std.debug.print(comptimePrint("command({s}) {s}\n", .{ self.name[0], fmt }), args);
}

name: []const LiteralString,
common: Common = .{},

_args: []const Arg = &.{},
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
_builtin_help: ?Arg = Arg.opt("help", bool)
    .help("Show this help then exit").short('h').long("help")
    ._checkOut(),
_config: Config = .{},

const Common = struct {
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
    cmd.common.version = s;
    return cmd;
}
pub fn about(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.common.about = s;
    return cmd;
}
pub fn homepage(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.common.homepage = s;
    return cmd;
}
pub fn author(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.common.author = s;
    return cmd;
}
pub fn alias(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.name = cmd.name ++ .{s};
    return cmd;
}
pub fn requireSub(self: Self, s: LiteralString) Self {
    var cmd = self;
    cmd.common.subName = s;
    return cmd;
}
pub fn arg(self: Self, meta: Arg) Self {
    var cmd = self;
    const m = meta._checkOut();
    cmd._checkIn(m);
    cmd._args = cmd._args ++ .{m};
    switch (meta.class) {
        .opt => cmd._stat.opt += 1,
        .optArg => cmd._stat.optArg += 1,
        .posArg => cmd._stat.posArg += 1,
    }
    return cmd;
}
pub fn sub(self: Self, cmd: Self) Self {
    if (self.common.subName == null) {
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
    var meta = Arg.opt(name, T);
    meta.common.help = common.help;
    if (common.short) |c| {
        meta.common.short = &.{c};
    }
    if (common.long) |s| {
        meta.common.long = &.{s};
    }
    if (common.default) |v| {
        meta.common.default = @ptrCast(&v);
    }
    if (common.callbackFn) |f| {
        meta.common.callbackFn = @ptrCast(&f);
    }
    return self.arg(meta);
}
pub fn optArg(
    self: Self,
    name: LiteralString,
    T: type,
    common: struct { help: ?LiteralString = null, short: ?u8 = null, long: ?String = null, argName: ?LiteralString = null, default: ?T = null, parseFn: ?par.Fn(T) = null, callbackFn: ?fn (*TryOptional(T)) void = null },
) Self {
    var meta = Arg.optArg(name, T);
    meta.common.help = common.help;
    if (common.short) |c| {
        meta.common.short = &.{c};
    }
    if (common.long) |s| {
        meta.common.long = &.{s};
    }
    meta.common.argName = common.argName;
    if (common.default) |v| {
        meta = meta.default(v);
    }
    if (common.parseFn) |f| {
        meta.common.parseFn = @ptrCast(&f);
    }
    if (common.callbackFn) |f| {
        meta.common.callbackFn = @ptrCast(&f);
    }
    return self.arg(meta);
}
pub fn posArg(
    self: Self,
    name: LiteralString,
    T: type,
    common: struct { help: ?LiteralString = null, argName: ?LiteralString = null, default: ?T = null, parseFn: ?par.Fn(T) = null, callbackFn: ?fn (*TryOptional(T)) void = null },
) Self {
    var meta = Arg.posArg(name, T);
    meta.common.help = common.help;
    meta.common.argName = common.argName;
    if (common.default) |v| {
        meta = meta.default(v);
    }
    if (common.parseFn) |f| {
        meta.common.parseFn = @ptrCast(&f);
    }
    if (common.callbackFn) |f| {
        meta.common.callbackFn = @ptrCast(&f);
    }
    return self.arg(meta);
}
pub fn setConfig(self: Self, config: Config) Self {
    config.validate() catch |err| {
        @compileError(comptimePrint("command({s}) invalid config {}: {any}", .{ self.name, config, err }));
    };
    var cmd = self;
    var cmds: []const Self = &.{};
    cmd._config = config;
    for (cmd._cmds) |c| {
        cmds = cmds ++ .{c.setConfig(config)};
    }
    cmd._cmds = cmds;
    return cmd;
}

fn _checkInName(self: *const Self, meta: Arg) void {
    if (self.common.subName) |s| {
        if (meta.class == .posArg) {
            @compileError(comptimePrint("{} conflicts with subName", .{meta}));
        }
        if (std.mem.eql(u8, s, meta.name)) {
            @compileError(comptimePrint("name of {} conflicts with subName({s})", .{ meta, s }));
        }
    }
    for (self._args) |m| {
        if (std.mem.eql(u8, meta.name, m.name)) {
            @compileError(comptimePrint("name of {} conflicts with {}", .{ meta, m }));
        }
    }
}
fn _checkInShort(self: *const Self, c: u8) void {
    if (self._builtin_help) |m| {
        for (m.common.short) |_c| {
            if (_c == c) {
                @compileError(comptimePrint("short_prefix({c}) conflicts with builtin {}", .{ c, m }));
            }
        }
    }
    for (self._args) |m| {
        if (m.class == .opt or m.class == .optArg) {
            for (m.common.short) |_c| {
                if (_c == c) {
                    @compileError(comptimePrint("short_prefix({c}) conflicts with {}", .{ c, m }));
                }
            }
        }
    }
}
fn _checkInLong(self: *const Self, s: String) void {
    if (self._builtin_help) |m| {
        for (m.common.long) |_l| {
            if (std.mem.eql(u8, _l, s)) {
                @compileError(comptimePrint("long_prefix({s}) conflicts with builtin {}", .{ s, m }));
            }
        }
    }
    for (self._args) |m| {
        if (m.class == .opt or m.class == .optArg) {
            for (m.common.long) |_l| {
                if (std.mem.eql(u8, _l, s)) {
                    @compileError(comptimePrint("long_prefix({s}) conflicts with {}", .{ s, m }));
                }
            }
        }
    }
}
fn _checkIn(self: *Self, meta: Arg) void {
    self._checkInName(meta);
    if (meta.class == .opt or meta.class == .optArg) {
        if (self._builtin_help) |m| {
            if (std.mem.eql(u8, meta.name, m.name)) {
                self._builtin_help = null;
            }
        }
        for (meta.common.short) |c| self._checkInShort(c);
        for (meta.common.long) |s| self._checkInLong(s);
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
        .name = self.common.subName.?,
        .type = U,
    };
}

pub fn Result(self: Self) type {
    var r = @typeInfo(struct {}).@"struct";
    for (self._args) |m| {
        r.fields = r.fields ++ .{m._toField()};
    }
    if (self.common.subName) |s| {
        if (self._stat.cmd == 0) {
            @compileError(comptimePrint("please call .sub(cmd) to add subcommands because subName({s}) is given", .{s}));
        }
        r.fields = r.fields ++ .{self.subCmdField()};
    }
    return @Type(.{ .@"struct" = r });
}

pub fn callBack(self: Self, f: fn (*self.Result()) void) Self {
    var cmd = self;
    cmd.common.callbackFn = @ptrCast(&f);
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

fn _errCastArg(self: Self, cap: Arg.Error, is_pos: bool) Error {
    return switch (cap) {
        Arg.Error.Allocator => blk: {
            self.log("Error <{any}> from Allocator", .{cap});
            break :blk Error.Allocator;
        },
        Arg.Error.Invalid => if (is_pos) Error.InvalidPosArg else Error.InvalidOptArg,
        Arg.Error.Missing => if (is_pos) Error.MissingPosArg else Error.MissingOptArg,
        else => unreachable,
    };
}

pub fn parse(self: Self, a: Allocator) !self.Result() {
    var it = try TokenIter.init(a, .{});
    defer it.deinit();
    _ = try it.next();
    return self.parseFrom(&it, a);
}

pub fn parseFrom(self: Self, it: *TokenIter, a: ?Allocator) Error!self.Result() {
    var matched: StringSet(self._stat.opt + self._stat.optArg) = .{};
    matched.init();

    var r = std.mem.zeroInit(self.Result(), if (self.common.subName) |s| blk: {
        comptime var info = @typeInfo(struct {}).@"struct";
        info.fields = info.fields ++ .{self.subCmdField()};
        const I = @Type(.{ .@"struct" = info });
        var i: I = undefined;
        @field(i, s) = undefined;
        break :blk i;
    } else .{});

    it.reinit(self._config);

    while (it.view() catch |e| return self._errCastIter(e)) |t| {
        switch (t) {
            .opt => {
                var hit = false;
                if (self._builtin_help) |m| {
                    if (m._match(t)) {
                        helper.exitf(null, 0, "{s}", .{self.helpString()});
                    }
                }
                inline for (self._args) |m| {
                    if (m.class == .posArg) continue;
                    hit = m._consume(&r, it, a) catch |e| return self._errCastArg(e, false);
                    if (hit) {
                        if (!matched.add(m.name)) {
                            if ((m.class == .opt and m.T != bool) or (m.class == .optArg and isSlice(m.T))) break;
                            self.log("match {} again with {}", .{ m, t.opt });
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
    inline for (self._args) |m| {
        if (m.class != .optArg) continue;
        if (m.common.default == null) {
            if (!isSlice(m.T) and !matched.contain(m.name)) {
                self.log("requires {} but not found", .{m});
                return Error.MissingOptArg;
            }
        }
    }
    inline for (self._args) |m| {
        if (m.class != .posArg) continue;
        if (m.common.default == null) {
            _ = m._consume(&r, it, a) catch |e| return self._errCastArg(e, true);
        }
    }
    inline for (self._args) |m| {
        if (m.class != .posArg) continue;
        if (m.common.default != null) {
            if ((it.view() catch |e| return self._errCastIter(e)) == null) break;
            _ = m._consume(&r, it, a) catch |e| return self._errCastArg(e, true);
        }
    }
    if (self.common.subName) |s| {
        if ((it.view() catch |e| return self._errCastIter(e)) == null) {
            self.log("requires subcommand but not found", .{});
            return Error.MissingSubCmd;
        }
        const t = (it.viewMust() catch unreachable).as_posArg().posArg;
        var hit = false;
        inline for (self._cmds) |c| {
            if (c._match(t)) {
                _ = it.next() catch unreachable;
                @field(r, s) = @unionInit(self.SubCmdUnion(), c.name[0], try c.parseFrom(it, a));
                hit = true;
                break;
            }
        }
        if (!hit) {
            self.log("unknown subcommand {s}", .{(it.viewMust() catch unreachable).as_posArg().posArg});
            return Error.UnknownSubCmd;
        }
    }
    if (self.common.callbackFn) |f| {
        const p: *const fn (*self.Result()) void = @ptrCast(@alignCast(f));
        p(&r);
    }
    return r;
}

pub fn destroy(self: Self, r: *const self.Result(), allocator: Allocator) void {
    inline for (self._args) |m| {
        m._destroy(r, allocator);
    }
    if (self.common.subName) |s| {
        inline for (self._cmds) |c| {
            if (std.enums.nameCast(std.meta.Tag(self.SubCmdUnion()), c.name[0]) == @field(r, s)) {
                const a = &@field(@field(r, s), c.name[0]);
                c.destroy(a, allocator);
                break;
            }
        }
    }
}

const CFormatter = @import("CFormatter.zig");
const StringifyUsage = struct {
    v: CFormatter,
    pub fn stringify(self: StringifyUsage, w: anytype) @TypeOf(w).Error!void {
        try self.v.usage(w);
    }
};
pub fn usageString(self: Self) *const [stringify(StringifyUsage{ .v = CFormatter.init(self, .{}) }).count():0]u8 {
    return stringify(StringifyUsage{ .v = CFormatter.init(self, .{}) }).literal();
}
const StringifyHelp = struct {
    v: CFormatter,
    pub fn stringify(self: StringifyHelp, w: anytype) @TypeOf(w).Error!void {
        try self.v.help(w);
    }
};
pub fn helpString(self: Self) *const [stringify(StringifyHelp{ .v = CFormatter.init(self, .{}) }).count():0]u8 {
    return stringify(StringifyHelp{ .v = CFormatter.init(self, .{}) }).literal();
}

const _test = struct {
    test "Compile Errors" {
        // TODO https://github.com/ziglang/zig/issues/513
        return error.SkipZigTest;
    }

    test "Parse Error without subcommand" {
        const cmd = Self.new("cmd")
            .arg(Arg.optArg("int", i32).long("int").help("Required integer"))
            .arg(Arg.optArg("files", []const String).short('f').long("file").help("Multiple files"))
            .arg(Arg.posArg("pos", u32).help("Required position argument"));
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
            .arg(Arg.opt("verbose", u8).short('v'))
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
            .arg(Arg.opt("verbose", u8).short('v'))
            .arg(Arg.optArg("count", u32).short('c').default(3).callbackFn(struct {
                fn f(v: *u32) void {
                    v.* *= 10;
                }
            }.f))
            .arg(Arg.posArg("pos", String));
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
            pub fn parse(s: String, a: ?Allocator) ?@This() {
                const allocator = a orelse return null;
                const len = par.any(usize, s, null) orelse return null;
                const buf = allocator.alloc(u8, len) catch return null;
                return .{ .buf = buf };
            }
            pub fn destroy(self: @This(), a: Allocator) void {
                a.free(self.buf);
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
            .arg(Arg.optArg("integer", ?i32).long("int"))
            .arg(Arg.optArg("output", ?String).long("out"))
            .arg(Arg.posArg("message", ?String));
        const R = cmd.Result();
        {
            var it = try TokenIter.initLine("--int 3 --out hello world", null, .{});
            const args = try cmd.parseFrom(&it, testing.allocator);
            defer cmd.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(
                R{ .integer = 3, .output = "hello", .message = "world" },
                args,
            );
        }
        {
            var it = try TokenIter.initLine("", null, .{});
            const args = try cmd.parseFrom(&it, testing.allocator);
            defer cmd.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(
                R{ .integer = null, .output = null, .message = null },
                args,
            );
        }
    }

    test "Parse with custom config" {
        const _d = Self.new("D")
            .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
            .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
            .arg(Arg.optArg("output", String).long("out").short('o'))
            .arg(Arg.posArg("input", String));
        const _c = Self.new("C")
            .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
            .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
            .arg(Arg.optArg("output", String).long("out").short('o'));
        const _b = Self.new("B")
            .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
            .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
            .arg(Arg.optArg("output", String).long("out").short('o'));
        const _a = Self.new("A")
            .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
            .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
            .arg(Arg.optArg("output", String).long("out").short('o'));
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
        const complex_config: Config = .{ .prefix = .{ .long = "+++", .short = "@" }, .terminator = "**", .connector = "=>" };
        {
            const a = _a.requireSub("sub").sub(
                _b.requireSub("sub").sub(
                    _c.requireSub("sub").sub(_d),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out=bb C -vo cc -- D -vio=dd in", null, .{});
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.setConfig(.{
                    .terminator = "##",
                    .connector = ":",
                }).requireSub("sub").sub(
                    _c.setConfig(complex_config).requireSub("sub").sub(_d),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C @v +++out=>cc ** D -vio=dd in", null, .{});
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.setConfig(.{
                    .terminator = "##",
                    .connector = ":",
                }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d.setConfig(complex_config),
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C -vo=cc -- D @vio=>dd in", null, .{});
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.setConfig(.{
                    .terminator = "##",
                    .connector = ":",
                }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d,
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C -v --out=cc -- D -vio=dd in", null, .{ .connector = "=>" });
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.setConfig(.{
                .terminator = "##",
                .connector = ":",
            }).requireSub("sub").sub(
                _b.requireSub("sub").sub(
                    _c.requireSub("sub").sub(
                        _d.setConfig(complex_config),
                    ),
                ),
            );
            var it = try TokenIter.initLine("-vvo:aa ## B -vi --out=bb -- C -v --out=cc -- D @vio=>dd in", null, .{});
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
        {
            const a = _a.requireSub("sub").sub(
                _b.setConfig(.{
                    .terminator = "##",
                    .connector = ":",
                }).requireSub("sub").sub(
                    _c.requireSub("sub").sub(_d).setConfig(complex_config),
                ),
            );
            var it = try TokenIter.initLine("-vvo=aa B -vi --out:bb ## C @v +++out=>cc ** D @vio=>dd in", null, .{});
            const args = try a.parseFrom(&it, testing.allocator);
            defer a.destroy(&args, testing.allocator);
            try testing.expectEqualDeep(r, args);
        }
    }

    test "Bug, destroy default String" {
        const cmd = Self.new("cmd").arg(Arg.posArg("pos", String).default("hello"));
        var it = try TokenIter.initList(&.{}, .{});
        const args = try cmd.parseFrom(&it, testing.allocator);
        cmd.destroy(&args, testing.allocator);
    }
};

test {
    _ = _test;
}
