const std = @import("std");
const testing = std.testing;

pub const String = []const u8;

pub const print = std.fmt.comptimePrint;

pub fn StringSet(capacity: comptime_int) type {
    const A = std.ArrayListUnmanaged(String);
    return struct {
        base: A = undefined,
        buffer: [capacity]String = undefined,
        pub fn init(self: *@This()) void {
            self.base = A.initBuffer(self.buffer[0..]);
        }
        pub fn contain(self: *const @This(), s: String) bool {
            return for (self.base.items) |item| {
                if (std.mem.eql(u8, item, s)) break true;
            } else false;
        }
        pub fn add(self: *@This(), s: String) bool {
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

pub fn upper(comptime str: []const u8) [str.len]u8 {
    var s = std.mem.zeroes([str.len]u8);
    _ = std.ascii.upperString(s[0..], str);
    return s;
}

test upper {
    try testing.expectEqualStrings("UPPER", &upper("upPer"));
}

pub const FormatOptions = std.fmt.FormatOptions;
