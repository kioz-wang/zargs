const std = @import("std");
const testing = std.testing;

const Meta = @import("meta.zig").Meta;
const Command = @import("Command.zig");
const attr = @import("attr");
const helper = @import("helper.zig");
const Alias = helper.Alias;
const String = Alias.String;
const Prefix = helper.Config.Prefix;

pub const MetaFormatter = struct {
    m: Meta,
    prefix: Prefix,
    sep: ?String = null,
    const Self = @This();
    const comptimePrint = std.fmt.comptimePrint;
    const bufPrint = std.fmt.bufPrint;

    pub fn new(m: Meta, prefix: Prefix, sep: ?String) Self {
        return .{ .m = m, .prefix = prefix, .sep = sep };
    }
    pub fn formatShortLong(self: Self, w: anytype) !usize {
        var n: usize = 0;
        for (self.m.common.short) |short| {
            n += try w.write(self.prefix.short);
            n += try w.write(&.{short});
            break;
        }
        for (self.m.common.long) |long| {
            if (n != 0) n += try w.write(self.sep.?);
            n += try w.write(self.prefix.long);
            n += try w.write(long);
            break;
        }
        return n;
    }
    pub fn formatUsage(self: Self, w: anytype) !usize {
        var n: usize = 0;
        n += try self.formatShortLong(w);
        if (self.m.common.argName) |s| {
            if (n != 0) n += try w.write(" ");
            n += try w.write(comptimePrint("{{{s}}}", .{s}));
        }
        return n;
    }
    pub fn formatAlignSpace(self: Self, w: anytype, is_first: bool) !usize {
        const usage_length = try self.formatUsage(&std.io.null_writer);
        const align_n: usize = @max(24, helper.alignIntUp(usize, usage_length, 4) + 4);
        const n: usize = if (is_first) align_n - usage_length else align_n;
        try w.writer().writeByteNTimes(' ', n);
        return n;
    }
    pub fn formatAlias(self: Self, w: anytype) !usize {
        var n: usize = 0;
        const shorts = if (self.m.common.short.len > 1) self.m.common.short[1..] else &.{};
        const longs = if (self.m.common.long.len > 1) self.m.common.long[1..] else &.{};
        if (shorts.len == 0 and longs.len == 0) return n;
        var is_first = true;
        n += try w.write("(alias ");
        for (shorts) |short| {
            if (is_first) is_first = false else n += try w.write(", ");
            n += try w.write(self.prefix.short);
            n += try w.write(&.{short});
        }
        for (longs) |long| {
            if (is_first) is_first = false else n += try w.write(", ");
            n += try w.write(self.prefix.long);
            n += try w.write(long);
        }
        n += try w.write(")");
        return n;
    }

    const _test = struct {
        test "format short/long" {
            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.opt("help", bool).short('h').long("help")._checkOut(), .{}, ", ").formatShortLong(&fbs);
                try testing.expectEqualStrings("-h, --help", buffer[0..n]);
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.opt("help", bool).short('h').long("help").long("hel").short('e')._checkOut(), .{}, "|").formatShortLong(&fbs);
                try testing.expectEqualStrings("-h|--help", buffer[0..n]);
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.opt("help", bool).short('h').short('e')._checkOut(), .{ .short = "@" }, "").formatShortLong(&fbs);
                try testing.expectEqualStrings("@h", buffer[0..n]);
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.optArg("help", bool).long("help").long("hel")._checkOut(), .{}, "").formatShortLong(&fbs);
                try testing.expectEqualStrings("--help", buffer[0..n]);
            }
            {
                defer fbs.reset();
                try testing.expectEqual(0, MetaFormatter.new(Meta.posArg("help", bool)._checkOut(), .{}, "").formatShortLong(&fbs));
            }
        }
        test "format usage" {
            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.opt("help", bool).short('h').long("help")._checkOut(), .{}, ", ").formatUsage(&fbs);
                try testing.expectEqualStrings("-h, --help", buffer[0..n]);
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.optArg("help", bool).short('h').long("help")._checkOut(), .{}, "|").formatUsage(&fbs);
                try testing.expectEqualStrings("-h|--help {HELP}", buffer[0..n]);
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.posArg("help", bool)._checkOut(), .{}, null).formatUsage(&fbs);
                try testing.expectEqualStrings("{HELP}", buffer[0..n]);
            }
        }
        test "format aligned space" {
            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            {
                defer fbs.reset();
                const f = MetaFormatter.new(Meta.opt("help", bool).short('h').long("help")._checkOut(), .{}, ", ");
                try testing.expectEqual(14, try f.formatAlignSpace(&fbs, true));
                try testing.expectEqual(24, try f.formatAlignSpace(&fbs, false));
            }
        }
        test "format alias" {
            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            {
                defer fbs.reset();
                try testing.expectEqual(0, try MetaFormatter.new(Meta.opt("help", bool).short('h').long("help")._checkOut(), .{}, null).formatAlias(&fbs));
            }
            {
                defer fbs.reset();
                const n = try MetaFormatter.new(Meta.opt("help", bool).short('h').long("help").long("hel").short('e')._checkOut(), .{}, null).formatAlias(&fbs);
                try testing.expectEqualStrings("(alias -e, --hel)", buffer[0..n]);
            }
        }
    };
};

test {
    _ = MetaFormatter._test;
}
