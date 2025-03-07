const std = @import("std");
const testing = std.testing;

const String = []const u8;

pub const Type = union(enum) {
    const FormatOptions = std.fmt.FormatOptions;
    pub const Opt = union(enum) {
        /// Short option that follows the prefix_short
        short: u8,
        /// Long option that follows the prefix_long
        long: String,
        pub fn format(self: @This(), comptime _: []const u8, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            try writer.writeAll(@tagName(self));
            try writer.writeAll("<");
            switch (self) {
                .short => |s| {
                    try std.fmt.format(writer, "{c}", .{s});
                },
                .long => |l| {
                    try std.fmt.formatBuf(l, options, writer);
                },
            }
            try writer.writeAll(">");
        }
    };
    opt: Opt,
    /// Option argument that follows the connector_optarg
    optArg: String,
    /// Positional argument that meets after the terminator
    posArg: String,
    /// Positional argument, and maybe Option argument
    arg: String,

    const Self = @This();

    pub fn as_posArg(self: Self) Self {
        const arg = switch (self) {
            .opt, .optArg => unreachable,
            .posArg => return self,
            .arg => |a| a,
        };
        return .{ .posArg = arg };
    }
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try writer.writeAll(@tagName(self));
        try writer.writeAll("<");
        switch (self) {
            .opt => |o| {
                try o.format(fmt, options, writer);
            },
            .optArg, .posArg, .arg => |a| {
                try std.fmt.formatBuf(a, options, writer);
            },
        }
        try writer.writeAll(">");
    }
};

fn IterWrapper(I: type, R: type, specifier: ?[]const u8) type {
    if (!@hasDecl(I, "go")) {
        @compileError(std.fmt.comptimePrint("Require {s}.go", .{@typeName(I)}));
    }
    const is_ErrorUnion = @typeInfo(R) == .ErrorUnion;
    const BaseR = switch (@typeInfo(R)) {
        .Optional => |info| info.child,
        .ErrorUnion => |info| switch (@typeInfo(info.payload)) {
            .Optional => |info_| info_.child,
            else => @compileError(std.fmt.comptimePrint("Require {s}.go return E!?T instead of {s}", .{ @typeName(I), @typeName(R) })),
        },
        else => @compileError(std.fmt.comptimePrint("Require {s}.go return (E!)?T instead of {s}", .{ @typeName(I), @typeName(R) })),
    };
    return struct {
        const Self = @This();
        it: I,
        cache: ?R = null,
        debug: bool = false,
        fn log(self: *const Self, comptime fmt: []const u8, args: anytype) void {
            if (!self.debug) return;
            std.debug.print(fmt, args);
        }
        pub fn next(self: *Self) R {
            var s: []const u8 = "";
            const item = if (self.cache) |i| blk: {
                self.cache = null;
                s = "(Cached)";
                break :blk i;
            } else self.it.go();
            self.log("\x1b[95mnext\x1b[90m{s}\x1b[0m {" ++ (specifier orelse "") ++ "}\n", .{ s, item });
            return item;
        }
        pub fn view(self: *Self) R {
            var s: []const u8 = "(Cached)";
            if (self.cache == null) {
                self.cache = self.it.go();
                s = "";
            }
            const item = self.cache.?;
            self.log("\x1b[92mview\x1b[90m{s}\x1b[0m {" ++ (specifier orelse "") ++ "}\n", .{ s, item });
            return item;
        }
        pub fn init(it: I) Self {
            return .{ .it = it };
        }
        pub fn deinit(self: *Self) void {
            if (@hasDecl(I, "deinit")) {
                self.it.deinit();
            }
        }
        pub fn nextAll(self: *Self, allocator: std.mem.Allocator) ![]const BaseR {
            var items = std.ArrayList(BaseR).init(allocator);
            defer items.deinit();
            while (if (is_ErrorUnion) (try self.next()) else self.next()) |item| {
                try items.append(item);
            }
            return try items.toOwnedSlice();
        }
    };
}

test "Wrap Compile, T" {
    // error: Require token.ListIter(i32).go return (E!)?T instead of i32
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    _ = IterWrapper(ListIter(i32), i32, null);
}

