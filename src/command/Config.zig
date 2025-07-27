const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;

const ztype = @import("ztype");
const String = ztype.String;

const BufferedList = @import("helper").Collection.BufferedList;

const Attr = @import("attr").Attribute;

pub const Prefix = struct {
    const Self = @This();
    pub const Error = error{
        PrefixLongEmpty,
        PrefixShortEmpty,
        PrefixLongShortEqual,
        PrefixLongHasSpace,
        PrefixShortHasSpace,
    };

    /// During matching, the `prefix_long` takes precedence over `prefix_short`.
    short: String = "-",
    /// During matching, the `prefix_long` takes precedence over `prefix_short`.
    long: String = "--",
    pub fn format(self: @This(), comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll("{ .short = ");
        try std.fmt.formatBuf(self.short, options, writer);
        try writer.writeAll(", .long = ");
        try std.fmt.formatBuf(self.long, options, writer);
        try writer.writeAll(" }");
    }
    pub fn validate(self: *const Self) Error!void {
        if (self.long.len == 0) {
            return Error.PrefixLongEmpty;
        }
        if (self.short.len == 0) {
            return Error.PrefixShortEmpty;
        }
        if (std.mem.eql(u8, self.long, self.short)) {
            return Error.PrefixLongShortEqual;
        }
        if (std.mem.indexOfAny(u8, self.long, " ")) |_| {
            return Error.PrefixLongHasSpace;
        }
        if (std.mem.indexOfAny(u8, self.short, " ")) |_| {
            return Error.PrefixShortHasSpace;
        }
    }
};

/// Used for parsing the original string.
pub const Token = struct {
    const Self = @This();
    pub const Error = error{
        ConnectorOptArgEmpty,
        TerminatorEmpty,
        ConnectorOptArgHasSpace,
        TerminatorHasSpace,
    } || Prefix.Error;

    prefix: Prefix = .{},
    /// During matching, the `terminator` takes precedence over `prefix_long`.
    terminator: String = "--",
    /// Used as a connector between `singleArgOpt` and its argument.
    connector: String = "=",

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll("{ .prefix = ");
        try self.prefix.format(fmt, options, writer);
        try writer.writeAll(", .terminator = ");
        try std.fmt.formatBuf(self.terminator, options, writer);
        try writer.writeAll(", .connector = ");
        try std.fmt.formatBuf(self.connector, options, writer);
        try writer.writeAll(" }");
    }
    pub fn validate(self: *const Self) Error!void {
        try self.prefix.validate();
        if (self.connector.len == 0) {
            return Error.ConnectorOptArgEmpty;
        }
        if (self.terminator.len == 0) {
            return Error.TerminatorEmpty;
        }
        if (std.mem.indexOfAny(u8, self.connector, " ")) |_| {
            return Error.ConnectorOptArgHasSpace;
        }
        if (std.mem.indexOfAny(u8, self.terminator, " ")) |_| {
            return Error.TerminatorHasSpace;
        }
    }

    test "Validate Config" {
        try testing.expectError(Error.PrefixLongEmpty, (Self{ .prefix = .{ .long = "" } }).validate());
        try testing.expectError(Error.PrefixShortEmpty, (Self{ .prefix = .{ .short = "" } }).validate());
        try testing.expectError(Error.ConnectorOptArgEmpty, (Self{ .connector = "" }).validate());
        try testing.expectError(Error.TerminatorEmpty, (Self{ .terminator = "" }).validate());
        try testing.expectError(Error.PrefixLongShortEqual, (Self{ .prefix = .{ .long = "-", .short = "-" } }).validate());
        try testing.expectError(Error.PrefixLongHasSpace, (Self{ .prefix = .{ .long = "a b" } }).validate());
        try testing.expectError(Error.PrefixShortHasSpace, (Self{ .prefix = .{ .short = "a b" } }).validate());
        try testing.expectError(Error.ConnectorOptArgHasSpace, (Self{ .connector = "a b" }).validate());
        try testing.expectError(Error.TerminatorHasSpace, (Self{ .terminator = "a b" }).validate());
    }
    test "Format Config" {
        try testing.expectEqualStrings(
            "{ .prefix = { .short = -, .long = -- }, .terminator = --, .connector = = }",
            comptimePrint("{}", .{Self{}}),
        );
    }
};

