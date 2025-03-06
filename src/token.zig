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
    {
        // const GoFn = fn (*I) R;
        // const GoFn_ = {}; // TODO howto get `go`'s type?
        // if (GoFn_ != GoFn) {
        //     @compileError(std.fmt.comptimePrint("Expect {s}.go is {s} but {s}", .{
        //         @typeName(I),
        //         @typeName(GoFn),
        //         @typeName(GoFn_),
        //     }));
        // }
    }
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
        pub fn deinit(self: *Self) void {
            if (@hasDecl(I, "deinit")) {
                self.it.deinit();
            }
        }
    };
}

const BaseIter = union(enum) {
    sys: std.process.ArgIterator,
    general: std.process.ArgIteratorGeneral(.{}),
    line: std.mem.TokenIterator(u8, .any),
    list: List,

    const Self = @This();

    const List = struct {
        list: []const String,
        fn next(self: *List) ?String {
            if (self.list.len == 0) {
                return null;
            }
            const token = self.list[0];
            self.list = self.list[1..];
            return token;
        }
    };
    fn go(self: *Self) ?String {
        return switch (self.*) {
            .sys => |*i| i.next(),
            .general => |*i| i.next(),
            .line => |*i| i.next(),
            .list => |*i| i.next(),
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

test "Wrap BaseIter" {
    var it: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = .{ .list = &[_]String{ "a", "b", "c" } } } };
    it.debug = true;
    defer it.deinit();
    try testing.expectEqualStrings("a", it.view().?);
    try testing.expectEqualStrings("a", it.view().?);
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expectEqualStrings("c", it.view().?);
    try testing.expectEqualStrings("c", it.next().?);
    try testing.expectEqual(null, it.next());
    try testing.expectEqual(null, it.view());
}

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
    const t = std.mem.trim(u8, s, " \t\n");
    return if (t[0] == '"' and t[t.len - 1] == '"') t[0 .. t.len - 1][1..] else t;
}

test trimString {
    try testing.expectEqualStrings("ab", trimString(" ab\t  "));
    try testing.expectEqualStrings("\"ab", trimString("\"ab "));
    try testing.expectEqualStrings("ab", trimString("\"ab\" "));
    try testing.expectEqualStrings("", trimString("\"\" "));
}