test "Wrap Compile, E!T" {
    // error: Require token.ListIter(i32).go return E!?T instead of error{Compile}!i32
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    _ = IterWrapper(ListIter(i32), error{Compile}!i32, null);
}

test "Wrap, normal" {
    var it = IterWrapper(ListIter(u32), ?u32, "?").init(.{ .list = &[_]u32{ 1, 2, 3, 4 } });
    it.debug = true;
    defer it.deinit();
    try testing.expectEqual(1, it.view().?);
    try testing.expectEqual(1, it.view().?);
    try testing.expectEqual(1, it.next().?);
    try testing.expectEqual(2, it.next().?);
    try testing.expectEqual(3, it.next().?);
    try testing.expectEqual(4, it.view().?);
    try testing.expectEqual(4, it.next().?);
    try testing.expectEqual(null, it.view());
    try testing.expectEqual(null, it.next());
}

test "Wrap, nextAll" {
    var it = IterWrapper(ListIter(u32), ?u32, "?").init(.{ .list = &[_]u32{ 1, 2, 3, 4 } });
    it.debug = true;
    defer it.deinit();
    try testing.expectEqual(1, it.view().?);
    const remain = try it.nextAll(testing.allocator);
    defer testing.allocator.free(remain);
    try testing.expectEqualSlices(u32, &[_]u32{ 1, 2, 3, 4 }, remain);
    try testing.expectEqual(null, it.next());
}

fn ListIter(T: type) type {
    return struct {
        const Self = @This();
        list: []const T,
        fn go(self: *Self) ?T {
            if (self.list.len == 0) {
                return null;
            }
            const item = self.list[0];
            self.list = self.list[1..];
            return item;
        }
    };
}

const BaseIter = union(enum) {
    const Self = @This();
    sys: std.process.ArgIterator,
    general: std.process.ArgIteratorGeneral(.{}),
    line: std.mem.TokenIterator(u8, .any),
    list: ListIter(String),

    fn go(self: *Self) ?String {
        return switch (self.*) {
            .sys => |*i| i.next(),
            .general => |*i| i.next(),
            .line => |*i| i.next(),
            .list => |*i| i.go(),
        };
    }
    fn deinit(self: *Self) void {
        switch (self.*) {
            .sys => |*i| i.deinit(),
            .general => |*i| i.deinit(),
            else => {},
        }
    }
};

pub const Config = struct {
    /// 匹配时，`terminator`优先于`prefix_long`
    terminator: String = "--",
    /// 匹配时，`prefix_long`优先于`prefix_short`
    prefix_long: String = "--",
    /// 匹配时，`prefix_long`优先于`prefix_short`
    prefix_short: String = "-",
    connector_optarg: String = "=",

    const Self = @This();
    const Error = error{
        PrefixLongEmpty,
        PrefixShortEmpty,
        ConnectorOptArgEmpty,
        TerminatorEmpty,
        PrefixLongShortEqual,
        PrefixLongHasSpace,
        PrefixShortHasSpace,
        ConnectorOptArgHasSpace,
        TerminatorHasSpace,
    };

    pub fn validate(self: *const Self) Error!void {
        if (self.prefix_long.len == 0) {
            return Error.PrefixLongEmpty;
        }
        if (self.prefix_short.len == 0) {
            return Error.PrefixShortEmpty;
        }
        if (self.connector_optarg.len == 0) {
            return Error.ConnectorOptArgEmpty;
        }
        if (self.terminator.len == 0) {
            return Error.TerminatorEmpty;
        }
        if (std.mem.eql(u8, self.prefix_long, self.prefix_short)) {
            return Error.PrefixLongShortEqual;
        }
        if (std.mem.indexOfAny(u8, self.prefix_long, " ")) |_| {
            return Error.PrefixLongHasSpace;
        }
        if (std.mem.indexOfAny(u8, self.prefix_short, " ")) |_| {
            return Error.PrefixShortHasSpace;
        }
        if (std.mem.indexOfAny(u8, self.connector_optarg, " ")) |_| {
            return Error.ConnectorOptArgHasSpace;
        }
        if (std.mem.indexOfAny(u8, self.terminator, " ")) |_| {
            return Error.TerminatorHasSpace;
        }
    }

    test "Config validate" {
        try testing.expectError(Error.PrefixLongEmpty, (Self{ .prefix_long = "" }).validate());
        try testing.expectError(Error.PrefixShortEmpty, (Self{ .prefix_short = "" }).validate());
        try testing.expectError(Error.ConnectorOptArgEmpty, (Self{ .connector_optarg = "" }).validate());
        try testing.expectError(Error.TerminatorEmpty, (Self{ .terminator = "" }).validate());
        try testing.expectError(Error.PrefixLongShortEqual, (Self{ .prefix_long = "-", .prefix_short = "-" }).validate());
        try testing.expectError(Error.PrefixLongHasSpace, (Self{ .prefix_long = "a b" }).validate());
        try testing.expectError(Error.PrefixShortHasSpace, (Self{ .prefix_short = "a b" }).validate());
        try testing.expectError(Error.ConnectorOptArgHasSpace, (Self{ .connector_optarg = "a b" }).validate());
        try testing.expectError(Error.TerminatorHasSpace, (Self{ .terminator = "a b" }).validate());
    }
};

