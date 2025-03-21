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

pub fn alignIntUp(I: type, i: I, a: I) I {
    return @divTrunc(i, a) * a + if (@rem(i, a) == 0) 0 else a;
}

test alignIntUp {
    try testing.expectEqual(0x100, alignIntUp(u32, 0x9, 0x100));
    try testing.expectEqual(0x100, alignIntUp(u32, 0x100, 0x100));
    try testing.expectEqual(0x1300, alignIntUp(u32, 0x1234, 0x100));
    try testing.expectEqual(20, alignIntUp(u8, 11, 10));
    try testing.expectEqual(20, alignIntUp(u8, 15, 10));
    try testing.expectEqual(21, alignIntUp(u8, 16, 7));
    try testing.expectEqual(21, alignIntUp(u8, 21, 7));
}

pub const FormatOptions = std.fmt.FormatOptions;

pub const Usage = struct {
    pub fn opt(short: ?u8, long: ?[]const u8) []const u8 {
        var usage: []const u8 = "";
        if (short) |s| {
            usage = print("-{c}", .{s});
        }
        if (short != null and long != null) {
            usage = print("{s}|", .{usage});
        }
        if (long) |l| {
            usage = print("{s}--{s}", .{ usage, l });
        }
        return usage;
    }
    pub fn arg(name: []const u8, T: type) []const u8 {
        const pre = switch (@typeInfo(T)) {
            .array => |info| print("[{d}]", .{info.len}),
            .pointer => if (T == String) "" else "[]",
            else => "",
        };
        return print("{{{s}{s}}}", .{ pre, name });
    }
    pub fn optional(has_default: bool, u: []const u8) []const u8 {
        return if (has_default) print("[{s}]", .{u}) else u;
    }
    test opt {
        try testing.expectEqualStrings("-o", comptime opt('o', null));
        try testing.expectEqualStrings("--out", comptime opt(null, "out"));
        try testing.expectEqualStrings("-o|--out", comptime opt('o', "out"));
    }
    test arg {
        try testing.expectEqualStrings("{OUT}", comptime arg("OUT", u32));
        try testing.expectEqualStrings("{[2]OUT}", comptime arg("OUT", [2]u32));
        try testing.expectEqualStrings("{[]OUT}", comptime arg("OUT", []const u32));
    }
    test optional {
        try testing.expectEqualStrings("usage", comptime optional(false, "usage"));
        try testing.expectEqualStrings("[usage]", comptime optional(true, "usage"));
    }
};

pub fn TryBase(T: type) type {
    if (T == String) return T;
    return switch (@typeInfo(T)) {
        .int, .float, .bool, .@"enum", .@"struct" => T,
        else => @compileError(print("illegal base type {s}, expect .int, .float, .bool, .@\"enum\", .@\"struct\" or []cosnt u8", .{@typeName(T)})),
    };
}
pub fn isArray(T: type) bool {
    return @typeInfo(T) == .array;
}
pub fn TryArray(T: type) type {
    return if (isArray(T)) @typeInfo(T).array.child else T;
}
pub fn isSlice(T: type) bool {
    return @typeInfo(T) == .pointer and T != String;
}
pub fn TrySlice(T: type) type {
    return if (isSlice(T)) @typeInfo(T).pointer.child else T;
}
pub fn isMultiple(T: type) bool {
    return isArray(T) or isSlice(T);
}
pub fn TryMultiple(T: type) type {
    return if (isMultiple(T))
        if (isArray(T)) TryArray(T) else TrySlice(T)
    else
        T;
}
pub fn isOptional(T: type) bool {
    return @typeInfo(T) == .optional;
}
pub fn TryOptional(T: type) type {
    return if (isOptional(T)) @typeInfo(T).optional.child else T;
}
pub fn Base(T: type) type {
    return TryBase(
        if (isMultiple(T)) TryMultiple(T) else if (isOptional(T)) TryOptional(T) else T,
    );
}

test Base {
    try testing.expect(u32 == Base(?u32));
    try testing.expect(u32 == Base([]u32));
    try testing.expect(u32 == Base([4]u32));
    try testing.expect(String == Base(?String));
    {
        const T = struct { a: i32 };
        try testing.expect(T == Base(?T));
    }
    {
        const T = enum { Red, Blue };
        try testing.expect(T == Base([]T));
    }
}

pub const Parser = struct {
    pub fn boolean(s: String) ?bool {
        return switch (s.len) {
            1 => switch (s[0]) {
                'n', 'N', 'f', 'F' => false,
                'y', 'Y', 't', 'T' => true,
                else => null,
            },
            2 => if (std.ascii.eqlIgnoreCase(s, "no")) false else null,
            3 => if (std.ascii.eqlIgnoreCase(s, "yes")) true else null,
            4 => if (std.ascii.eqlIgnoreCase(s, "true")) true else null,
            5 => if (std.ascii.eqlIgnoreCase(s, "false")) false else null,
            else => null,
        };
    }
    test boolean {
        try testing.expectEqual(true, boolean("y"));
        try testing.expectEqual(true, boolean("Y"));
        try testing.expectEqual(true, boolean("t"));
        try testing.expectEqual(true, boolean("T"));
        try testing.expectEqual(false, boolean("n"));
        try testing.expectEqual(false, boolean("N"));
        try testing.expectEqual(false, boolean("f"));
        try testing.expectEqual(false, boolean("F"));
        try testing.expectEqual(true, boolean("yEs"));
        try testing.expectEqual(true, boolean("TRue"));
        try testing.expectEqual(false, boolean("nO"));
        try testing.expectEqual(false, boolean("False"));
        try testing.expectEqual(null, boolean("xxx"));
    }
};

test {
    _ = Usage;
    _ = Parser;
}