const FSM = struct {
    const Error = error{
        MissingOptionArgument,
        MissingLongOption,
        MissingShortOption,
        NoMore,
    };
    fn toOptArg(s: String, connector: String) Error!Type {
        const a = s[connector.len..];
        if (a.len == 0) {
            return Error.MissingOptionArgument;
        } else {
            return .{ .optArg = trimString(a) };
        }
    }
    const Short = struct {
        const Self = @This();
        s: ?String,
        connector: String,
        _state: State = .begin,
        const State = union(enum) { begin, end, optArg: String, multi: String };
        fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin => {
                        if (self.s) |s| {
                            if (s.len == 0) {
                                return Error.MissingShortOption;
                            }
                            if (std.mem.startsWith(u8, s, self.connector)) {
                                return Error.MissingShortOption;
                            }
                            self._state = .{ .multi = s };
                        } else self._state = .end;
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
        test "FSM, Short, normal single" {
            {
                var fsm: Short = .{ .s = "a", .connector = "=" };
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm: Short = .{ .s = "a=hello", .connector = "=" };
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Short, normal multiple" {
            {
                var fsm: Short = .{ .s = "abc", .connector = "=" };
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual('b', (try fsm.go()).?.opt.short);
                try testing.expectEqual('c', (try fsm.go()).?.opt.short);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm: Short = .{ .s = "abc=hello", .connector = "=" };
                try testing.expectEqual('a', (try fsm.go()).?.opt.short);
                try testing.expectEqual('b', (try fsm.go()).?.opt.short);
                try testing.expectEqual('c', (try fsm.go()).?.opt.short);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Short, empty argument" {
            var fsm: Short = .{ .s = "a=\"\"", .connector = "=" };
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Short, argument with space" {
            var fsm: Short = .{ .s = "a=\" a\"", .connector = "=" };
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectEqualStrings(" a", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Short, MissingOptionArgument" {
            var fsm: Short = .{ .s = "a=", .connector = "=" };
            try testing.expectEqual('a', (try fsm.go()).?.opt.short);
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
        }
        test "FSM, Short, MissingShortOption" {
            {
                var fsm: Short = .{ .s = "=", .connector = "=" };
                try testing.expectError(Error.MissingShortOption, fsm.go());
                try testing.expectError(Error.MissingShortOption, fsm.go());
            }
            {
                var fsm: Short = .{ .s = "", .connector = "=" };
                try testing.expectError(Error.MissingShortOption, fsm.go());
                try testing.expectError(Error.MissingShortOption, fsm.go());
            }
        }
        test "Wrap, FSM, Short" {
            var it: IterWrapper(Short, Error!?Type, "!?") = .{ .it = .{ .s = "ac=hello", .connector = "=" } };
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
        s: ?String,
        connector: String,
        _state: State = .begin,
        const State = union(enum) { begin, end, optArg: String };
        fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin => {
                        if (self.s) |s| {
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
                        } else self._state = .end;
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
        test "FSM, Long, normal" {
            {
                var fsm: Long = .{ .s = "word", .connector = "=" };
                try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
            {
                var fsm: Long = .{ .s = "word=hello", .connector = "=" };
                try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
                try testing.expectEqualStrings("hello", (try fsm.go()).?.optArg);
                try testing.expectEqual(null, try fsm.go());
                try testing.expectEqual(null, try fsm.go());
            }
        }
        test "FSM, Long, empty argument" {
            var fsm: Long = .{ .s = "word=\"\"", .connector = "=" };
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, argument with space" {
            var fsm: Long = .{ .s = "word=\" a\"", .connector = "=" };
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings(" a", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, MissingOptionArgument" {
            var fsm: Long = .{ .s = "word=", .connector = "=" };
            try testing.expectEqualStrings("word", (try fsm.go()).?.opt.long);
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
            try testing.expectError(Error.MissingOptionArgument, fsm.go());
        }
        test "FSM, Long, MissingLongOption" {
            {
                var fsm: Long = .{ .s = "=", .connector = "=" };
                try testing.expectError(Error.MissingLongOption, fsm.go());
                try testing.expectError(Error.MissingLongOption, fsm.go());
            }
            {
                var fsm: Long = .{ .s = "", .connector = "=" };
                try testing.expectError(Error.MissingLongOption, fsm.go());
                try testing.expectError(Error.MissingLongOption, fsm.go());
            }
        }
        test "FSM, Long, mess" {
            var fsm: Long = .{ .s = "\" word\"=\"\"", .connector = "=" };
            try testing.expectEqualStrings(" word", (try fsm.go()).?.opt.long);
            try testing.expectEqualStrings("", (try fsm.go()).?.optArg);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
        test "FSM, Long, short length" {
            var fsm: Long = .{ .s = "a", .connector = "=" };
            try testing.expectEqualStrings("a", (try fsm.go()).?.opt.long);
            try testing.expectEqual(null, try fsm.go());
            try testing.expectEqual(null, try fsm.go());
        }
    };
    const Token = struct {
        const Self = @This();
        it: IterWrapper(BaseIter, ?String, "?s"),
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
                                self._state = .{ .long = .{
                                    .s = item[self.config.prefix_long.len..],
                                    .connector = self.config.connector_optarg,
                                } };
                            } else if (std.mem.startsWith(u8, item, self.config.prefix_short)) {
                                self._state = .{ .short = .{
                                    .s = item[self.config.prefix_short.len..],
                                    .connector = self.config.connector_optarg,
                                } };
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
        fn deinit(self: *Self) void {
            self.it.deinit();
        }
        test "FSM, Token, normal" {
            const it__: BaseIter.List = .{ .list = &[_]String{
                "-a",
                "--word=hello",
                "--verbose",
                "-ht=amd64",
                "arg",
                "--",
                "pos0",
                "pos1",
            } };
            var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
            it_.debug = true;
            var it: Token = .{ .it = it_, .config = .{} };
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
            const it__: BaseIter.List = .{ .list = &[_]String{ "-a", "--word=", "--verbose" } };
            var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
            it_.debug = true;
            var it: Token = .{ .it = it_, .config = .{} };
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
                const it__: BaseIter.List = .{ .list = &[_]String{ "-", "--verbose" } };
                var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
                it_.debug = true;
                var it: Token = .{ .it = it_, .config = .{} };
                defer it.deinit();
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectEqualStrings("-", it.it.view().?);
                try testing.expectEqualStrings("-", it.it.next().?);
                try testing.expectEqualStrings("--verbose", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
            {
                const it__: BaseIter.List = .{ .list = &[_]String{"-="} };
                var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
                it_.debug = true;
                var it: Token = .{ .it = it_, .config = .{} };
                defer it.deinit();
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectError(Error.MissingShortOption, it.go());
                try testing.expectEqualStrings("-=", it.it.next().?);
                try testing.expectEqual(null, it.it.next());
            }
        }
        test "FSM, Token, MissingLongOption" {
            {
                const it__: BaseIter.List = .{ .list = &[_]String{ "-a", "--=", "--verbose" } };
                var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
                it_.debug = true;
                var it: Token = .{ .it = it_, .config = .{} };
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
                const it__: BaseIter.List = .{ .list = &[_]String{
                    "-a",
                    "--",
                } };
                var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
                it_.debug = true;
                var it: Token = .{ .it = it_, .config = .{ .terminator = "**" } };
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
            const it__: BaseIter.List = .{ .list = &[_]String{
                "hell o ",
                " \"world \" ",
            } };
            var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
            it_.debug = true;
            var it: Token = .{ .it = it_, .config = .{} };
            defer it.deinit();
            try testing.expectEqualStrings("hell o", (try it.go()).?.arg);
            try testing.expectEqualStrings("world ", (try it.go()).?.arg);
            try testing.expectEqual(null, try it.go());
            try testing.expectEqual(null, try it.go());
        }
        test "FSM, Token, position with space" {
            const it__: BaseIter.List = .{ .list = &[_]String{
                "-a",
                "--",
                " \"world \" ",
            } };
            var it_: IterWrapper(BaseIter, ?String, "?s") = .{ .it = .{ .list = it__ } };
            it_.debug = true;
            var it: Token = .{ .it = it_, .config = .{} };
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
    config: Config = undefined,
    iter: BaseIter = undefined,
    /// cache short options and maybe an argument that is belong to last option
    cache_shorts: ?String = null,
    /// cache an option argument
    cache_optarg: ?String = null,
    /// mark if the terminator is found
    flag_termiantor: bool = false,
    /// cache for next&view
    cache_token: ?(Error!?Type) = null,

    debug: bool = false,

    const Self = @This();
    pub const Error = FSM.Error;

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .sys = try std.process.argsWithAllocator(allocator) } };
    }
    pub fn initGeneral(allocator: std.mem.Allocator, line: String, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .general = try std.process.ArgIteratorGeneral(.{}).init(allocator, line) } };
    }
    pub fn initLine(line: String, delimiters: ?String, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .line = std.mem.tokenizeAny(u8, line, delimiters orelse " \t\n") } };
    }
    pub fn initList(list: []const String, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .list = .{ .list = list } } };
    }
    pub fn deinit(self: *Self) void {
        self.iter.deinit();
    }
    pub fn reinit(self: *Self, config: Config) *Self {
        self.config = config;
        self.cache_shorts = null;
        self.cache_optarg = null;
        self.flag_termiantor = false;
        self.cache_token = null;
        return self;
    }

    fn log(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.debug) return;
        std.debug.print(fmt, args);
    }

    fn go(self: *Self) Error!?Type {
        const config = self.config;
        if (self.cache_optarg) |optarg| {
            self.cache_optarg = null;
            return .{ .optArg = optarg };
        }
        if (self.cache_shorts) |shorts_| {
            const s = shorts_[0];
            const shorts = shorts_[1..];
            if (shorts.len == 0) {
                self.cache_shorts = null;
            } else if (std.mem.startsWith(u8, shorts, config.connector_optarg)) {
                self.cache_shorts = null;
                const optarg = shorts[config.connector_optarg.len..];
                if (optarg.len == 0) {
                    return Error.MissingOptionArgument;
                }
                self.cache_optarg = optarg;
            } else {
                self.cache_shorts = shorts;
            }
            return .{ .opt = .{ .short = s } };
        }
        const token = self.iter.go() orelse return null;
        if (self.flag_termiantor) {
            return .{ .posArg = token };
        }
        if (std.mem.eql(u8, token, config.terminator)) {
            self.flag_termiantor = true;
            return self.go();
        }
        if (std.mem.startsWith(u8, token, config.prefix_long)) {
            var long = token[config.prefix_long.len..];
            if (long.len == 0) {
                return Error.MissingLongOption;
            }
            if (std.mem.indexOf(u8, long, config.connector_optarg)) |i| {
                const optarg = long[i + config.connector_optarg.len ..];
                if (optarg.len == 0) {
                    return Error.MissingOptionArgument;
                }
                long = long[0..i];
                self.cache_optarg = optarg;
            }
            return .{ .opt = .{ .long = long } };
        }
        if (std.mem.startsWith(u8, token, config.prefix_short)) {
            self.cache_shorts = token[config.prefix_short.len..];
            if (self.cache_shorts.?.len == 0) {
                return Error.MissingShortOption;
            }
            return self.go();
        }
        return .{ .arg = token };
    }

    test "go, missing long option" {
        var it = try Self.initGeneral(testing.allocator, "--", .{ .terminator = "xx" });
        defer it.deinit();
        try testing.expectError(Error.MissingLongOption, it.go());
    }

    test "go, missing short option" {
        var it = try Self.initGeneral(testing.allocator, "-", .{});
        defer it.deinit();
        try testing.expectError(Error.MissingShortOption, it.go());
    }

    test "go, missing option argument" {
        var shortIt = try Self.initGeneral(testing.allocator, "-a=", .{});
        defer shortIt.deinit();
        try testing.expectError(Error.MissingOptionArgument, shortIt.go());
        var longIt = try Self.initGeneral(testing.allocator, "--a=", .{});
        defer longIt.deinit();
        try testing.expectError(Error.MissingOptionArgument, longIt.go());
    }

    test "go, long option" {
        var it = try Self.initGeneral(testing.allocator, "--verbose", .{});
        defer it.deinit();
        try testing.expectEqualSlices(u8, "verbose", (try it.go()).?.opt.long);
        try testing.expectEqual(null, try it.go());
    }

    test "go, long option with arg" {
        var it = try Self.initGeneral(testing.allocator, "--verbose=hello", .{});
        defer it.deinit();
        try testing.expectEqualSlices(u8, "verbose", (try it.go()).?.opt.long);
        try testing.expectEqualSlices(u8, "hello", (try it.go()).?.optArg);
        try testing.expectEqual(null, try it.go());
    }

    test "go, short option" {
        var it = try Self.initGeneral(testing.allocator, "-v", .{});
        defer it.deinit();
        try testing.expectEqual('v', (try it.go()).?.opt.short);
        try testing.expectEqual(null, try it.go());
    }

    test "go, short options" {
        var it = try Self.initGeneral(testing.allocator, "-abc", .{});
        defer it.deinit();
        try testing.expectEqual('a', (try it.go()).?.opt.short);
        try testing.expectEqual('b', (try it.go()).?.opt.short);
        try testing.expectEqual('c', (try it.go()).?.opt.short);
        try testing.expectEqual(null, try it.go());
    }

    test "go, short option with arg" {
        var it = try Self.initGeneral(testing.allocator, "-v=hello", .{});
        defer it.deinit();
        try testing.expectEqual('v', (try it.go()).?.opt.short);
        try testing.expectEqualSlices(u8, "hello", (try it.go()).?.optArg);
        try testing.expectEqual(null, try it.go());
    }

    test "go, short options with arg" {
        var it = try Self.initGeneral(testing.allocator, "-abc=hello", .{});
        defer it.deinit();
        try testing.expectEqual('a', (try it.go()).?.opt.short);
        try testing.expectEqual('b', (try it.go()).?.opt.short);
        try testing.expectEqual('c', (try it.go()).?.opt.short);
        try testing.expectEqualSlices(u8, "hello", (try it.go()).?.optArg);
        try testing.expectEqual(null, try it.go());
    }

    test "go, general argument" {
        var it = try Self.initGeneral(testing.allocator, "pos0", .{});
        defer it.deinit();
        try testing.expectEqualSlices(u8, "pos0", (try it.go()).?.arg);
        try testing.expectEqual(null, try it.go());
    }

    test "go, positional arguments" {
        var it = try Self.initGeneral(testing.allocator, "-- pos0 -a -- --verbose", .{});
        defer it.deinit();
        try testing.expectEqualSlices(u8, "pos0", (try it.go()).?.posArg);
        try testing.expectEqualSlices(u8, "-a", (try it.go()).?.posArg);
        try testing.expectEqualSlices(u8, "--", (try it.go()).?.posArg);
        try testing.expectEqualSlices(u8, "--verbose", (try it.go()).?.posArg);
        try testing.expectEqual(null, try it.go());
    }

    pub fn next(self: *Self) Error!?Type {
        var s: []const u8 = "";
        const token = if (self.cache_token) |t| blk: {
            self.cache_token = null;
            s = "(Cached)";
            break :blk t;
        } else self.go();
        self.log("\x1b[95mnext\x1b[90m{s}\x1b[0m {any}\n", .{ s, token });
        return token;
    }

    pub fn nextMust(self: *Self) Error!Type {
        return (try self.next()) orelse Error.NoMore;
    }

    test "nextMust, no more" {
        var it = try Self.initLine("", null, .{});
        defer it.deinit();
        try testing.expectError(error.NoMore, it.nextMust());
    }

    pub fn view(self: *Self) Error!?Type {
        var s: []const u8 = "(Cached)";
        const token = if (self.cache_token == null) blk: {
            self.cache_token = self.go();
            s = "";
            break :blk self.cache_token.?;
        } else self.cache_token.?;
        self.log("\x1b[92mview\x1b[90m{s}\x1b[0m {!?}\n", .{ s, token });
        return token;
    }

    pub fn viewMust(self: *Self) Error!Type {
        return (try self.view()) orelse Error.NoMore;
    }

    test "Cache Token, view and next" {
        var it = try Self.initGeneral(testing.allocator, "-- pos0 -a -- --verbose", .{});
        defer it.deinit();
        it.debug = true;
        try testing.expectEqualSlices(u8, "pos0", (try it.view()).?.posArg);
        try testing.expectEqualSlices(u8, "pos0", (try it.next()).?.posArg);
        try testing.expectEqualSlices(u8, "-a", (try it.next()).?.posArg);
        try testing.expectEqualSlices(u8, "--", (try it.view()).?.posArg);
        try testing.expectEqualSlices(u8, "--", (try it.next()).?.posArg);
        try testing.expectEqualSlices(u8, "--verbose", (try it.next()).?.posArg);
        try testing.expectEqual(null, try it.next());
        try testing.expectEqual(null, try it.view());
        try testing.expectEqual(null, try it.view());
        try testing.expectEqual(null, try it.next());
        try testing.expectError(error.NoMore, it.viewMust());
    }

    test "Cache Token, missing option argument" {
        var shortIt = try Self.initGeneral(testing.allocator, "-a=", .{});
        defer shortIt.deinit();
        shortIt.debug = true;
        try testing.expectError(Error.MissingOptionArgument, shortIt.view());
        try testing.expectError(Error.MissingOptionArgument, shortIt.next());
    }

    pub fn nextAll(self: *Self, allocator: std.mem.Allocator) ![]const Type {
        var tokens = std.ArrayList(Type).init(allocator);
        defer tokens.deinit();
        while (try self.next()) |token| {
            try tokens.append(token);
        }
        return try tokens.toOwnedSlice();
    }

    test "nextAll" {
        var it = try Self.initList(&[_]String{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
        defer it.deinit();
        const tokens = try it.nextAll(testing.allocator);
        defer testing.allocator.free(tokens);
        try testing.expectEqual(4, tokens.len);
        try testing.expectEqualSlices(u8, "verbose", tokens[0].opt.long);
        try testing.expectEqual('a', tokens[1].opt.short);
        try testing.expectEqualSlices(u8, "po s0", tokens[2].arg);
        try testing.expectEqualSlices(u8, "--verbose", tokens[3].posArg);
    }

    pub fn nextAllComptime(self: *Self) []const Type {
        switch (self.iter) {
            .sys, .general => @compileError("comptimeNextAll is not supported for sys or general iterator"),
            else => {},
        }
        var tokens: []const Type = &.{};
        inline while (try self.next()) |token| {
            tokens = tokens ++ [_]Type{token};
        }
        return tokens;
    }

    test "nextAllComptime" {
        comptime var it = try Self.initList(&[_]String{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
        const tokens = comptime it.nextAllComptime();
        try testing.expectEqual(4, tokens.len);
        try testing.expectEqualSlices(u8, "verbose", tokens[0].opt.long);
        try testing.expectEqual('a', tokens[1].opt.short);
        try testing.expectEqualSlices(u8, "po s0", tokens[2].arg);
        try testing.expectEqualSlices(u8, "--verbose", tokens[3].posArg);
    }

    pub fn nextAllBase(self: *Self, allocator: std.mem.Allocator) ![]const String {
        var tokens = std.ArrayList(String).init(allocator);
        defer tokens.deinit();
        while (self.iter.go()) |token| {
            try tokens.append(token);
        }
        return try tokens.toOwnedSlice();
    }

    test "nextAllBase" {
        var it = try Self.initList(&[_]String{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
        defer it.deinit();
        const tokens = try it.nextAllBase(testing.allocator);
        defer testing.allocator.free(tokens);
        try testing.expectEqualSlices(
            String,
            &[_]String{ "--verbose", "-a", "po s0", "--", "--verbose" },
            tokens,
        );
    }
};

test {
    _ = Iter;
    _ = Config;
    _ = FSM;
}
