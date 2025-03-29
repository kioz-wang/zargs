const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const helper = @import("helper.zig");
const print = helper.Alias.print;
const String = helper.Alias.String;

pub const TokenIter = @import("token.zig").Iter;

const parser = @import("parser.zig");
pub const parseAny = parser.parseAny;

const Meta = @import("meta.zig").Meta;
pub const Arg = Meta;
pub const Ranges = @import("meta.zig").Ranges;

/// Command builder
pub const Command = struct {
    const StringSet = helper.Collection.StringSet;
    const isSlice = helper.Type.isSlice;
    const TryOptional = helper.Type.TryOptional;
    const niceFormatter = helper.niceFormatter;
    const Self = @This();

    fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(print("command({s}) {s}\n", .{ self.name, fmt }), args);
    }

    name: [:0]const u8,
    common: Common = .{},

    _args: []const Meta = &.{},
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
    _builtin_help: ?Meta = Meta.opt("help", bool)
        .help("Show this help then exit").short('h').long("help"),

    const Common = struct {
        version: ?[]const u8 = null,
        about: ?[]const u8 = null,
        author: ?[]const u8 = null,
        homepage: ?[]const u8 = null,
        callBackFn: ?*const anyopaque = null,
        alias: []const [:0]const u8 = &.{},
        /// Use subcommands, specifying the name of the subcommand's enum union field.
        subName: ?[:0]const u8 = null,
    };

    pub fn new(name: [:0]const u8) Self {
        return .{ .name = name };
    }
    pub fn version(self: Self, s: []const u8) Self {
        var cmd = self;
        cmd.common.version = s;
        return cmd;
    }
    pub fn about(self: Self, s: []const u8) Self {
        var cmd = self;
        cmd.common.about = s;
        return cmd;
    }
    pub fn homepage(self: Self, s: []const u8) Self {
        var cmd = self;
        cmd.common.homepage = s;
        return cmd;
    }
    pub fn author(self: Self, s: []const u8) Self {
        var cmd = self;
        cmd.common.author = s;
        return cmd;
    }
    pub fn alias(self: Self, s: [:0]const u8) Self {
        var cmd = self;
        cmd.common.alias = cmd.common.alias ++ [_][:0]const u8{s};
        return cmd;
    }
    pub fn requireSub(self: Self, s: [:0]const u8) Self {
        var cmd = self;
        cmd.common.subName = s;
        return cmd;
    }
    pub fn arg(self: Self, meta: Meta) Self {
        var cmd = self;
        const m = meta._checkOut();
        cmd._checkIn(m);
        cmd._args = cmd._args ++ [_]Meta{m};
        switch (meta.class) {
            .opt => cmd._stat.opt += 1,
            .optArg => cmd._stat.optArg += 1,
            .posArg => cmd._stat.posArg += 1,
        }
        return cmd;
    }
    pub fn sub(self: Self, cmd: Self) Self {
        if (self.common.subName == null) {
            @compileError(print("please call .requireSub(s) before .sub({s})", .{cmd.name}));
        }
        var c = self;
        c._checkInCmdName(cmd.name);
        for (cmd.common.alias) |s| {
            c._checkInCmdName(s);
        }
        c._cmds = c._cmds ++ [_]Self{cmd};
        c._stat.cmd += 1;
        return c;
    }
    pub fn opt(
        self: Self,
        name: [:0]const u8,
        T: type,
        common: struct { help: ?[]const u8 = null, short: ?u8 = null, long: ?String = null, default: ?T = null, callBackFn: ?fn (*T) void = null },
    ) Self {
        var meta = Meta.opt(name, T);
        meta.common.help = common.help;
        if (common.short) |c| {
            meta.common.short = &[_]u8{c};
        }
        if (common.long) |s| {
            meta.common.long = &[_]String{s};
        }
        if (common.default) |v| {
            meta.common.default = @ptrCast(&v);
        }
        if (common.callBackFn) |f| {
            meta.common.callBackFn = @ptrCast(&f);
        }
        return self.arg(meta);
    }
    pub fn optArg(
        self: Self,
        name: [:0]const u8,
        T: type,
        common: struct { help: ?[]const u8 = null, short: ?u8 = null, long: ?String = null, argName: ?[]const u8 = null, default: ?T = null, parseFn: ?parser.Fn(T) = null, callBackFn: ?fn (*TryOptional(T)) void = null },
    ) Self {
        var meta = Meta.optArg(name, T);
        meta.common.help = common.help;
        if (common.short) |c| {
            meta.common.short = &[_]u8{c};
        }
        if (common.long) |s| {
            meta.common.long = &[_]String{s};
        }
        meta.common.argName = common.argName;
        if (common.default) |v| {
            meta = meta.default(v);
        }
        if (common.parseFn) |f| {
            meta.common.parseFn = @ptrCast(&f);
        }
        if (common.callBackFn) |f| {
            meta.common.callBackFn = @ptrCast(&f);
        }
        return self.arg(meta);
    }
    pub fn posArg(
        self: Self,
        name: [:0]const u8,
        T: type,
        common: struct { help: ?[]const u8 = null, argName: ?[]const u8 = null, default: ?T = null, parseFn: ?parser.Fn(T) = null, callBackFn: ?fn (*TryOptional(T)) void = null },
    ) Self {
        var meta = Meta.posArg(name, T);
        meta.common.help = common.help;
        meta.common.argName = common.argName;
        if (common.default) |v| {
            meta = meta.default(v);
        }
        if (common.parseFn) |f| {
            meta.common.parseFn = @ptrCast(&f);
        }
        if (common.callBackFn) |f| {
            meta.common.callBackFn = @ptrCast(&f);
        }
        return self.arg(meta);
    }

    fn _checkInName(self: *const Self, meta: Meta) void {
        if (self.common.subName) |s| {
            if (meta.class == .posArg) {
                @compileError(print("{} conflicts with subName", .{meta}));
            }
            if (std.mem.eql(u8, s, meta.name)) {
                @compileError(print("name of {} conflicts with subName({s})", .{ meta, s }));
            }
        }
        for (self._args) |m| {
            if (std.mem.eql(u8, meta.name, m.name)) {
                @compileError(print("name of {} conflicts with {}", .{ meta, m }));
            }
        }
    }
    fn _checkInShort(self: *const Self, c: u8) void {
        if (self._builtin_help) |m| {
            for (m.common.short) |_c| {
                if (_c == c) {
                    @compileError(print("short_prefix({c}) conflicts with builtin {}", .{ c, m }));
                }
            }
        }
        for (self._args) |m| {
            if (m.class == .opt or m.class == .optArg) {
                for (m.common.short) |_c| {
                    if (_c == c) {
                        @compileError(print("short_prefix({c}) conflicts with {}", .{ c, m }));
                    }
                }
            }
        }
    }
    fn _checkInLong(self: *const Self, s: []const u8) void {
        if (self._builtin_help) |m| {
            for (m.common.long) |_l| {
                if (std.mem.eql(u8, _l, s)) {
                    @compileError(print("long_prefix({s}) conflicts with builtin {}", .{ s, m }));
                }
            }
        }
        for (self._args) |m| {
            if (m.class == .opt or m.class == .optArg) {
                for (m.common.long) |_l| {
                    if (std.mem.eql(u8, _l, s)) {
                        @compileError(print("long_prefix({s}) conflicts with {}", .{ s, m }));
                    }
                }
            }
        }
    }
    fn _checkIn(self: *Self, meta: Meta) void {
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
    fn _checkInCmdName(self: *const Self, name: [:0]const u8) void {
        for (self._cmds) |c| {
            if (std.mem.eql(u8, c.name, name)) {
                @compileError(print("name({s}) conflicts with subcommand({s})", .{ name, c.name }));
            }
            for (c.common.alias) |s| {
                if (std.mem.eql(u8, s, name)) {
                    @compileError(print("name({s}) conflicts with subcommand({s})'s alias({s})", .{ name, c.name, s }));
                }
            }
        }
    }

    fn _usage(self: Self) []const u8 {
        var s: []const u8 = self.name;
        if (self._builtin_help) |m| {
            s = print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .opt) continue;
            s = print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .optArg) continue;
            s = print("{s} {s}", .{ s, m._usage() });
        }
        if (self._stat.posArg != 0 or self._stat.cmd != 0) {
            s = s ++ " [--]";
        }
        for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default == null)
                s = print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default != null)
                s = print("{s} {s}", .{ s, m._usage() });
        }
        if (self._stat.cmd != 0) {
            s = s ++ " {";
        }
        for (self._cmds, 0..) |c, i| {
            s = s ++ (if (i == 0) "" else "|") ++ c.name;
        }
        if (self._stat.cmd != 0) {
            s = s ++ "}";
        }
        return s;
    }
    pub fn usage(self: Self) *const [self._usage().len:0]u8 {
        return print("{s}", .{comptime self._usage()});
    }

    fn _help(self: Self) []const u8 {
        var msg: []const u8 = "Usage: " ++ self.usage();
        const common = self.common;
        if (common.about) |s| {
            msg = msg ++ "\n\n" ++ s;
        }
        if (common.version != null or common.author != null or common.homepage != null) {
            msg = msg ++ "\n\n";
        }
        if (common.version) |s| {
            msg = msg ++ "Version " ++ s ++
                if (common.author != null or common.homepage != null) "\t" else "";
        }
        if (common.author) |s| {
            msg = msg ++ "Author <" ++ s ++ ">" ++
                if (common.homepage != null) "\t" else "";
        }
        if (common.homepage) |s| {
            msg = msg ++ "Homepage " ++ s;
        }
        if (self._stat.opt != 0 or self._builtin_help != null) {
            msg = msg ++ "\n\nOptions:";
        }
        if (self._builtin_help) |m| {
            msg = msg ++ "\n" ++ m._help();
        }
        for (self._args) |m| {
            if (m.class != .opt) continue;
            msg = msg ++ "\n" ++ m._help();
        }
        if (self._stat.optArg != 0) {
            msg = msg ++ "\n\nOptions with arguments:";
        }
        for (self._args) |m| {
            if (m.class != .optArg) continue;
            msg = msg ++ "\n" ++ m._help();
        }
        if (self._stat.posArg != 0) {
            msg = msg ++ "\n\nPositional arguments:";
        }
        for (self._args) |m| {
            if (m.class != .posArg) continue;
            msg = msg ++ "\n" ++ m._help();
        }
        if (self._stat.cmd != 0) {
            msg = msg ++ "\n\nCommands:";
        }
        for (self._cmds) |c| {
            if (c.common.about) |s| {
                msg = msg ++ "\n" ++ print("{s:<24} {s}", .{ c.name, s });
            } else {
                msg = msg ++ "\n" ++ c.name;
            }
            if (c.common.alias.len != 0) {
                msg = msg ++ "\n" ++ print("(alias{})", .{niceFormatter(@as([]const String, c.common.alias))});
            }
        }
        return msg;
    }
    pub fn help(self: Self) *const [self._help().len:0]u8 {
        return print("{s}", .{comptime self._help()});
    }

    const StructField = std.builtin.Type.StructField;
    const EnumField = std.builtin.Type.EnumField;
    const UnionField = std.builtin.Type.UnionField;

    fn SubCmdUnion(self: Self) type {
        var e: []const EnumField = &.{};
        var u: []const UnionField = &.{};
        for (self._cmds, 0..) |c, i| {
            e = e ++ [_]EnumField{.{ .name = c.name, .value = i }};
            u = u ++ [_]UnionField{.{ .name = c.name, .type = c.Result(), .alignment = @alignOf(c.Result()) }};
        }
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

    fn subCmdField(self: Self) StructField {
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
            r.fields = r.fields ++ [_]StructField{m._toField()};
        }
        if (self.common.subName) |s| {
            if (self._stat.cmd == 0) {
                @compileError(print("please call .sub(cmd) to add subcommands because subName({s}) is given", .{s}));
            }
            r.fields = r.fields ++ [_]StructField{self.subCmdField()};
        }
        return @Type(.{ .@"struct" = r });
    }

    pub fn callBack(self: *Self, f: fn (*self.Result()) void) void {
        self.common.callBackFn = @ptrCast(&f);
    }

    fn _match(self: Self, t: String) bool {
        if (std.mem.eql(u8, self.name, t)) return true;
        for (self.common.alias) |s| {
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

    fn _errCastMeta(self: Self, cap: Meta.Error, is_pos: bool) Error {
        return switch (cap) {
            Meta.Error.Allocator => blk: {
                self.log("Error <{any}> from Allocator", .{cap});
                break :blk Error.Allocator;
            },
            Meta.Error.Invalid => if (is_pos) Error.InvalidPosArg else Error.InvalidOptArg,
            Meta.Error.Missing => if (is_pos) Error.MissingPosArg else Error.MissingOptArg,
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
            info.fields = info.fields ++ [_]StructField{self.subCmdField()};
            const I = @Type(.{ .@"struct" = info });
            var i: I = undefined;
            @field(i, s) = undefined;
            break :blk i;
        } else .{});

        while (it.view() catch |e| return self._errCastIter(e)) |t| {
            switch (t) {
                .opt => {
                    var hit = false;
                    if (self._builtin_help) |m| {
                        if (m._match(t)) {
                            std.debug.print("{s}\n", .{self.help()});
                            std.process.exit(1);
                        }
                    }
                    inline for (self._args) |m| {
                        if (m.class == .posArg) continue;
                        hit = m._consume(&r, it, a) catch |e| return self._errCastMeta(e, false);
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
                _ = m._consume(&r, it, a) catch |e| return self._errCastMeta(e, true);
            }
        }
        inline for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default != null) {
                if ((it.view() catch |e| return self._errCastIter(e)) == null) break;
                _ = m._consume(&r, it, a) catch |e| return self._errCastMeta(e, true);
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
                    it.reinit();
                    @field(r, s) = @unionInit(self.SubCmdUnion(), c.name, try c.parseFrom(it, a));
                    hit = true;
                    break;
                }
            }
            if (!hit) {
                self.log("unknown subcommand {s}", .{(it.viewMust() catch unreachable).as_posArg().posArg});
                return Error.UnknownSubCmd;
            }
        }
        if (self.common.callBackFn) |f| {
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
                if (std.enums.nameCast(std.meta.Tag(self.SubCmdUnion()), c.name) == @field(r, s)) {
                    const a = &@field(@field(r, s), c.name);
                    c.destroy(a, allocator);
                    break;
                }
            }
        }
    }

    test "Compile Errors" {
        // TODO https://github.com/ziglang/zig/issues/513
        return error.SkipZigTest;
    }

    test "Format usage" {
        const subcmd0 = Self.new("subcmd0")
            .arg(Meta.optArg("optional_int", i32).long("oint").default(1).argName("OINT"))
            .arg(Meta.optArg("int", i32).long("int"))
            .arg(Meta.optArg("files", []const String).short('f').long("file"))
            .arg(Meta.posArg("optional_pos", u32).default(6))
            .arg(Meta.posArg("io", [2]String))
            .arg(Meta.posArg("message", String).default("hello"));
        const cmd = Self.new("cmd").requireSub("sub")
            .arg(Meta.opt("verbose", u8).short('v'))
            .sub(subcmd0)
            .sub(Self.new("subcmd1"));
        try testing.expectEqualStrings(
            "cmd [-h|--help] [-v]... [--] {subcmd0|subcmd1}",
            cmd.usage(),
        );
        try testing.expectEqualStrings(
            "subcmd0 [-h|--help] [--oint {OINT}] --int {INT} -f|--file {[]FILES}... [--] {[2]IO} [{OPTIONAL_POS}] [{MESSAGE}]",
            subcmd0.usage(),
        );
    }

    test "Format help" {
        {
            const cmd = Self.new("cmd")
                .arg(Meta.opt("verbose", u8).short('v').help("Set log level"))
                .arg(Meta.optArg("optional_int", i32).long("oint").default(1).argName("OINT").help("Optional integer"))
                .arg(Meta.optArg("int", i32).long("int").help("Required integer"))
                .arg(Meta.optArg("files", []String).short('f').long("file").help("Multiple files"))
                .arg(Meta.posArg("optional_pos", u32).default(6).help("Optional position argument"))
                .arg(Meta.posArg("io", [2]String).help("Array position arguments"))
                .arg(Meta.posArg("message", ?String).help("Optional message"));
            try testing.expectEqualStrings(
                \\Usage: cmd [-h|--help] [-v]... [--oint {OINT}] --int {INT} -f|--file {[]FILES}... [--] {[2]IO} [{OPTIONAL_POS}] [{MESSAGE}]
                \\
                \\Options:
                \\[-h|--help]             Show this help then exit
                \\[-v]...                 Set log level
                \\                        (default=0)
                \\
                \\Options with arguments:
                \\[--oint {OINT}]         Optional integer
                \\                        (default=1)
                \\--int {INT}             Required integer
                \\-f|--file {[]FILES}...      Multiple files
                \\
                \\Positional arguments:
                \\[{OPTIONAL_POS}]        Optional position argument
                \\                        (default=6)
                \\{[2]IO}                 Array position arguments
                \\[{MESSAGE}]             Optional message
                \\                        (default=null)
            ,
                cmd.help(),
            );
        }
        {
            const cmd = Self.new("cmd").requireSub("sub")
                .arg(Meta.opt("verbose", u8).short('v'))
                .sub(Self.new("subcmd0").alias("alias0").alias("alias1"))
                .sub(Self.new("subcmd1").alias("alias3"));
            try testing.expectEqualStrings(
                \\Usage: cmd [-h|--help] [-v]... [--] {subcmd0|subcmd1}
                \\
                \\Options:
                \\[-h|--help]             Show this help then exit
                \\[-v]...                 (default=0)
                \\
                \\Commands:
                \\subcmd0
                \\(alias{alias0, alias1})
                \\subcmd1
                \\(alias{alias3})
            ,
                cmd.help(),
            );
        }
    }

    test "Parse Error without subcommand" {
        const cmd = Self.new("cmd")
            .arg(Meta.optArg("int", i32).long("int").help("Required integer"))
            .arg(Meta.optArg("files", []const String).short('f').long("file").help("Multiple files"))
            .arg(Meta.posArg("pos", u32).help("Required position argument"));
        {
            var it = try TokenIter.initList(&[_]String{"-"}, .{});
            try testing.expectError(Error.TokenIter, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"--int="}, .{});
            try testing.expectError(Error.MissingOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"--int=a"}, .{});
            try testing.expectError(Error.InvalidOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{ "--int=1", "--int", "2" }, .{});
            try testing.expectError(Error.RepeatOpt, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"-t"}, .{});
            try testing.expectError(Error.UnknownOpt, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"--"}, .{});
            try testing.expectError(Error.MissingOptArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{ "--int=1", "--" }, .{});
            try testing.expectError(Error.MissingPosArg, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{ "--int=1", "--", "a" }, .{});
            try testing.expectError(Error.InvalidPosArg, cmd.parseFrom(&it, null));
        }
    }

    test "Parse Error with subcommand" {
        const cmd = Self.new("cmd").requireSub("sub")
            .arg(Meta.opt("verbose", u8).short('v'))
            .sub(Self.new("subcmd0"))
            .sub(Self.new("subcmd1").alias("alias0"));
        {
            var it = try TokenIter.initList(&[_]String{"-v"}, .{});
            try testing.expectError(Error.MissingSubCmd, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"subcmd2"}, .{});
            try testing.expectError(Error.UnknownSubCmd, cmd.parseFrom(&it, null));
        }
        {
            var it = try TokenIter.initList(&[_]String{"alias0"}, .{});
            try testing.expectEqual(
                cmd.Result(){ .sub = .{ .subcmd1 = .{} } },
                try cmd.parseFrom(&it, null),
            );
        }
    }

    test "Parse with callBack" {
        comptime var cmd = Self.new("cmd")
            .arg(Meta.opt("verbose", u8).short('v'))
            .arg(Meta.optArg("count", u32).short('c').default(3).callBackFn(struct {
                fn f(v: *u32) void {
                    v.* *= 10;
                }
            }.f))
            .arg(Meta.posArg("pos", String));
        const R = cmd.Result();
        comptime cmd.callBack(struct {
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

    test "Parse struct with parser and allocator" {
        const Mem = struct {
            buf: []u8,
            pub fn parse(s: String, a: ?Allocator) ?@This() {
                const allocator = a orelse return null;
                const len = parseAny(usize, s, null) orelse return null;
                const buf = allocator.alloc(u8, len) catch return null;
                return .{ .buf = buf };
            }
            pub fn destroy(self: @This(), a: Allocator) void {
                a.free(self.buf);
            }
        };
        const cmd = Self.new("cmd")
            .posArg("mem", [2]Mem, .{ .callBackFn = struct {
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
};

test {
    _ = Command;
}