fn trimString(s: String) String {
    var t = std.mem.trim(u8, s, " \t\n");
    if (t.len >= 2) {
        if (t[0] == '"' and t[t.len - 1] == '"') {
            t = t[0 .. t.len - 1][1..];
        }
    }
    return t;
}

test trimString {
    try testing.expectEqualStrings("ab", trimString(" ab\t  "));
    try testing.expectEqualStrings("\"ab", trimString("\"ab "));
    try testing.expectEqualStrings("ab", trimString("\"ab\" "));
    try testing.expectEqualStrings("", trimString("\"\" "));
    try testing.expectEqualStrings("", trimString(" "));
    try testing.expectEqualStrings("a", trimString(" a"));
}

const FSM = struct {
    const Error = error{
        MissingOptionArgument,
        MissingLongOption,
        MissingShortOption,
    };
    const Short = struct {
        const Self = @This();
        connector: String,
        _state: State,
        const State = union(enum) { begin: String, end, optArg: String, multi: String };
        fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin => |s| {
                        if (s.len == 0) {
                            return Error.MissingShortOption;
                        }
                        if (std.mem.startsWith(u8, s, self.connector)) {
                            return Error.MissingShortOption;
                        }
                        self._state = .{ .multi = s };
                    },
                    .end => return null,
                    .optArg => |s| {
                        if (s.len == 0) {
                            return Error.MissingOptionArgument;
                        }
                        self._state = .end;
                        return .{ .optArg = trimString(s) };
                    },
                    .multi => |s| {
                        if (s.len == 0) {
                            self._state = .end;
                        } else {
                            if (std.mem.startsWith(u8, s, self.connector)) {
                                self._state = .{ .optArg = s[self.connector.len..] };
                            } else {
                                self._state = .{ .multi = s[1..] };
                                return .{ .opt = .{ .short = s[0] } };
                            }
                        }
                    },
                }
            }
        }
        fn init(s: String, connector: String) Self {
            return .{ .connector = connector, ._state = .{ .begin = s } };
        }
        test "FSM, Short, normal single" {
            {
                var fsm = Short.init("a", "=");
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm = Short.init("a=hello", "=");
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Short, normal multiple" {
            {
                var fsm = Short.init("abc", "=");
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual('b', (try fsm.go()).?.opt.short);
                try testing.expectEqual('c', (try fsm.go()).?.opt.short);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm = Short.init("abc=hello", "=");
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual('b', (try fsm.go()).?.opt.short);
                try testing.expectEqual('c', (try fsm.go()).?.opt.short);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Short, empty argument" {
            var fsm = Short.init("a=\"\"", "=");
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Short, argument with space" {
            var fsm = Short.init("a=\" a\"", "=");
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectEqualStrings(" a", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Short, MissingOptionArgument" {
            var fsm = Short.init("a=", "=");
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
        }
        test "FSM, Short, MissingShortOption" {
            {
                var fsm = Short.init("=", "=");
                try testing.expectError(Error.MissingShortOption, fsm.go());
                try testing.expectError(Error.MissingShortOption, fsm.go());
            }
            {
                var fsm = Short.init("", "=");
                try testing.expectError(Error.MissingShortOption, fsm.go());
                try testing.expectError(Error.MissingShortOption, fsm.go());
            }
        }
        test "Wrap, FSM, Short" {
            var it = IterWrapper(Short, Error!?Type, "!?").init(Short.init("ac=hello", "="));
            it.debug = true;
            defer it.deinit();
            try testing.expectEqual('a', (try it.view()).?.opt.short);
            try testing.expectEqual('a', (try it.view()).?.opt.short);
            try testing.expectEqual('a', (try it.next()).?.opt.short);
            try testing.expectEqual('c', (try it.view()).?.opt.short);
            try testing.expectEqual('c', (try it.next()).?.opt.short);
            try testing.expectEqualStrings("hello", (try it.next()).?.optArg);
            try testing.expectEqual(null, try it.view());
            try testing.expectEqual(null, try it.next());
        }
    };
    const Long = struct {
        const Self = @This();
        connector: String,
        _state: State,
        const State = union(enum) { begin: String, end, optArg: String };
        fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin => |s| {
                        if (s.len == 0) {
                            return Error.MissingLongOption;
                        }
                        if (std.mem.indexOf(u8, s, self.connector)) |i| {
                            if (i == 0) {
                                return Error.MissingLongOption;
                            }
                            self._state = .{ .optArg = s[i..][self.connector.len..] };
                            return .{ .opt = .{ .long = trimString(s[0..i]) } };
                        } else {
                            self._state = .end;
                            return .{ .opt = .{ .long = trimString(s) } };
                        }
                    },
                    .end => return null,
                    .optArg => |s| {
                        if (s.len == 0) {
                            return Error.MissingOptionArgument;
                        }
                        self._state = .end;
                        return .{ .optArg = trimString(s) };
                    },
                }
            }
        }
        fn init(s: String, connector: String) Self {
            return .{ .connector = connector, ._state = .{ .begin = s } };
        }
        test "FSM, Long, normal" {
            {
                var fsm = Long.init("word", "=");
                try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm = Long.init("word=hello", "=");
                try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Long, empty argument" {
            var fsm = Long.init("word=\"\"", "=");
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, argument with space" {
            var fsm = Long.init("word=\" a\"", "=");
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings(" a", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, MissingOptionArgument" {
            var fsm = Long.init("word=", "=");
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
        }
        test "FSM, Long, MissingLongOption" {
            {
                var fsm = Long.init("=", "=");
                try testing.expectError(Error.MissingLongOption, fsm.go());
                try testing.expectError(Error.MissingLongOption, fsm.go());
            }
            {
                var fsm = Long.init("", "=");
                try testing.expectError(Error.MissingLongOption, fsm.go());
                try testing.expectError(Error.MissingLongOption, fsm.go());
            }
        }
        test "FSM, Long, mess" {
            var fsm = Long.init("\" word\"=\"\"", "=");
            try testing.expectEqualStrings(" word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, short length" {
            var fsm = Long.init("a", "=");
            try testing.expectEqualStrings("a", (try fsm.go()).?.opt.long);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
    };
    const Token = struct {
        const Self = @This();
        const It = IterWrapper(BaseIter, ?String, "?s");
        it: It,
        config: Config,
        _state: State = .begin,
        const State = union(enum) {
            begin,
            end,
            next,
            pos,
            short: FSM.Short,
            long: FSM.Long,
        };
        fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin, .next => {
                        if (self._state == .next) {
                            _ = self.it.next() orelse unreachable;
                        }
                        if (self.it.view()) |item| {
                            if (std.mem.eql(u8, item, self.config.terminator)) {
                                self._state = .pos;
                            } else if (std.mem.startsWith(u8, item, self.config.prefix_long)) {
                                self._state = .{ .long = Long.init(
                                    item[self.config.prefix_long.len..],
                                    self.config.connector_optarg,
                                ) };
                            } else if (std.mem.startsWith(u8, item, self.config.prefix_short)) {
                                self._state = .{ .short = Short.init(
                                    item[self.config.prefix_short.len..],
                                    self.config.connector_optarg,
                                ) };
                            } else {
                                self._state = .next;
                                return .{ .arg = trimString(item) };
                            }
                        } else self._state = .end;
                    },
                    .pos => {
                        _ = self.it.next() orelse unreachable;
                        if (self.it.view()) |item| {
                            return .{ .posArg = trimString(item) };
                        } else self._state = .end;
                    },
                    .end => return null,
                    .short => |*it_s| {
                        if (try it_s.go()) |item| {
                            return item;
                        } else self._state = .next;
                    },
                    .long => |*it_l| {
                        if (try it_l.go()) |item| {
                            return item;
                        } else self._state = .next;
                    },
                }
            }
        }
        fn init(it: BaseIter, config: Config) !Self {
            try config.validate();
            return .{ .it = It.init(it), .config = config };
        }
        fn deinit(self: *Self) void {
            self.it.deinit();
        }
        test "FSM, Token, normal" {
            const it_: BaseIter = .{ .list = .{ .list = &[_]String{
                "-a",
                "--word=hello",
                "--verbose",
                "-ht=amd64",
                "arg",
                "--",
                "pos0",
                "pos1",
            } } };
            var it = try Self.init(it_, .{});
            it.it.debug = true;
            defer it.deinit();
            try testing.expectEqual('a', (try it.go()).?.opt.short);
            try testing.expectEqualStrings("word", (try it.go()).?.opt.long);
            try testing.expectEqualStrings("hello", (try it.go()).?.optArg);
            try testing.expectEqualStrings("verbose", (try it.go()).?.opt.long);
            try testing.expectEqual('h', (try it.go()).?.opt.short);
            try testing.expectEqual('t', (try it.go()).?.opt.short);
            try testing.expectEqualStrings("amd64", (try it.go()).?.optArg);
            try testing.expectEqualStrings("arg", (try it.go()).?.arg);
            try testing.expectEqualStrings("pos0", (try it.go()).?.posArg);
            try testing.expectEqualStrings("pos1", (try it.go()).?.posArg);
            try testing.expectEqual(null, try it.go());
            try testing.expectEqual(null, try it.go());
        }
        test "FSM, Token, MissingOptionArgument" {
            const it_: BaseIter = .{ .list = .{ .list = &[_]String{
                "-a",
                "--word=",
                "--verbose",
            } } };
            var it = try Self.init(it_, .{});
            it.it.debug = true;
            defer it.deinit();
            try testing.expectEqual('a', (try it.go()).?.opt.short);
            try testing.expectEqualStrings("word", (try it.go()).?.opt.long);
            try testing.expectError(Error.MissingOptionArgument, it.go());
            try testing.expectError(Error.MissingOptionArgument, it.go());
            try testing.expectEqualStrings("--word=", it.it.view().?);
            try testing.expectEqualStrings("--word=", it.it.next().?);
            try testing.expectEqualStrings("--verbose", it.it.next().?);
            try testing.expectEqual(null, it.it.next());
        }
        test "FSM, Token, MissingShortOption" {
            {
                const it_: BaseIter = .{ .list = .{ .list = &[_]String{ "-", "--verbose" } } };
                var it = try Self.init(it_, .{});
                it.it.debug = true;
                defer it.deinit();
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectEqualStrings("-", it.it.view().?);
                try testing.expectEqualStrings("-", it.it.next().?);
                try testing.expectEqualStrings("--verbose", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
            {
                const it_: BaseIter = .{ .list = .{ .list = &[_]String{"-="} } };
                var it = try Self.init(it_, .{});
                it.it.debug = true;
                defer it.deinit();
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectEqualStrings("-=", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
        }
        test "FSM, Token, MissingLongOption" {
            {
                const it_: BaseIter = .{ .list = .{ .list = &[_]String{ "-a", "--=", "--verbose" } } };
                var it = try Self.init(it_, .{});
                it.it.debug = true;
                defer it.deinit();
                try testing.expectEqual('a', (try it.go()).?.opt.short);
                try testing.expectError(Error.MissingLongOption, it.go());
                try testing.expectError(Error.MissingLongOption, it.go());
                try testing.expectEqualStrings("--=", it.it.view().?);
                try testing.expectEqualStrings("--=", it.it.next().?);
                try testing.expectEqualStrings("--verbose", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
            {
                const it_: BaseIter = .{ .list = .{ .list = &[_]String{ "-a", "--" } } };
                var it = try Self.init(it_, .{ .terminator = "**" });
                it.it.debug = true;
                defer it.deinit();
                try testing.expectEqual('a', (try it.go()).?.opt.short);
                try testing.expectError(Error.MissingLongOption, it.go());
                try testing.expectError(Error.MissingLongOption, it.go());
                try testing.expectEqualStrings("--", it.it.view().?);
                try testing.expectEqualStrings("--", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
        }
        test "FSM, Token, argument with space" {
            const it_: BaseIter = .{ .list = .{ .list = &[_]String{
                "hell o ",
                " \"world \" ",
            } } };
            var it = try Self.init(it_, .{});
            it.it.debug = true;
            defer it.deinit();
            try testing.expectEqualStrings("hell o", (try it.go()).?.arg);
            try testing.expectEqualStrings("world ", (try it.go()).?.arg);
            try testing.expectEqual(null, try it.go());
            try testing.expectEqual(null, try it.go());
        }
        test "FSM, Token, position with space" {
            const it_: BaseIter = .{ .list = .{ .list = &[_]String{
                "-a",
                "--",
                " \"world \" ",
            } } };
            var it = try Self.init(it_, .{});
            it.it.debug = true;
            defer it.deinit();
            try testing.expectEqual('a', (try it.go()).?.opt.short);
            try testing.expectEqualStrings("world ", (try it.go()).?.posArg);
            try testing.expectEqual(null, try it.go());
            try testing.expectEqual(null, try it.go());
        }
    };
    test {
        _ = Short;
        _ = Long;
        _ = Token;
    }
};

pub const Iter = struct {
    const Self = @This();
    pub const Error = FSM.Error;
    const It = IterWrapper(FSM.Token, Error!?Type, "!?");

    it: It,

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        try config.validate();
        const it = It.init(try FSM.Token.init(.{ .sys = try std.process.argsWithAllocator(allocator) }, config));
        return .{ .it = it };
    }
    pub fn initGeneral(allocator: std.mem.Allocator, line: String, config: Config) !Self {
        try config.validate();
        const it = It.init(try FSM.Token.init(.{ .general = try std.process.ArgIteratorGeneral(.{}).init(allocator, line) }, config));
        return .{ .it = it };
    }
    pub fn initLine(line: String, delimiters: ?String, config: Config) !Self {
        try config.validate();
        const it = It.init(try FSM.Token.init(.{ .line = std.mem.tokenizeAny(u8, line, delimiters orelse " \t\n") }, config));
        return .{ .it = it };
    }
    pub fn initList(list: []const String, config: Config) !Self {
        try config.validate();
        const it = It.init(try FSM.Token.init(.{ .list = .{ .list = list } }, config));
        return .{ .it = it };
    }
    pub fn deinit(self: *Self) void {
        self.it.deinit();
    }
    pub fn next(self: *Self) Error!?Type {
        return self.it.next();
    }
    pub fn nextMust(self: *Self) !Type {
        return (try self.next()) orelse error.NoMore;
    }
    pub fn view(self: *Self) Error!?Type {
        return self.it.view();
    }
    pub fn viewMust(self: *Self) !Type {
        return (try self.view()) orelse error.NoMore;
    }
    /// 😵 TODO
    pub fn nextAllBase(self: *Self, allocator: std.mem.Allocator) ![]const String {
        var items = std.ArrayList(String).init(allocator);
        defer items.deinit();
        while (self.it.it.it.next()) |item| {
            try items.append(item);
        }
        self.it.it._state = .end;
        return try items.toOwnedSlice();
    }
    /// 😵 TODO
    pub fn fsm_to_pos(self: *Self) void {
        self.it.it._state = .pos;
    }
    /// 😵 TODO
    pub fn reinit(self: *Self) void {
        self.it.it._state = .begin;
        self.it.cache = null;
        self.it.it.it.cache = null;
    }
    pub fn debug(self: *Self, b: bool) void {
        self.it.debug = b;
    }
};

test {
    _ = Iter;
    _ = Config;
    _ = FSM;
}
