const std = @import("std");
const testing = std.testing;
const h = @import("helper.zig");

pub const TokenIter = @import("token.zig").Iter;
const parser = @import("parser.zig");
/// Universal parsing function
pub const parseAny = parser.any;
pub const Meta = @import("Meta.zig");

/// Command builder
pub const Command = struct {
    const Self = @This();

    fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(h.print("command({s}) {s}\n", .{ self.name, fmt }), args);
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
            @compileError(h.print("please call .requireSub(s) before .sub({s})", .{cmd.name}));
        }
        var c = self;
        c._checkInCmdName(cmd.name);
        c._cmds = c._cmds ++ [_]Self{cmd};
        c._stat.cmd += 1;
        return c;
    }
    pub fn opt(
        self: Self,
        name: [:0]const u8,
        T: type,
        common: struct { help: ?[]const u8 = null, short: ?u8 = null, long: ?[]const u8 = null, default: ?T = null, callBackFn: ?fn (*T) void = null },
    ) Self {
        var meta = Meta.opt(name, T);
        meta.common.help = common.help;
        meta.common.short = common.short;
        meta.common.long = common.long;
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
        common: struct { help: ?[]const u8 = null, short: ?u8 = null, long: ?[]const u8 = null, argName: ?[]const u8 = null, default: ?T = null, parseFn: ?parser.Fn(parser.Base(T)) = null, callBackFn: ?fn (*T) void = null },
    ) Self {
        var meta = Meta.optArg(name, T);
        meta.common.help = common.help;
        meta.common.short = common.short;
        meta.common.long = common.long;
        meta.common.argName = common.argName;
        if (common.default) |v| {
            meta.common.default = @ptrCast(&v);
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
        common: struct { help: ?[]const u8 = null, argName: ?[]const u8 = null, default: ?T = null, parseFn: ?parser.Fn(parser.Base(T)) = null, callBackFn: ?fn (*T) void = null },
    ) Self {
        var meta = Meta.posArg(name, T);
        meta.common.help = common.help;
        meta.common.argName = common.argName;
        if (common.default) |v| {
            meta.common.default = @ptrCast(&v);
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
                @compileError(h.print("{} conflicts with subName", .{meta}));
            }
            if (std.mem.eql(u8, s, meta.name)) {
                @compileError(h.print("name of {} conflicts with subName({s})", .{ meta, s }));
            }
        }
        for (self._args) |m| {
            if (std.mem.eql(u8, meta.name, m.name)) {
                @compileError(h.print("name of {} conflicts with {}", .{ meta, m }));
            }
        }
    }
    fn _checkInShort(self: *const Self, c: u8) void {
        if (self._builtin_help) |m| {
            if (m.common.short == c) {
                @compileError(h.print("short_prefix({c}) conflicts with builtin {}", .{ c, m }));
            }
        }
        for (self._args) |m| {
            if (m.class == .opt or m.class == .optArg) {
                if (m.common.short == c) {
                    @compileError(h.print("short_prefix({c}) conflicts with  {}", .{ c, m }));
                }
            }
        }
    }
    fn _checkInLong(self: *const Self, s: []const u8) void {
        if (self._builtin_help) |m| {
            if (m.common.long) |l| {
                if (std.mem.eql(u8, l, s)) {
                    @compileError(h.print("long_prefix({s}) conflicts with builtin {}", .{ s, m }));
                }
            }
        }
        for (self._args) |m| {
            if (m.class == .opt or m.class == .optArg) {
                if (m.common.long) |l| {
                    if (std.mem.eql(u8, l, s)) {
                        @compileError(h.print("long_prefix({s}) conflicts with  {}", .{ s, m }));
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
            if (meta.common.short) |c| self._checkInShort(c);
            if (meta.common.long) |s| self._checkInLong(s);
        }
    }
    fn _checkInCmdName(self: *const Self, name: [:0]const u8) void {
        for (self._cmds) |c| {
            if (std.mem.eql(u8, c.name, name)) {
                @compileError(h.print("name({s}) conflicts with subcommand({s})", .{ name, c.name }));
            }
        }
    }

    fn _usage(self: Self) []const u8 {
        var s: []const u8 = self.name;
        if (self._builtin_help) |m| {
            s = h.print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .opt) continue;
            s = h.print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .optArg) continue;
            s = h.print("{s} {s}", .{ s, m._usage() });
        }
        if (self._stat.posArg != 0 or self._stat.cmd != 0) {
            s = s ++ " [--]";
        }
        for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default == null)
                s = h.print("{s} {s}", .{ s, m._usage() });
        }
        for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default != null)
                s = h.print("{s} {s}", .{ s, m._usage() });
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
        return h.print("{s}", .{comptime self._usage()});
    }

    // test "usage without subCmds" {
    //     const Color = enum { Red, Green, Blue };

    //     comptime var cmd: Self = .{ .name = "exp", .log = null };

    //     _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });

    //     _ = cmd.optArg("optional_int", u32, .{ .long = "oint", .default = 1, .arg_name = "OptionalInt" });
    //     _ = cmd.optArg("int", u32, .{ .long = "int" });
    //     _ = cmd.optArg("color", Color, .{ .long = "color", .default = Color.Blue });
    //     _ = cmd.optArg("3word", [3][]const u8, .{ .long = "3word", .arg_name = "WORD" });

    //     _ = cmd.posArg("optional_pos_int", u32, .{ .help = "give me a u32", .arg_name = "Num", .default = 9 });
    //     _ = cmd.posArg("pos_int", u32, .{ .help = "give me a u32" });
    //     _ = cmd.posArg("optional_2pos_int", [2]u32, .{ .help = "give me two u32", .arg_name = "Num", .default = .{ 1, 2 } });

    //     try testing.expectEqualStrings(
    //         "exp [-v]... [-h|--help] [--oint {OptionalInt}] --int {INT} [--color {COLOR}] --3word {[3]WORD} [--] {POS_INT} [{Num}] [{[2]Num}]",
    //         comptime cmd.usage(),
    //     );
    // }

    // test "usage with subCmds" {
    //     comptime var cmd: Self = .{ .name = "exp", .log = null, .subName = "sub" };
    //     _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });
    //     _ = cmd.optArg("int", u32, .{ .long = "int" });
    //     _ = cmd.subCmd(.{ .name = "install" }).subCmd(.{ .name = "remove" }).subCmd(.{ .name = "version" });

    //     try testing.expectEqualStrings(
    //         "exp [-v]... [-h|--help] --int {INT} [--] {install|remove|version}",
    //         comptime cmd.usage(),
    //     );
    // }

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
            msg = msg ++ "\n\nSub Commands:";
        }
        for (self._cmds) |c| {
            if (c.common.about) |s| {
                msg = msg ++ "\n" ++ h.print("{s:<30} {s}", .{ c.name, s });
            } else {
                msg = msg ++ "\n" ++ c.name;
            }
        }
        return msg;
    }

    pub fn help(self: Self) *const [self._help().len:0]u8 {
        return h.print("{s}", .{comptime self._help()});
    }

    // test "help" {
    //     comptime var cmd: Self = .{ .name = "exp", .log = null, .subName = "sub" };
    //     _ = cmd.opt("verbose", u8, .{ .short = 'v' }).optArg("int", i32, .{ .long = "int", .help = "Give me an integer" });
    //     _ = cmd.subCmd(.{ .name = "install" }).subCmd(.{ .name = "remove", .description = "Remove something" }).subCmd(.{ .name = "version" });

    //     try testing.expectEqualStrings(
    //         \\Usage: exp [-h|--help] [-v]... --int {INT} [--] {install|remove|version}
    //         \\
    //         \\[-h|--help]                    Show this help then exit
    //         \\[-v]...
    //         \\
    //         \\--int {INT}                    Give me an integer
    //         \\
    //         \\install
    //         \\remove                         Remove something
    //         \\version
    //     ,
    //         comptime cmd.help(),
    //     );
    // }

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
                @compileError(h.print("please call .sub(cmd) to add subcommands because subName({s}) is given", .{s}));
            }
            r.fields = r.fields ++ [_]StructField{self.subCmdField()};
        }
        return @Type(.{ .@"struct" = r });
    }

    pub fn callBack(self: *Self, f: fn (*self.Result()) void) void {
        self.common.callBackFn = @ptrCast(&f);
    }

    pub fn destroy(self: Self, r: *const self.Result(), allocator: std.mem.Allocator) void {
        inline for (self._args) |m| {
            if (@typeInfo(m.T) == .pointer) {
                allocator.free(@field(r, m.name));
            }
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

    pub fn parse(self: Self, it: *TokenIter) Error!self.Result() {
        return self.parseAlloc(it, null);
    }

    pub fn parseAlloc(self: Self, it: *TokenIter, allocator: ?std.mem.Allocator) Error!self.Result() {
        var matched: h.StringSet(self._stat.opt + self._stat.optArg) = .{};
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
                        hit = m._consume(&r, it, allocator) catch |e| return self._errCastMeta(e, false);
                        if (hit) {
                            if (!matched.add(m.name)) {
                                if ((m.class == .opt and m.T != bool) or (m.class == .optArg and h.isSlice(m.T))) break;
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
                if (!h.isSlice(m.T) and !matched.contain(m.name)) {
                    self.log("requires {} but not found", .{m});
                    return Error.MissingOptArg;
                }
            }
        }
        inline for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default == null) {
                _ = m._consume(&r, it, allocator) catch |e| return self._errCastMeta(e, true);
            }
        }
        inline for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default != null) {
                if ((it.view() catch |e| return self._errCastIter(e)) == null) break;
                _ = m._consume(&r, it, allocator) catch |e| return self._errCastMeta(e, true);
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
                if (std.mem.eql(u8, c.name, t)) {
                    _ = it.next() catch unreachable;
                    it.reinit();
                    @field(r, s) = @unionInit(self.SubCmdUnion(), c.name, try c.parseAlloc(it, allocator));
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

    // test "parse, Error RepeatOpt" {
    //     comptime var cmd: Self = .{ .name = "exp" };
    //     _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });
    //     {
    //         var it = try TokenIter.initLine("-vvh --help", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.RepeatOpt, cmd.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("number", u32, .{ .long = "num" });
    //         var it = try TokenIter.initLine("--num 1 --num 2", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.RepeatOpt, c.parse(&it));
    //     }
    // }

    // test "parse, Error UnknownOpt" {
    //     comptime var cmd: Self = .{ .name = "exp" };
    //     var it = try TokenIter.initLine("-a", null, .{});
    //     defer it.deinit();
    //     try testing.expectError(Error.UnknownOpt, cmd.parse(&it));
    // }

    // test "parse, Error MissingSubCmd" {
    //     comptime var cmd: Self = .{ .name = "exp", .subName = "sub" };
    //     _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub1" });
    //     var it = try TokenIter.initLine("", null, .{});
    //     defer it.deinit();
    //     try testing.expectError(Error.MissingSubCmd, cmd.parse(&it));
    // }

    // test "parse, Error UnknownSubCmd" {
    //     comptime var cmd: Self = .{ .name = "exp", .subName = "sub" };
    //     _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub1" });
    //     var it = try TokenIter.initLine("abc", null, .{});
    //     defer it.deinit();
    //     try testing.expectError(Error.UnknownSubCmd, cmd.parse(&it));
    // }

    test "Compile Errors" {
        // TODO https://github.com/ziglang/zig/issues/513
        return error.SkipZigTest;
    }
};

test {
    _ = Command;
    _ = @import("token.zig");
}
