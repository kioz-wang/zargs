const std = @import("std");
const testing = std.testing;

fn StringSet(capacity: comptime_int) type {
    const S = []const u8;
    const A = std.ArrayListUnmanaged(S);
    return struct {
        base: A = undefined,
        buffer: [capacity]S = undefined,
        fn init(self: *@This()) void {
            self.base = A.initBuffer(self.buffer[0..]);
        }
        fn contain(self: *const @This(), s: S) bool {
            return for (self.base.items) |item| {
                if (std.mem.eql(u8, item, s)) break true;
            } else false;
        }
        fn add(self: *@This(), s: S) bool {
            if (self.contain(s)) return false;
            self.base.appendAssumeCapacity(s);
            return true;
        }
    };
}

test StringSet {
    var set: StringSet(2) = .{};
    set.init();
    try testing.expect(!set.contain("a"));
    try testing.expect(set.add("a"));
    try testing.expect(set.contain("a"));
    try testing.expect(!set.add("a"));
}

fn upper(comptime str: []const u8) [str.len]u8 {
    var s = std.mem.zeroes([str.len]u8);
    _ = std.ascii.upperString(s[0..], str);
    return s;
}

test upper {
    try testing.expectEqualStrings("UPPER", &upper("upPer"));
}

pub const Iter = @import("token.zig").Iter;
pub const parser = @import("parser.zig");

