const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;

const ztype = @import("ztype");
const String = ztype.String;

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

    const _test = struct {
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
};

pub const Format = struct {
    const Self = @This();
    indent: usize = 2,
    left_max: usize = 24,
};

pub const Style = struct {
    const Self = @This();
};

test {
    _ = Prefix;
    _ = Token;
    _ = Format;
    _ = Style;
}

token: Token = .{},
format: Format = .{},
style: Style = .{},