pub const Format = struct {
    indent: usize = 2,
    left_max: usize = 24,
};

pub const Style = struct {
    usage: struct {
        optarg: Attr = .none,
        optional: Attr = .none,
        argument: Attr = .none,
        alias: Attr = .none,
    } = .{},
    help: struct {
        default: Attr = .none,
        defaultValue: Attr = .none,
        possible: Attr = .none,
        possibleValue: Attr = .none,
        possibleInput: Attr = .none,
        enum_: Attr = .none,
        enumValue: Attr = .none,
    } = .{},
    homepage: Attr = .none,
    title: Attr = .none,

    pub const none = Style{};
    pub const classic = Style{
        .usage = .{
            .optarg = Attr.none.underscore(),
            .optional = Attr.none.half_bright(),
            .argument = Attr.none.italic(),
            .alias = Attr.none.half_bright(),
        },
        .help = .{
            .default = Attr.none.green().italic().half_bright(),
            .defaultValue = Attr.none.off_italic().normal_intensity(),
            .possible = Attr.none.cyan().italic().half_bright(),
            .possibleValue = Attr.none.off_italic().normal_intensity(),
            .possibleInput = Attr.none.off_italic().normal_intensity(),
            .enum_ = Attr.none.red().italic().half_bright(),
            .enumValue = Attr.none.off_italic().normal_intensity(),
        },
        .homepage = Attr.none.underscore().italic().blue(),
        .title = Attr.none.colorRGB(0xee, 0xee, 0),
    };
};

pub fn StyleRecord(capacity: comptime_int) type {
    return struct {
        const Self = @This();
        const Queue = BufferedList(capacity, union(enum) {
            _apply: Attr,
            _restore: Attr,
            _reset,
        });
        clean: bool = true,
        queue: Queue = .{},
        inited: bool = false,
        fn format_apply(self: *Self, w: anytype, a: Attr) @TypeOf(w).Error!void {
            if (!std.meta.eql(a, Attr.none)) {
                if (self.clean) {
                    try Attr.reset.stringify(w);
                }
                self.clean = false;
                try a.stringify(w);
            }
        }
        fn format_reset(self: *Self, w: anytype) @TypeOf(w).Error!void {
            if (!self.clean) {
                try Attr.reset.stringify(w);
                self.clean = true;
            }
        }
        pub fn format(self: *Self, comptime _: []const u8, _: anytype, w: anytype) @TypeOf(w).Error!void {
            switch (self.queue.dequeue().?) {
                ._apply => |a| try self.format_apply(w, a),
                ._reset => try self.format_reset(w),
                ._restore => |a| {
                    try self.format_reset(w);
                    try self.format_apply(w, a);
                },
            }
        }
        fn init(self: *Self) void {
            if (!self.inited) {
                self.inited = true;
                self.queue.init();
            }
        }
        pub fn apply(self: *Self, a: Attr) *Self {
            self.init();
            _ = self.queue.enqueue(.{ ._apply = a });
            return self;
        }
        pub fn restore(self: *Self, a: Attr) *Self {
            self.init();
            _ = self.queue.enqueue(.{ ._restore = a });
            return self;
        }
        pub fn reset(self: *Self) *Self {
            self.init();
            _ = self.queue.enqueue(._reset);
            return self;
        }
    };
}

test StyleRecord {
    var rec = StyleRecord(4){};
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings(
        "\x1b[0m\x1b[32ma \x1b[4;31mb \x1b[0m\x1b[0m\x1b[3;32ma \x1b[0m hello",
        try std.fmt.bufPrint(&buffer, "{}a {}b {}a {s} hello", .{
            rec.apply(Attr.none.green()),
            rec.apply(Attr.none.underscore().red()),
            rec.restore(Attr.none.green().italic()),
            rec.reset(),
        }),
    );
}

test {
    _ = Prefix;
    _ = Token;
    _ = Format;
    _ = Style;
}

token: Token = .{},
format: Format = .{},
style: Style = .none,

pub fn destruct(self: @This()) struct { Token, Format, Style } {
    return .{ self.token, self.format, self.style };
}
