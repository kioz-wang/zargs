const std = @import("std");
const testing = std.testing;
const iter = @import("iter.zig");
const String = @import("helper.zig").Alias.String;
const Config = @import("helper.zig").Config;

/// The original iterator that iterates over the raw string.
const BaseIter = union(enum) {
    const Self = @This();
    /// System iterator, get real command line arguments.
    sys: std.process.ArgIterator,
    /// General iterator, splits command line arguments from a one-line string.
    general: std.process.ArgIteratorGeneral(.{}),
    /// Line iterator, same as regular iterator, but you can specify delimiters.
    line: std.mem.TokenIterator(u8, .any),
    /// List iterator, iterates over a list of strings.
    list: iter.ListIter(String),

    pub fn go(self: *Self) ?String {
        return switch (self.*) {
            .sys => |*i| i.next(),
            .general => |*i| i.next(),
            .line => |*i| i.next(),
            .list => |*i| i.go(),
        };
    }
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .sys => |*i| i.deinit(),
            .general => |*i| i.deinit(),
            else => {},
        }
    }
};

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
    /// Option argument that follows the connector
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

/// First, trim whitespace characters, then trim double quotes (if they exist).
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

/// Iterators based on a Finite State Machine (FSM).
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
        pub fn go(self: *Self) Error!?Type {
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
        const _test = struct {
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
                var it = iter.Wrapper(Short, Error!?Type, "!?").init(Short.init("ac=hello", "="));
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
    };
    const Long = struct {
        const Self = @This();
        connector: String,
        _state: State,
        const State = union(enum) { begin: String, end, optArg: String };
        pub fn go(self: *Self) Error!?Type {
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
        const _test = struct {
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
    };
    /// Iterate over the original iterator and parse.
    const Token = struct {
        const Self = @This();
        const It = iter.Wrapper(BaseIter, ?String, "?s");
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
        pub fn go(self: *Self) Error!?Type {
            while (true) {
                switch (self._state) {
                    .begin, .next => {
                        if (self._state == .next) {
                            _ = self.it.next() orelse unreachable;
                        }
                        if (self.it.view()) |item| {
                            if (std.mem.eql(u8, item, self.config.terminator)) {
                                self._state = .pos;
                            } else if (std.mem.startsWith(u8, item, self.config.prefix.long)) {
                                self._state = .{ .long = Long.init(
                                    item[self.config.prefix.long.len..],
                                    self.config.connector,
                                ) };
                            } else if (std.mem.startsWith(u8, item, self.config.prefix.short)) {
                                self._state = .{ .short = Short.init(
                                    item[self.config.prefix.short.len..],
                                    self.config.connector,
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
        const _test = struct {
            test "FSM, Token, normal" {
                const it_: BaseIter = .{ .list = .{ .list = &.{
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
                const it_: BaseIter = .{ .list = .{ .list = &.{
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
                    const it_: BaseIter = .{ .list = .{ .list = &.{ "-", "--verbose" } } };
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
                    const it_: BaseIter = .{ .list = .{ .list = &.{"-="} } };
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
                    const it_: BaseIter = .{ .list = .{ .list = &.{ "-a", "--=", "--verbose" } } };
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
                    const it_: BaseIter = .{ .list = .{ .list = &.{ "-a", "--" } } };
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
                const it_: BaseIter = .{ .list = .{ .list = &.{
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
                const it_: BaseIter = .{ .list = .{ .list = &.{
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
    };
    test {
        _ = Short._test;
        _ = Long._test;
        _ = Token._test;
    }
};

pub const Iter = struct {
    const Self = @This();
    pub const Error = FSM.Error;
    const It = iter.Wrapper(FSM.Token, Error!?Type, "!?");

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
    /// Complete the remaining iteration on the original iterator, then terminate the internal FSM.
    pub fn nextAllBase(self: *Self, allocator: std.mem.Allocator) ![]const String {
        const items = try self.it.it.it.nextAll(allocator);
        self.it.it._state = .end;
        return items;
    }
    /// Update the internal FSM so that only `posArg`s are returned afterward.
    pub fn fsm_to_pos(self: *Self) void {
        self.it.it._state = .pos;
    }
    /// Reset the state of the internal FSM. Only used for subcommand parsing.
    pub fn reinit(self: *Self, config: ?Config) void {
        self.it.it._state = .begin;
        self.it.cache = null;
        self.it.it.it.cache = null;
        if (config) |c| {
            self.it.it.config = c;
        }
    }
    pub fn debug(self: *Self, b: bool) void {
        self.it.debug = b;
    }
};

test {
    _ = Iter;
    _ = FSM;
}
