const std = @import("std");
const testing = std.testing;
const h = @import("helper.zig");

pub const TokenIter = @import("token.zig").Iter;
const parser = @import("parser.zig");
/// Universal parsing function
pub const parseAny = parser.any;
pub const Meta = @import("meta.zig").Meta;

/// Command builder
pub const Command = struct {
    const Self = @This();

    fn _log(self: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(h.print("command({s}) {s}\n", .{ self.name, fmt }), args);
    }

    name: [:0]const u8,
    common: Common = .{},

    _args: []const Meta = &.{},
    _subs: []const Self = &.{},
    _stat: struct {
        opt: u32 = 0,
        optArg: u32 = 0,
        posArg: u32 = 0,
        subCmd: u32 = 0,
    } = .{},
    /// Use the built-in `help` option (short option `-h`, long option `--help`; if matched, output the help message and terminate the program).
    ///
    /// It is enabled by default, but if a `opt` or `arg` named "help" is added, it will automatically be disabled.
    _builtin_help: ?Meta = Meta.opt("help", bool)
        .help("Show this help then exit")
        .short('h')
        .long("help"),

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
        var c = self;
        c.common.version = s;
        return c;
    }
    pub fn about(self: Self, s: []const u8) Self {
        var c = self;
        c.common.about = s;
        return c;
    }
    pub fn homepage(self: Self, s: []const u8) Self {
        var c = self;
        c.common.homepage = s;
        return c;
    }
    pub fn author(self: Self, s: []const u8) Self {
        var c = self;
        c.common.author = s;
        return c;
    }
    pub fn requireSub(self: Self, s: [:0]const u8) Self {
        var c = self;
        c.common.subName = s;
        return c;
    }

    // test "name, Compile, exist as opt" {
    //     // error: name alreay exist as opt
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.opt("name", u32, .{ .short = 'n' });
    //     _ = cmd.opt("name", u32, .{ .short = 'n' });
    // }

    // test "name, Compile, exist as optArg" {
    //     // error: name alreay exist as optArg
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("name", u32, .{ .short = 'n' });
    //     _ = cmd.opt("name", u32, .{ .short = 'n' });
    // }

    // test "name, Compile, exist as posArg" {
    //     // error: name alreay exist as posArg
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.posArg("name", u32, .{});
    //     _ = cmd.opt("name", u32, .{ .short = 'n' });
    // }

    // test "name, Compile, exist as subCmd" {
    //     // error: name alreay exist as subCmd
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     const sub: Self = .{ .name = "sub" };
    //     comptime var cmd: Self = .{ .name = "test", .subName = "name" };
    //     _ = cmd.subCmd(sub);
    //     _ = cmd.opt("name", u32, .{ .short = 'c' });
    // }

    // test "short, Compile, used by opt" {
    //     // error: o alreay used by opt<opt0>
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.opt("opt0", u32, .{ .short = 'o' });
    //     _ = cmd.opt("opt1", u32, .{ .short = 'o' });
    // }

    // test "short, Compile, used by optArg" {
    //     // error: o alreay used by optArg<opt0>
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("opt0", u32, .{ .short = 'o' });
    //     _ = cmd.opt("opt1", u32, .{ .short = 'o' });
    // }

    // test "long, Compile, used by opt" {
    //     // error: long alreay used by opt<opt0>
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.opt("opt0", u32, .{ .long = "long" });
    //     _ = cmd.opt("opt1", u32, .{ .long = "long" });
    // }

    // test "long, Compile, used by optArg" {
    //     // error: long alreay used by optArg<opt0>
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("opt0", u32, .{ .long = "long" });
    //     _ = cmd.opt("opt1", u32, .{ .long = "long" });
    // }

    fn _checkInName(self: *const Self, m: Meta) void {
        if (self.common.subName) |s| {
            if (m.class == .posArg) {
                @compileError(h.print("{} not accept because subCmd<{s}>", .{ m, s }));
            }
            if (std.mem.eql(u8, s, m.name)) {
                @compileError(h.print("{s} already exist as subCmd", .{m.name}));
            }
        }
        for (self._args) |a| {
            if (std.mem.eql(u8, m.name, a.name)) {
                @compileError(h.print("{} already exist as {}", .{ m, a }));
            }
        }
    }
    fn _checkInShort(self: *const Self, short: u8) void {
        if (self._builtin_help) |m| {
            if (m.common.short == short) {
                @compileError(h.print("{c} already used by Builtin {}", .{ short, m }));
            }
        }
        for (self._args) |a| {
            if (a.class == .opt or a.class == .optArg) {
                if (a.common.short == short) {
                    @compileError(h.print("short {c} already used by {}", .{ short, a }));
                }
            }
        }
    }
    fn _checkInLong(self: *const Self, long: []const u8) void {
        if (self._builtin_help) |m| {
            if (m.common.long) |l| {
                if (std.mem.eql(u8, l, long)) {
                    @compileError(h.print("{s} already used by Builtin {}", .{ long, m }));
                }
            }
        }
        for (self._args) |a| {
            if (a.class == .opt or a.class == .optArg) {
                if (a.common.long) |l| {
                    if (std.mem.eql(u8, l, long)) {
                        @compileError(h.print("long {s} already used by {}", .{ long, a }));
                    }
                }
            }
        }
    }
    fn _checkIn(self: *Self, m: Meta) void {
        self._checkInName(m);
        if (m.class == .opt or m.class == .optArg) {
            if (self._builtin_help) |n| {
                if (std.mem.eql(u8, m.name, n.name)) {
                    self._builtin_help = null;
                }
            }
            if (m.common.short) |short| self._checkInShort(short);
            if (m.common.long) |long| self._checkInLong(long);
        }
    }

    pub fn arg(self: Self, m: Meta) Self {
        var c = self;
        var a = m;
        a._checkOut();
        c._checkIn(a);
        c._args = c._args ++ [_]Meta{a};
        switch (m.class) {
            .opt => c._stat.opt += 1,
            .optArg => c._stat.optArg += 1,
            .posArg => c._stat.posArg += 1,
        }
        return c;
    }

    // test "opt, Compile, short and long" {
    //     // error: opt(Arg)<name> at least one of short or long is required
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.opt("name", u32, .{});
    // }

    // test "opt, Compile, unsupport type" {
    //     // error: opt<name> not accept f32
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.opt("name", f32, .{ .short = 'n' });
    // }

    // test "optArg, Compile, short and long" {
    //     // error: opt(Arg)<name> at least one of short or long is required
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("name", u32, .{});
    // }

    // test "optArg, Compile, pointer but not slice" {
    //     // error: optArg<name> not accept *[]const u8
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("name", *[]const u8, .{ .short = 'n' });
    // }

    // test "optArg, Compile, slice but not const" {
    //     // error: optArg<name> not accept []u32
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("name", []u32, .{ .short = 'n' });
    // }

    // test "optArg, Compile, default for Slice" {
    //     // error: optArg<num> not support default for Slice
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.optArg("num", []const u32, .{ .short = 'n', .default = &[_]u32{ 1, 2 } });
    // }

    // test "posArg, Compile, conflict with subCmd" {
    //     // error: posArg<pos> not accept because subCmd<name> exist
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     const sub: Self = .{ .name = "sub" };
    //     comptime var cmd: Self = .{ .name = "test", .subName = "name" };
    //     _ = cmd.subCmd(sub);
    //     _ = cmd.posArg("pos", u32, .{});
    // }

    fn _checkInCmdName(self: *const Self, name: [:0]const u8) void {
        for (self._subs) |c| {
            if (std.mem.eql(u8, c.name, name)) {
                @compileError(self.common.subName.? ++ "." ++ name ++ " alreay exist");
            }
        }
    }

    // test "subCmd, Compile, alreay exist" {
    //     // error: sub.sub0 alreay exist
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test", .subName = "sub" };
    //     _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub0" });
    // }

    pub fn sub(self: Self, cmd: Self) Self {
        if (self.common.subName == null) {
            @compileError(h.print(".requireSub(subName) first then add command({s})", .{cmd.name}));
        }
        var c = self;
        c._checkInCmdName(cmd.name);
        c._subs = c._subs ++ [_]Self{cmd};
        c._stat.subCmd += 1;
        return c;
    }

    // test "subCmd, Compile, not accept" {
    //     // error: ?.sub not accept because subName is null
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test" };
    //     _ = cmd.subCmd(.{ .name = "sub" });
    // }

    fn usagePre(self: Self) []const u8 {
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
        if (self._stat.posArg != 0 or self._stat.subCmd != 0) {
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
        if (self._stat.subCmd != 0) {
            s = s ++ " {";
        }
        for (self._subs, 0..) |c, i| {
            s = s ++ (if (i == 0) "" else "|") ++ c.name;
        }
        if (self._stat.subCmd != 0) {
            s = s ++ "}";
        }
        return s;
    }

    pub fn usage(self: Self) *const [self.usagePre().len:0]u8 {
        return h.print("{s}", .{comptime self.usagePre()});
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

    fn helpPre(self: Self) []const u8 {
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
        if (self._stat.subCmd != 0) {
            msg = msg ++ "\n\nSub Commands:";
        }
        for (self._subs) |c| {
            if (c.common.about) |s| {
                msg = msg ++ "\n" ++ h.print("{s:<30} {s}", .{ c.name, s });
            } else {
                msg = msg ++ "\n" ++ c.name;
            }
        }
        return msg;
    }

    pub fn help(self: Self) *const [self.helpPre().len:0]u8 {
        return h.print("{s}", .{comptime self.helpPre()});
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
        for (self._subs, 0..) |m, i| {
            e = e ++ [_]EnumField{.{ .name = m.name, .value = i }};
            u = u ++ [_]UnionField{.{ .name = m.name, .type = m.Result(), .alignment = @alignOf(m.Result()) }};
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
            if (self._stat.subCmd == 0) {
                @compileError("subCmd<" ++ s ++ "> subName is given, but no cmds has been added");
            }
            r.fields = r.fields ++ [_]StructField{self.subCmdField()};
        }
        return @Type(.{ .@"struct" = r });
    }

    // test "subCmd, Compile, no cmds has been added" {
    //     // error: subCmd<sub> subName is given, but no cmds has been added
    //     const skip = true;
    //     if (skip)
    //         return error.SkipZigTest;
    //     comptime var cmd: Self = .{ .name = "test", .subName = "sub" };
    //     _ = cmd.Result();
    // }

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
            inline for (self._subs) |c| {
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

    fn errCastIter(self: Self, cap: TokenIter.Error) Error {
        self._log("Error <{any}> from TokenIter", .{cap});
        return Error.TokenIter;
    }

    fn errCastMeta(self: Self, cap: Meta.Error, is_pos: bool) Error {
        return switch (cap) {
            Meta.Error.Allocator => blk: {
                self._log("Error <{any}> from Allocator", .{cap});
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

        while (it.view() catch |e| return self.errCastIter(e)) |top| {
            switch (top) {
                .opt => |o| {
                    var hit = false;
                    if (self._builtin_help) |m| {
                        if (m._match(top)) {
                            std.debug.print("{s}\n", .{self.help()});
                            std.process.exit(1);
                        }
                    }
                    inline for (self._args) |m| {
                        if (m.class == .posArg) continue;
                        hit = m._consume(&r, it, allocator) catch |e| return self.errCastMeta(e, false);
                        if (hit) {
                            if (!matched.add(m.name)) {
                                if ((m.class == .opt and m.T != bool) or (m.class == .optArg and m._isSlice())) break;
                                self._log("match {} again with {}", .{ m, o });
                                return Error.RepeatOpt;
                            }
                            break;
                        }
                    }
                    if (hit) continue;
                    self._log("unknown option {}", .{o});
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
                if (!m._isSlice() and !matched.contain(m.name)) {
                    const u = comptime m._usage();
                    self._log("requires {} but not found: {s}", .{ m, u });
                    return Error.MissingOptArg;
                }
            }
        }
        inline for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default == null) {
                _ = m._consume(&r, it, allocator) catch |e| return self.errCastMeta(e, true);
            }
        }
        inline for (self._args) |m| {
            if (m.class != .posArg) continue;
            if (m.common.default != null) {
                if ((it.view() catch |e| return self.errCastIter(e)) == null) break;
                _ = m._consume(&r, it, allocator) catch |e| return self.errCastMeta(e, true);
            }
        }
        if (self.common.subName) |s| {
            if ((it.view() catch |e| return self.errCastIter(e)) == null) {
                self._log("requires subCmd<{s}> but not found", .{s});
                return Error.MissingSubCmd;
            }
            const t = (it.viewMust() catch unreachable).as_posArg().posArg;
            var hit = false;
            inline for (self._subs) |c| {
                if (std.mem.eql(u8, c.name, t)) {
                    _ = it.next() catch unreachable;
                    it.reinit();
                    @field(r, s) = @unionInit(self.SubCmdUnion(), c.name, try c.parseAlloc(it, allocator));
                    hit = true;
                    break;
                }
            }
            if (!hit) {
                self._log("unknown subCmd {s}", .{(it.viewMust() catch unreachable).as_posArg().posArg});
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

    // test "parse, Error MissingOptArg" {
    //     const cmd: Self = .{ .name = "exp" };
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("file", []const u8, .{ .short = 'f' });
    //         var it = try TokenIter.initLine("-f -a", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingOptArg, c.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("u32s", [2]u32, .{ .short = 'u' });
    //         var it = try TokenIter.initLine("-u 0xa", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingOptArg, c.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("u32s", [2]u32, .{ .short = 'u' });
    //         var it = try TokenIter.initLine("-u=0xa 1", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingOptArg, c.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("file", []const u8, .{ .short = 'f' });
    //         var it = try TokenIter.initLine("", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingOptArg, c.parse(&it));
    //     }
    // }

    // test "parse, Error InvalidOptArg" {
    //     const cmd: Self = .{ .name = "exp" };
    //     {
    //         comptime var c = cmd;
    //         _ = c.optArg("number", u32, .{ .long = "num" });
    //         var it = try TokenIter.initLine("--num=a", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.InvalidOptArg, c.parse(&it));
    //     }
    //     {
    //         const lastCharacter = struct {
    //             fn p(s: []const u8) ?u8 {
    //                 return if (s.len == 0) null else s[s.len - 1];
    //             }
    //         }.p;
    //         comptime var c = cmd;
    //         _ = c.optArg("lastc", u8, .{ .short = 'l', .parseFn = lastCharacter });
    //         var it = try TokenIter.initList(&[_][]const u8{ "-l", "" }, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.InvalidOptArg, c.parse(&it));
    //     }
    //     {
    //         const Color = enum { Red, Green, Blue };
    //         comptime var c = cmd;
    //         _ = c.optArg("color", Color, .{ .long = "color" });
    //         var it = try TokenIter.initLine("--color red", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.InvalidOptArg, c.parse(&it));
    //     }
    // }

    // test "parse, Error MissingPosArg" {
    //     const cmd: Self = .{ .name = "exp" };
    //     {
    //         comptime var c = cmd;
    //         _ = c.posArg("number", u32, .{});
    //         var it = try TokenIter.initLine("", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingPosArg, c.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         _ = c.posArg("numbers", [2]u32, .{ .default = .{ 1, 2 } });
    //         var it = try TokenIter.initLine("9", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.MissingPosArg, c.parse(&it));
    //     }
    // }

    // test "parse, Error InvalidPosArg" {
    //     comptime var cmd: Self = .{ .name = "exp" };
    //     _ = cmd.posArg("number", u32, .{});
    //     var it = try TokenIter.initLine("a", null, .{});
    //     defer it.deinit();
    //     try testing.expectError(Error.InvalidPosArg, cmd.parse(&it));
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

    // test "parse, Error Allocator" {
    //     comptime var cmd: Self = .{ .name = "exp" };
    //     _ = cmd.optArg("slice", []const u32, .{ .short = 'n' });
    //     var it = try TokenIter.initLine("-n 1", null, .{});
    //     defer it.deinit();
    //     try testing.expectError(Error.Allocator, cmd.parse(&it));
    // }

    // test "parse, Error TokenIter" {
    //     const cmd: Self = .{ .name = "exp" };
    //     {
    //         comptime var c = cmd;
    //         var it = try TokenIter.initLine("--", null, .{ .terminator = "==" });
    //         defer it.deinit();
    //         try testing.expectError(Error.TokenIter, c.parse(&it));
    //     }
    //     {
    //         comptime var c = cmd;
    //         var it = try TokenIter.initLine("-", null, .{});
    //         defer it.deinit();
    //         try testing.expectError(Error.TokenIter, c.parse(&it));
    //     }
    // }
};

test {
    _ = Command;
    _ = @import("token.zig");
}
