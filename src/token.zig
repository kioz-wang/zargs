const std = @import("std");
const testing = std.testing;

pub const Type = union(enum) {
    const FormatOptions = std.fmt.FormatOptions;
    pub const Opt = union(enum) {
        /// Short option that follows the prefix_short
        short: u8,
        /// Long option that follows the prefix_long
        long: []const u8,
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
    /// Option argument that follows the connector_optarg
    pub const OptArg = struct {
        arg: []const u8,
        opt: Opt,
    };
    opt: Opt,
    optArg: OptArg,
    /// Positional argument that meets after the terminator
    posArg: []const u8,
    /// Positional argument, and maybe Option argument
    arg: []const u8,

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
        try writer.writeAll("{ ");
        switch (self) {
            .opt => |o| {
                try o.format(fmt, options, writer);
            },
            .optArg => |o| {
                try std.fmt.formatBuf(o.arg, options, writer);
                try writer.writeAll(", ");
                try o.opt.format(fmt, options, writer);
            },
            .posArg, .arg => |a| {
                try std.fmt.formatBuf(a, options, writer);
            },
        }
        try writer.writeAll(" }");
    }
};

const BaseIter = union(enum) {
    Sys: std.process.ArgIterator,
    General: std.process.ArgIteratorGeneral(.{}),
    Line: std.mem.TokenIterator(u8, .any),
    List: List,

    const Self = @This();

    const List = struct {
        list: []const []const u8,
        fn next(self: *List) ?[]const u8 {
            if (self.list.len == 0) {
                return null;
            }
            const token = self.list[0];
            self.list = self.list[1..];
            return token;
        }
    };
    fn next(self: *Self) ?[]const u8 {
        return switch (self.*) {
            .Sys => |*i| i.next(),
            .General => |*i| i.next(),
            .Line => |*i| i.next(),
            .List => |*i| i.next(),
        };
    }
};

pub const Config = struct {
    prefix_long: []const u8 = "--",
    prefix_short: []const u8 = "-",
    connector_optarg: []const u8 = "=",
    terminator: []const u8 = "--",

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

pub const Iter = struct {
    config: Config = undefined,
    iter: BaseIter = undefined,
    /// cache short options and maybe an argument that is belong to last option
    cache_shorts: ?[]const u8 = null,
    /// cache an option argument
    cache_optarg: ?Type.OptArg = null,
    /// mark if the terminator is found
    flag_termiantor: bool = false,
    /// cache for next&view
    cache_token: ?(Error!?Type) = null,

    debug: bool = false,

    const Self = @This();
    pub const Error = error{
        MissingOptionArgument,
        MissingLongOption,
        MissingShortOption,
        NoMore,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .Sys = try std.process.argsWithAllocator(allocator) } };
    }
    pub fn initGeneral(allocator: std.mem.Allocator, line: []const u8, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .General = try std.process.ArgIteratorGeneral(.{}).init(allocator, line) } };
    }
    pub fn initLine(line: []const u8, delimiters: ?[]const u8, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .Line = std.mem.tokenizeAny(u8, line, delimiters orelse " \t\n") } };
    }
    pub fn initList(list: []const []const u8, config: Config) !Self {
        try config.validate();
        return .{ .config = config, .iter = .{ .List = .{ .list = list } } };
    }
    pub fn deinit(self: *Self) void {
        switch (self.iter) {
            .Sys => |*i| i.deinit(),
            .General => |*i| i.deinit(),
            else => {},
        }
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
                self.cache_optarg = .{ .arg = optarg, .opt = .{ .short = s } };
            } else {
                self.cache_shorts = shorts;
            }
            return .{ .opt = .{ .short = s } };
        }
        const token = self.iter.next() orelse return null;
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
                self.cache_optarg = .{ .arg = optarg, .opt = .{ .long = long } };
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
        const optarg = (try it.go()).?.optArg;
        try testing.expectEqualSlices(u8, "verbose", optarg.opt.long);
        try testing.expectEqualSlices(u8, "hello", optarg.arg);
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
        try testing.expectEqualSlices(u8, "hello", (try it.go()).?.optArg.arg);
        try testing.expectEqual(null, try it.go());
    }

    test "go, short options with arg" {
        var it = try Self.initGeneral(testing.allocator, "-abc=hello", .{});
        defer it.deinit();
        try testing.expectEqual('a', (try it.go()).?.opt.short);
        try testing.expectEqual('b', (try it.go()).?.opt.short);
        try testing.expectEqual('c', (try it.go()).?.opt.short);
        try testing.expectEqualSlices(u8, "hello", (try it.go()).?.optArg.arg);
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
        var it = try Self.initList(&[_][]const u8{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
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
            .Sys, .General => @compileError("comptimeNextAll is not supported for Sys or General iterator"),
            else => {},
        }
        var tokens: []const Type = &.{};
        inline while (try self.next()) |token| {
            tokens = tokens ++ [_]Type{token};
        }
        return tokens;
    }

    test "nextAllComptime" {
        comptime var it = try Self.initList(&[_][]const u8{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
        const tokens = comptime it.nextAllComptime();
        try testing.expectEqual(4, tokens.len);
        try testing.expectEqualSlices(u8, "verbose", tokens[0].opt.long);
        try testing.expectEqual('a', tokens[1].opt.short);
        try testing.expectEqualSlices(u8, "po s0", tokens[2].arg);
        try testing.expectEqualSlices(u8, "--verbose", tokens[3].posArg);
    }

    pub fn nextAllBase(self: *Self, allocator: std.mem.Allocator) ![]const []const u8 {
        var tokens = std.ArrayList([]const u8).init(allocator);
        defer tokens.deinit();
        while (self.iter.next()) |token| {
            try tokens.append(token);
        }
        return try tokens.toOwnedSlice();
    }

    test "nextAllBase" {
        var it = try Self.initList(&[_][]const u8{ "--verbose", "-a", "po s0", "--", "--verbose" }, .{});
        defer it.deinit();
        const tokens = try it.nextAllBase(testing.allocator);
        defer testing.allocator.free(tokens);
        try testing.expectEqualSlices(
            []const u8,
            &[_][]const u8{ "--verbose", "-a", "po s0", "--", "--verbose" },
            tokens,
        );
    }
};

test {
    _ = Iter;
    _ = Config;
}