pub const Command = struct {
    const meta = @import("meta.zig");

    pub const Builtin = struct {
        pub fn logFn(comptime fmt: []const u8, args: anytype) void {
            std.debug.print(fmt ++ "\n", args);
        }
        const help: meta.Opt = .{
            .meta = .{
                .name = "help",
                .T = bool,
                .help = "Show this help then exit",
            },
            .short = 'h',
            .long = "help",
        };
    };

    const Self = @This();

    log: ?*const @TypeOf(std.debug.print) = Builtin.logFn,

    name: [:0]const u8,
    version: ?[]const u8 = null,
    description: ?[]const u8 = null,
    author: ?[]const u8 = null,
    homepage: ?[]const u8 = null,

    _opts: []const meta.Opt = &.{},
    _optArgs: []const meta.OptArg = &.{},
    _posArgs: []const meta.PosArg = &.{},
    _subCmds: []const Self = &.{},

    use_subCmd: ?[:0]const u8 = null,

    use_builtin_help: bool = true,

    fn checkName(self: *const Self, name: [:0]const u8) void {
        for (self._opts) |m| {
            if (std.mem.eql(u8, m.meta.name, name)) {
                @compileError(name ++ " alreay exist as opt");
            }
        }
        for (self._optArgs) |m| {
            if (std.mem.eql(u8, m.meta.name, name)) {
                @compileError(name ++ " alreay exist as optArg");
            }
        }
        for (self._posArgs) |m| {
            if (std.mem.eql(u8, m.meta.name, name)) {
                @compileError(name ++ " alreay exist as posArg");
            }
        }
        if (self.use_subCmd) |s| {
            if (std.mem.eql(u8, s, name)) {
                @compileError(name ++ " alreay exist as subCmd");
            }
        }
    }

    test "name, Compile, exist as opt" {
        // error: name alreay exist as opt
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.opt("name", u32, .{ .short = 'n' });
        _ = cmd.opt("name", u32, .{ .short = 'n' });
    }

    test "name, Compile, exist as optArg" {
        // error: name alreay exist as optArg
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("name", u32, .{ .short = 'n' });
        _ = cmd.opt("name", u32, .{ .short = 'n' });
    }

    test "name, Compile, exist as posArg" {
        // error: name alreay exist as posArg
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.posArg("name", u32, .{});
        _ = cmd.opt("name", u32, .{ .short = 'n' });
    }

    test "name, Compile, exist as subCmd" {
        // error: name alreay exist as subCmd
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        const sub: Self = .{ .name = "sub" };
        comptime var cmd: Self = .{ .name = "test", .use_subCmd = "name" };
        _ = cmd.subCmd(sub);
        _ = cmd.opt("name", u32, .{ .short = 'c' });
    }

    fn checkShort(self: *const Self, short: u8) void {
        if (self.use_builtin_help) {
            const m = Builtin.help;
            if (m.short == short) {
                @compileError([_]u8{short} ++ " alreay used by Builtin opt<" ++ m.meta.name ++ ">");
            }
        }
        for (self._opts) |m| {
            if (m.short == short) {
                @compileError([_]u8{short} ++ " alreay used by opt<" ++ m.meta.name ++ ">");
            }
        }
        for (self._optArgs) |m| {
            if (m.short == short) {
                @compileError([_]u8{short} ++ " alreay used by optArg<" ++ m.meta.name ++ ">");
            }
        }
    }

    test "short, Compile, used by opt" {
        // error: o alreay used by opt<opt0>
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.opt("opt0", u32, .{ .short = 'o' });
        _ = cmd.opt("opt1", u32, .{ .short = 'o' });
    }

    test "short, Compile, used by optArg" {
        // error: o alreay used by optArg<opt0>
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("opt0", u32, .{ .short = 'o' });
        _ = cmd.opt("opt1", u32, .{ .short = 'o' });
    }

    fn checkLong(self: *const Self, long: []const u8) void {
        if (self.use_builtin_help) {
            const m = Builtin.help;
            if (m.long) |l| {
                if (std.mem.eql(u8, l, long)) {
                    @compileError(long ++ " alreay used by Builtin optArg<" ++ m.meta.name ++ ">");
                }
            }
        }
        for (self._opts) |m| {
            if (m.long) |l| {
                if (std.mem.eql(u8, l, long)) {
                    @compileError(long ++ " alreay used by opt<" ++ m.meta.name ++ ">");
                }
            }
        }
        for (self._optArgs) |m| {
            if (m.long) |l| {
                if (std.mem.eql(u8, l, long)) {
                    @compileError(long ++ " alreay used by optArg<" ++ m.meta.name ++ ">");
                }
            }
        }
    }

    test "long, Compile, used by opt" {
        // error: long alreay used by opt<opt0>
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.opt("opt0", u32, .{ .long = "long" });
        _ = cmd.opt("opt1", u32, .{ .long = "long" });
    }

    test "long, Compile, used by optArg" {
        // error: long alreay used by optArg<opt0>
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("opt0", u32, .{ .long = "long" });
        _ = cmd.opt("opt1", u32, .{ .long = "long" });
    }

    fn checkOpt(self: *Self, name: [:0]const u8, short: ?u8, long: ?[]const u8) void {
        self.checkName(name);
        if (std.mem.eql(u8, Builtin.help.meta.name, name)) {
            self.use_builtin_help = false;
        }
        if (short == null and long == null) {
            @compileError("opt(Arg):" ++ name ++ " at least one of short or long is required");
        }
        if (short) |s| self.checkShort(s);
        if (long) |l| self.checkLong(l);
    }

    pub fn opt(
        self: *Self,
        name: [:0]const u8,
        T: type,
        config: struct {
            default: ?T = null,
            help: ?[]const u8 = null,
            short: ?u8 = null,
            long: ?[]const u8 = null,
            callBackFn: ?fn (*T) void = null,
        },
    ) *Self {
        self.checkOpt(name, config.short, config.long);
        if (T != bool and @typeInfo(T) != .Int) {
            @compileError("opt:" ++ name ++ " not accept " ++ @typeName(T));
        }
        var m: meta.Meta = .{ .name = name, .T = T, .help = config.help, .log = self.log };
        if (config.default) |d| {
            m.default = @ptrCast(&d);
        } else {
            if (T == bool) {
                m.default = @ptrCast(&false);
            } else {
                const zero: T = 0;
                m.default = @ptrCast(&zero);
            }
        }
        if (config.callBackFn) |f| {
            m.callBackFn = @ptrCast(&f);
        }
        self._opts = self._opts ++ [_]meta.Opt{.{
            .meta = m,
            .short = config.short,
            .long = config.long,
        }};
        return self;
    }

    test "opt, Compile, short and long" {
        // error: opt(Arg)<name> at least one of short or long is required
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.opt("name", u32, .{});
    }

    test "opt, Compile, unsupport type" {
        // error: opt<name> not accept f32
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.opt("name", f32, .{ .short = 'n' });
    }

    pub fn optArg(
        self: *Self,
        name: [:0]const u8,
        T: type,
        config: struct {
            default: ?T = null,
            help: ?[]const u8 = null,
            short: ?u8 = null,
            long: ?[]const u8 = null,
            arg_name: ?[]const u8 = null,
            parseFn: ?parser.Fn(parser.Base(T)) = null,
            callBackFn: ?fn (*T) void = null,
        },
    ) *Self {
        self.checkOpt(name, config.short, config.long);
        const info = @typeInfo(T);
        if (info == .Pointer) {
            if (info.Pointer.size != .Slice or !info.Pointer.is_const) {
                @compileError("optArg:" ++ name ++ " not accept " ++ @typeName(T));
            }
            if (T != []const u8) {
                if (config.default != null) {
                    @compileError("optArg:" ++ name ++ " not support default for Slice");
                }
            }
        }
        var m: meta.Meta = .{ .name = name, .T = T, .help = config.help, .log = self.log };
        if (config.default) |v| {
            m.default = @ptrCast(&v);
        }
        if (config.parseFn) |f| {
            m.parseFn = @ptrCast(&f);
        }
        if (config.callBackFn) |f| {
            m.callBackFn = @ptrCast(&f);
        }
        self._optArgs = self._optArgs ++ [_]meta.OptArg{.{
            .meta = m,
            .short = config.short,
            .long = config.long,
            .arg_name = config.arg_name orelse &upper(name),
        }};
        return self;
    }

    test "optArg, Compile, short and long" {
        // error: opt(Arg)<name> at least one of short or long is required
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("name", u32, .{});
    }

    test "optArg, Compile, pointer but not slice" {
        // error: optArg<name> not accept *[]const u8
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("name", *[]const u8, .{ .short = 'n' });
    }

    test "optArg, Compile, slice but not const" {
        // error: optArg<name> not accept []u32
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("name", []u32, .{ .short = 'n' });
    }

    test "optArg, Compile, default for Slice" {
        // error: optArg<num> not support default for Slice
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.optArg("num", []const u32, .{ .short = 'n', .default = &[_]u32{ 1, 2 } });
    }

    pub fn posArg(
        self: *Self,
        name: [:0]const u8,
        T: type,
        config: struct {
            default: ?T = null,
            help: ?[]const u8 = null,
            arg_name: ?[]const u8 = null,
            parseFn: ?parser.Fn(parser.Base(T)) = null,
            callBackFn: ?fn (*T) void = null,
        },
    ) *Self {
        if (self.use_subCmd) |s| {
            @compileError("posArg:" ++ name ++ " not accept because subCmd<" ++ s ++ "> exist");
        }
        self.checkName(name);
        var m: meta.Meta = .{ .name = name, .T = T, .help = config.help, .log = self.log };
        if (config.default) |v| {
            m.default = @ptrCast(&v);
        }
        if (config.parseFn) |f| {
            m.parseFn = @ptrCast(&f);
        }
        if (config.callBackFn) |f| {
            m.callBackFn = @ptrCast(&f);
        }
        self._posArgs = self._posArgs ++ [_]meta.PosArg{.{
            .meta = m,
            .arg_name = config.arg_name orelse &upper(name),
        }};
        return self;
    }

    test "posArg, Compile, conflict with subCmd" {
        // error: posArg<pos> not accept because subCmd<name> exist
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        const sub: Self = .{ .name = "sub" };
        comptime var cmd: Self = .{ .name = "test", .use_subCmd = "name" };
        _ = cmd.subCmd(sub);
        _ = cmd.posArg("pos", u32, .{});
    }

    fn checkSubCmd(self: *const Self, name: [:0]const u8) void {
        for (self._subCmds) |c| {
            if (std.mem.eql(u8, c.name, name)) {
                @compileError(self.use_subCmd.? ++ "." ++ name ++ " alreay exist");
            }
        }
    }

    test "subCmd, Compile, alreay exist" {
        // error: sub.sub0 alreay exist
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test", .use_subCmd = "sub" };
        _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub0" });
    }

    pub fn subCmd(self: *Self, c: Self) *Self {
        if (self.use_subCmd == null) {
            @compileError("?." ++ c.name ++ " not accept because use_subCmd is null");
        }
        self.checkSubCmd(c.name);
        self._subCmds = self._subCmds ++ [_]Self{c};
        return self;
    }

    test "subCmd, Compile, not accept" {
        // error: ?.sub not accept because use_subCmd is null
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test" };
        _ = cmd.subCmd(.{ .name = "sub" });
    }

    fn usagePre(self: Self) []const u8 {
        var s: []const u8 = self.name;
        if (self.use_builtin_help) {
            s = s ++ " " ++ Builtin.help.usage();
        }
        for (self._opts) |m| {
            s = s ++ " " ++ m.usage();
        }
        for (self._optArgs) |m| {
            s = s ++ " " ++ m.usage();
        }
        if (self._posArgs.len != 0 or self._subCmds.len != 0) {
            s = s ++ " [--]";
        }
        for (self._posArgs) |m| {
            if (m.meta.default == null)
                s = s ++ " " ++ m.usage();
        }
        for (self._posArgs) |m| {
            if (m.meta.default != null)
                s = s ++ " " ++ m.usage();
        }
        if (self._subCmds.len != 0) {
            s = s ++ " {";
        }
        for (self._subCmds, 0..) |c, i| {
            s = s ++ (if (i == 0) "" else "|") ++ c.name;
        }
        if (self._subCmds.len != 0) {
            s = s ++ "}";
        }
        return s;
    }

    pub fn usage(self: Self) *const [self.usagePre().len:0]u8 {
        return std.fmt.comptimePrint("{s}", .{comptime self.usagePre()});
    }

    test "usage without subCmds" {
        const Color = enum { Red, Green, Blue };

        comptime var cmd: Self = .{ .name = "exp", .log = null };

        _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });

        _ = cmd.optArg("optional_int", u32, .{ .long = "oint", .default = 1, .arg_name = "OptionalInt" });
        _ = cmd.optArg("int", u32, .{ .long = "int" });
        _ = cmd.optArg("color", Color, .{ .long = "color", .default = Color.Blue });
        _ = cmd.optArg("3word", [3][]const u8, .{ .long = "3word", .arg_name = "WORD" });

        _ = cmd.posArg("optional_pos_int", u32, .{ .help = "give me a u32", .arg_name = "Num", .default = 9 });
        _ = cmd.posArg("pos_int", u32, .{ .help = "give me a u32" });
        _ = cmd.posArg("optional_2pos_int", [2]u32, .{ .help = "give me two u32", .arg_name = "Num", .default = .{ 1, 2 } });

        try testing.expectEqualStrings(
            "exp [-v]... [-h|--help] [--oint {OptionalInt}] --int {INT} [--color {COLOR}] --3word {[3]WORD} [--] {POS_INT} [{Num}] [{[2]Num}]",
            comptime cmd.usage(),
        );
    }

    test "usage with subCmds" {
        comptime var cmd: Self = .{ .name = "exp", .log = null, .use_subCmd = "sub" };
        _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });
        _ = cmd.optArg("int", u32, .{ .long = "int" });
        _ = cmd.subCmd(.{ .name = "install" }).subCmd(.{ .name = "remove" }).subCmd(.{ .name = "version" });

        try testing.expectEqualStrings(
            "exp [-v]... [-h|--help] --int {INT} [--] {install|remove|version}",
            comptime cmd.usage(),
        );
    }

    fn helpPre(self: Self) []const u8 {
        var msg: []const u8 = "Usage: " ++ self.usage();
        if (self.description) |s| {
            msg = msg ++ "\n\n" ++ s;
        }
        if (self.version != null or self.author != null or self.homepage != null) {
            msg = msg ++ "\n\n";
        }
        if (self.version) |s| {
            msg = msg ++ "Version " ++ s ++
                if (self.author != null or self.homepage != null) "\t" else "";
        }
        if (self.author) |s| {
            msg = msg ++ "Author <" ++ s ++ ">" ++
                if (self.homepage != null) "\t" else "";
        }
        if (self.homepage) |s| {
            msg = msg ++ "Homepage " ++ s;
        }
        if (self._opts.len != 0 or self.use_builtin_help) {
            msg = msg ++ "\n";
        }
        if (self.use_builtin_help) {
            msg = msg ++ "\n" ++ Builtin.help.help();
        }
        for (self._opts) |m| {
            msg = msg ++ "\n" ++ m.help();
        }
        if (self._optArgs.len != 0) {
            msg = msg ++ "\n";
        }
        for (self._optArgs) |m| {
            msg = msg ++ "\n" ++ m.help();
        }
        if (self._posArgs.len != 0) {
            msg = msg ++ "\n";
        }
        for (self._posArgs) |m| {
            msg = msg ++ "\n" ++ m.help();
        }
        if (self._subCmds.len != 0) {
            msg = msg ++ "\n";
        }
        for (self._subCmds) |m| {
            if (m.description) |s| {
                msg = msg ++ "\n" ++ std.fmt.comptimePrint("{s:<30} {s}", .{ m.name, s });
            } else {
                msg = msg ++ "\n" ++ m.name;
            }
        }
        return msg;
    }

    pub fn help(self: Self) *const [self.helpPre().len:0]u8 {
        return std.fmt.comptimePrint("{s}", .{comptime self.helpPre()});
    }

    test "help" {
        comptime var cmd: Self = .{ .name = "exp", .log = null, .use_subCmd = "sub" };
        _ = cmd.opt("verbose", u8, .{ .short = 'v' }).optArg("int", i32, .{ .long = "int", .help = "Give me an integer" });
        _ = cmd.subCmd(.{ .name = "install" }).subCmd(.{ .name = "remove", .description = "Remove something" }).subCmd(.{ .name = "version" });

        try testing.expectEqualStrings(
            \\Usage: exp [-h|--help] [-v]... --int {INT} [--] {install|remove|version}
            \\
            \\[-h|--help]                    Show this help then exit
            \\[-v]...
            \\
            \\--int {INT}                    Give me an integer
            \\
            \\install
            \\remove                         Remove something
            \\version
        ,
            comptime cmd.help(),
        );
    }

    const StructField = std.builtin.Type.StructField;
    const EnumField = std.builtin.Type.EnumField;
    const UnionField = std.builtin.Type.UnionField;

    fn SubCmdUnion(self: Self) type {
        var e: []const EnumField = &.{};
        var u: []const UnionField = &.{};
        for (self._subCmds, 0..) |m, i| {
            e = e ++ [_]EnumField{.{ .name = m.name, .value = i }};
            u = u ++ [_]UnionField{.{ .name = m.name, .type = m.Result(), .alignment = @alignOf(m.Result()) }};
        }
        const E = @Type(.{ .Enum = .{
            .tag_type = std.math.IntFittingRange(0, e.len - 1),
            .fields = e,
            .decls = &.{},
            .is_exhaustive = true,
        } });
        const U = @Type(.{ .Union = .{
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
            .default_value = null,
            .is_comptime = false,
            .name = self.use_subCmd.?,
            .type = U,
        };
    }

    fn Result(self: Self) type {
        var r = @typeInfo(struct {}).Struct;
        for (self._opts) |m| {
            r.fields = r.fields ++ [_]StructField{m.meta.toField()};
        }
        for (self._optArgs) |m| {
            r.fields = r.fields ++ [_]StructField{m.meta.toField()};
        }
        for (self._posArgs) |m| {
            r.fields = r.fields ++ [_]StructField{m.meta.toField()};
        }
        if (self.use_subCmd) |s| {
            if (self._subCmds.len == 0) {
                @compileError("subCmd<" ++ s ++ "> use_subCmd is given, but no cmds has been added");
            }
            r.fields = r.fields ++ [_]StructField{self.subCmdField()};
        }
        return @Type(.{ .Struct = r });
    }

    test "subCmd, Compile, no cmds has been added" {
        // error: subCmd<sub> use_subCmd is given, but no cmds has been added
        const skip = true;
        if (skip)
            return error.SkipZigTest;
        comptime var cmd: Self = .{ .name = "test", .use_subCmd = "sub" };
        _ = cmd.Result();
    }

    pub fn destory(self: Self, r: *const self.Result(), allocator: std.mem.Allocator) void {
        inline for (self._optArgs) |m| {
            if (@typeInfo(m.meta.T) == .Pointer) {
                allocator.free(@field(r, m.meta.name));
            }
        }
        inline for (self._posArgs) |m| {
            if (@typeInfo(m.meta.T) == .Pointer) {
                allocator.free(@field(r, m.meta.name));
            }
        }
        if (self.use_subCmd) |s| {
            inline for (self._subCmds) |c| {
                if (std.enums.nameCast(std.meta.Tag(self.SubCmdUnion()), c.name) == @field(r, s)) {
                    const sub = &@field(@field(r, s), c.name);
                    c.destory(sub, allocator);
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

    fn errCastIter(self: Self, cap: Iter.Error) Error {
        if (self.log) |log| {
            log("TokenIter Error <{any}>", .{cap});
        }
        return Error.TokenIter;
    }

    fn errCastMeta(self: Self, cap: meta.Error, is_pos: bool) Error {
        return switch (cap) {
            meta.Error.Allocator => blk: {
                if (self.log) |log| {
                    log("Allocator Error <{any}>", .{cap});
                }
                break :blk Error.Allocator;
            },
            meta.Error.Invalid => if (is_pos) Error.InvalidPosArg else Error.InvalidOptArg,
            meta.Error.Missing => if (is_pos) Error.MissingPosArg else Error.MissingOptArg,
            else => unreachable,
        };
    }

    pub fn parse(self: Self, it: *Iter) Error!self.Result() {
        return self.parseAlloc(it, null);
    }

    pub fn parseAlloc(self: Self, it: *Iter, allocator: ?std.mem.Allocator) Error!self.Result() {
        var hitOpts: StringSet(self._opts.len + self._optArgs.len) = .{};
        hitOpts.init();

        var r = std.mem.zeroInit(self.Result(), if (self.use_subCmd) |s| blk: {
            comptime var info = @typeInfo(struct {}).Struct;
            info.fields = info.fields ++ [_]StructField{self.subCmdField()};
            const I = @Type(.{ .Struct = info });
            var i: I = undefined;
            @field(i, s) = undefined;
            break :blk i;
        } else .{});

        while (it.view() catch |e| return self.errCastIter(e)) |top| {
            switch (top) {
                .opt => |o| {
                    var hit = false;
                    if (self.use_builtin_help) {
                        if (meta.hitOpt(Builtin.help, top)) {
                            if (self.log) |log| {
                                log("{s}", .{self.help()});
                            }
                            std.process.exit(1);
                        }
                    }
                    inline for (self._opts) |m| {
                        hit = m.consume(&r, it);
                        if (hit) {
                            if (!hitOpts.add(m.meta.name)) {
                                if (m.meta.T != bool) break;
                                if (self.log) |log| {
                                    log("opt:{s} repeat with {}", .{ m.meta.name, o });
                                }
                                return Error.RepeatOpt;
                            }
                            break;
                        }
                    }
                    if (hit) continue;
                    inline for (self._optArgs) |m| {
                        if (m.meta.isSlice() and allocator == null) {
                            if (self.log) |log| {
                                log("optArg:{s} allocator is required", .{m.meta.name});
                            }
                            return Error.Allocator;
                        }
                        hit = m.consume(&r, it, allocator) catch |e| return self.errCastMeta(e, false);
                        if (hit) {
                            if (!hitOpts.add(m.meta.name)) {
                                if (m.meta.isSlice()) break;
                                if (self.log) |log| {
                                    log("optArg:{s} repeat with {}", .{ m.meta.name, o });
                                }
                                return Error.RepeatOpt;
                            }
                            break;
                        }
                    }
                    if (hit) continue;
                    if (self.log) |log| {
                        log("Unknown option {}", .{o});
                    }
                    return Error.UnknownOpt;
                },
                .posArg, .arg => {
                    it.flag_termiantor = true;
                    break;
                },
                else => unreachable,
            }
        }
        inline for (self._optArgs) |m| {
            if (m.meta.default == null) {
                if (!m.meta.isSlice() and !hitOpts.contain(m.meta.name)) {
                    if (self.log) |log| {
                        const u = comptime m.usage();
                        log("optArg:{s} is required, but not found {s}", .{ m.meta.name, u });
                    }
                    return Error.MissingOptArg;
                }
            }
        }
        inline for (self._posArgs) |m| {
            if (m.meta.default == null) {
                m.consume(&r, it, allocator) catch |e| return self.errCastMeta(e, true);
            }
        }
        inline for (self._posArgs) |m| {
            if (m.meta.default != null) {
                if ((it.view() catch |e| return self.errCastIter(e)) == null) break;
                m.consume(&r, it, allocator) catch |e| return self.errCastMeta(e, true);
            }
        }
        if (self.use_subCmd) |s| {
            if ((it.view() catch |e| return self.errCastIter(e)) == null) {
                if (self.log) |log| {
                    log("subCmd<" ++ s ++ "> is required, but not found", .{});
                }
                return Error.MissingSubCmd;
            }
            inline for (self._subCmds) |c| {
                if (try c.consume(s, &r, it, allocator)) {
                    return r;
                }
            }
            if (self.log) |log| {
                log("Unknown subCmd {s}", .{(it.viewMust() catch unreachable).as_posArg().posArg});
            }
            return Error.UnknownSubCmd;
        }
        return r;
    }

    fn consume(self: Self, comptime s: []const u8, r: anytype, it: *Iter, allocator: ?std.mem.Allocator) Error!bool {
        const c = (it.viewMust() catch unreachable).as_posArg().posArg;
        if (std.mem.eql(u8, self.name, c)) {
            _ = it.next() catch unreachable;
            _ = it.reinit(it.config);
            @field(r, s) = @unionInit(@TypeOf(@field(r, s)), self.name, try self.parseAlloc(it, allocator));
            return true;
        }
        return false;
    }

    test "parse, Error RepeatOpt" {
        comptime var cmd: Self = .{ .name = "exp" };
        _ = cmd.opt("verbose", u8, .{ .short = 'v' }).opt("help", bool, .{ .long = "help", .short = 'h' });
        {
            var it = try Iter.initLine("-vvh --help", null, .{});
            defer it.deinit();
            try testing.expectError(Error.RepeatOpt, cmd.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.optArg("number", u32, .{ .long = "num" });
            var it = try Iter.initLine("--num 1 --num 2", null, .{});
            defer it.deinit();
            try testing.expectError(Error.RepeatOpt, c.parse(&it));
        }
    }

    test "parse, Error UnknownOpt" {
        comptime var cmd: Self = .{ .name = "exp" };
        var it = try Iter.initLine("-a", null, .{});
        defer it.deinit();
        try testing.expectError(Error.UnknownOpt, cmd.parse(&it));
    }

    test "parse, Error MissingOptArg" {
        const cmd: Self = .{ .name = "exp" };
        {
            comptime var c = cmd;
            _ = c.optArg("file", []const u8, .{ .short = 'f' });
            var it = try Iter.initLine("-f -a", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingOptArg, c.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.optArg("u32s", [2]u32, .{ .short = 'u' });
            var it = try Iter.initLine("-u 0xa", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingOptArg, c.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.optArg("u32s", [2]u32, .{ .short = 'u' });
            var it = try Iter.initLine("-u=0xa 1", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingOptArg, c.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.optArg("file", []const u8, .{ .short = 'f' });
            var it = try Iter.initLine("", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingOptArg, c.parse(&it));
        }
    }

    test "parse, Error InvalidOptArg" {
        const cmd: Self = .{ .name = "exp" };
        {
            comptime var c = cmd;
            _ = c.optArg("number", u32, .{ .long = "num" });
            var it = try Iter.initLine("--num=a", null, .{});
            defer it.deinit();
            try testing.expectError(Error.InvalidOptArg, c.parse(&it));
        }
        {
            const lastCharacter = struct {
                fn p(s: []const u8) ?u8 {
                    return if (s.len == 0) null else s[s.len - 1];
                }
            }.p;
            comptime var c = cmd;
            _ = c.optArg("lastc", u8, .{ .short = 'l', .parseFn = lastCharacter });
            var it = try Iter.initList(&[_][]const u8{ "-l", "" }, .{});
            defer it.deinit();
            try testing.expectError(Error.InvalidOptArg, c.parse(&it));
        }
        {
            const Color = enum { Red, Green, Blue };
            comptime var c = cmd;
            _ = c.optArg("color", Color, .{ .long = "color" });
            var it = try Iter.initLine("--color red", null, .{});
            defer it.deinit();
            try testing.expectError(Error.InvalidOptArg, c.parse(&it));
        }
    }

    test "parse, Error MissingPosArg" {
        const cmd: Self = .{ .name = "exp" };
        {
            comptime var c = cmd;
            _ = c.posArg("number", u32, .{});
            var it = try Iter.initLine("", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingPosArg, c.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.posArg("numbers", [2]u32, .{ .default = .{ 1, 2 } });
            var it = try Iter.initLine("9", null, .{});
            defer it.deinit();
            try testing.expectError(Error.MissingPosArg, c.parse(&it));
        }
    }

    test "parse, Error InvalidPosArg" {
        comptime var cmd: Self = .{ .name = "exp" };
        _ = cmd.posArg("number", u32, .{});
        var it = try Iter.initLine("a", null, .{});
        defer it.deinit();
        try testing.expectError(Error.InvalidPosArg, cmd.parse(&it));
    }

    test "parse, Error MissingSubCmd" {
        comptime var cmd: Self = .{ .name = "exp", .use_subCmd = "sub" };
        _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub1" });
        var it = try Iter.initLine("", null, .{});
        defer it.deinit();
        try testing.expectError(Error.MissingSubCmd, cmd.parse(&it));
    }

    test "parse, Error UnknownSubCmd" {
        comptime var cmd: Self = .{ .name = "exp", .use_subCmd = "sub" };
        _ = cmd.subCmd(.{ .name = "sub0" }).subCmd(.{ .name = "sub1" });
        var it = try Iter.initLine("abc", null, .{});
        defer it.deinit();
        try testing.expectError(Error.UnknownSubCmd, cmd.parse(&it));
    }

    test "parse, Error Allocator" {
        comptime var cmd: Self = .{ .name = "exp" };
        _ = cmd.optArg("slice", []const u32, .{ .short = 'n' });
        var it = try Iter.initLine("-n 1", null, .{});
        defer it.deinit();
        try testing.expectError(Error.Allocator, cmd.parse(&it));
    }

    test "parse, Error TokenIter" {
        const cmd: Self = .{ .name = "exp" };
        {
            comptime var c = cmd;
            var it = try Iter.initLine("--help=", null, .{});
            defer it.deinit();
            try testing.expectError(Error.TokenIter, c.parse(&it));
        }
        {
            comptime var c = cmd;
            _ = c.posArg("number", u32, .{ .default = 1 });
            var it = try Iter.initLine("-a=", null, .{});
            defer it.deinit();
            try testing.expectError(Error.TokenIter, c.parse(&it));
        }
        {
            comptime var c = cmd;
            var it = try Iter.initLine("--", null, .{ .terminator = "==" });
            defer it.deinit();
            try testing.expectError(Error.TokenIter, c.parse(&it));
        }
        {
            comptime var c = cmd;
            var it = try Iter.initLine("-", null, .{});
            defer it.deinit();
            try testing.expectError(Error.TokenIter, c.parse(&it));
        }
    }
};

test {
    _ = Command;
    _ = @import("token.zig");
}
