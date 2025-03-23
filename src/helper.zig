const std = @import("std");
const testing = std.testing;

pub const Alias = struct {
    pub const String = []const u8;
    pub const print = std.fmt.comptimePrint;
    pub const FormatOptions = std.fmt.FormatOptions;
};

const String = Alias.String;
const print = Alias.print;

pub const Collection = struct {
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
};

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

pub const Compare = struct {
    pub const Order = enum { Less, Equal, Greater };

    /// compare between two values of base T
    ///
    /// for enum and struct, if find `pub fn compare(self: T, v: T) Order`, use it
    pub fn compare(a: anytype, b: @TypeOf(a)) Order {
        const B = @TypeOf(a);
        if (B == comptime_int or B == comptime_float) return if (a > b) .Greater else if (a == b) .Equal else .Less;
        return switch (@typeInfo(B)) {
            .int, .float => if (a > b) .Greater else if (a == b) .Equal else .Less,
            .@"enum" => if (@hasDecl(B, "compare")) a.compare(b) else blk: {
                const _a = @intFromEnum(a);
                const _b = @intFromEnum(b);
                break :blk if (_a > _b) .Greater else if (_a == _b) .Equal else .Less;
            },
            .@"struct" => if (@hasDecl(B, "compare")) a.compare(b) else @compileError(print("require comparer for {s}", .{@typeName(B)})),
            else => @compileError(print("unable compare in {s}", .{@typeName(B)})),
        };
    }

    /// check equal between two values of base T
    ///
    /// for struct, if find `pub fn equal(self: T, v: T) bool`, use it
    ///
    /// for packed struct, just check equal directly
    pub fn equal(a: anytype, b: @TypeOf(a)) bool {
        const B = @TypeOf(a);
        if (B == String) return std.mem.eql(u8, a, b);
        if (B == comptime_int or B == comptime_float) return a == b;
        return switch (@typeInfo(B)) {
            .int, .float, .bool, .@"enum" => a == b,
            .@"struct" => |info| if (@hasDecl(B, "equal")) a.equal(b) else if (info.layout == .@"packed") a == b else @compileError(print("require equaler for {s}", .{@typeName(B)})),
            else => @compileError(print("unable check equal in {s}", .{@typeName(B)})),
        };
    }

    test compare {
        try testing.expectEqual(compare(1, 2), Order.Less);
        try testing.expectEqual(compare(2, 2), Order.Equal);
        try testing.expectEqual(compare(3, 2), Order.Greater);
        try testing.expectEqual(compare(@as(u32, 1), 2), Order.Less);
        try testing.expectEqual(compare(@as(u32, 2), 2), Order.Equal);
        try testing.expectEqual(compare(@as(u32, 3), 2), Order.Greater);
        try testing.expectEqual(compare(1.0, 2.0), Order.Less);
        try testing.expectEqual(compare(2.0, 2.0), Order.Equal);
        try testing.expectEqual(compare(3.0, 2.0), Order.Greater);
        try testing.expectEqual(compare(@as(f32, 1.0), 2.0), Order.Less);
        try testing.expectEqual(compare(@as(f32, 2.0), 2.0), Order.Equal);
        try testing.expectEqual(compare(@as(f32, 3.0), 2.0), Order.Greater);
        {
            const Color = enum { Red, Green, Blue };
            try testing.expectEqual(compare(Color.Red, Color.Green), Order.Less);
            try testing.expectEqual(compare(Color.Green, Color.Green), Order.Equal);
            try testing.expectEqual(compare(Color.Blue, Color.Green), Order.Greater);
        }
        {
            const Color = enum {
                Red,
                Green,
                Blue,
                pub fn compare(self: @This(), v: @This()) Order {
                    const _a = @intFromEnum(self);
                    const _b = @intFromEnum(v);
                    return if (_a > _b) .Greater else if (_a == _b) .Equal else .Less;
                }
            };
            try testing.expectEqual(compare(Color.Red, Color.Green), Order.Less);
            try testing.expectEqual(compare(Color.Green, Color.Green), Order.Equal);
            try testing.expectEqual(compare(Color.Blue, Color.Green), Order.Greater);
        }
        {
            const Person = struct {
                age: u32,
                name: String = undefined,
                pub fn compare(self: @This(), v: @This()) Order {
                    const _a = self.age;
                    const _b = v.age;
                    return if (_a > _b) .Greater else if (_a == _b) .Equal else .Less;
                }
            };
            try testing.expectEqual(compare(Person{ .age = 1 }, Person{ .age = 2 }), Order.Less);
            try testing.expectEqual(compare(Person{ .age = 2 }, Person{ .age = 2 }), Order.Equal);
            try testing.expectEqual(compare(Person{ .age = 3 }, Person{ .age = 2 }), Order.Greater);
        }
    }

    test equal {
        {
            const stringA: []const u8 = "hello";
            const stringB: []const u8 = "world";
            try testing.expect(equal(stringA, stringA));
            try testing.expect(!equal(stringB, stringA));
        }
        try testing.expect(equal(1, 1));
        try testing.expect(!equal(2, 1));
        try testing.expect(equal(@as(u32, 1), 1));
        try testing.expect(!equal(@as(u32, 2), 1));
        try testing.expect(equal(1.0, 1.0));
        try testing.expect(!equal(2.0, 1.0));
        try testing.expect(equal(@as(f32, 1.0), 1.0));
        try testing.expect(!equal(@as(f32, 2.0), 1.0));
        try testing.expect(equal(true, true));
        try testing.expect(!equal(false, true));
        {
            const Color = enum { Red, Green, Blue };
            try testing.expect(equal(Color.Green, Color.Green));
            try testing.expect(!equal(Color.Red, Color.Green));
        }
        {
            const Person = struct {
                age: u32,
                name: String = undefined,
                pub fn equal(self: @This(), v: @This()) bool {
                    return self.age == v.age;
                }
            };
            try testing.expect(equal(Person{ .age = 2 }, Person{ .age = 2 }));
            try testing.expect(!equal(Person{ .age = 1 }, Person{ .age = 2 }));
        }
        {
            const Person = packed struct {
                age: u32,
                sex: bool = true,
            };
            try testing.expect(equal(Person{ .age = 2 }, Person{ .age = 2 }));
            try testing.expect(!equal(Person{ .age = 1 }, Person{ .age = 2 }));
        }
    }
};

pub const Type = struct {
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
};

fn formatBase(v: anytype) []const u8 {
    const T = @TypeOf(v);
    if (T == String) return print("{s}", .{v});
    return switch (@typeInfo(T)) {
        .int, .bool, .@"struct" => print("{any}", .{v}),
        .float => print("{:.3}", .{v}),
        .@"enum" => print("{s}", .{@tagName(v)}),
        else => unreachable,
    };
}

pub fn NiceFormatter(T: type) type {
    return struct {
        v: T,
        pub fn format(self: @This(), comptime _: []const u8, _: Alias.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            if (Type.Base(T) == T) {
                try writer.writeAll(formatBase(self.v));
                return;
            }
            if (Type.isOptional(T)) {
                try writer.writeAll(if (self.v) |v_| formatBase(v_) else "null");
                return;
            }
            if (Type.isMultiple(T)) {
                try writer.writeAll("{");
                for (self.v, 0..) |v_, i| {
                    if (i != 0) {
                        try writer.writeAll(", ");
                    }
                    try writer.writeAll(formatBase(v_));
                }
                try writer.writeAll("}");
                return;
            }
            unreachable;
        }
        pub fn value(v: T) @This() {
            return .{ .v = v };
        }
    };
}

test "NiceFormatter Base" {
    try testing.expectEqualStrings("1", print("{}", .{comptime NiceFormatter(u32).value(1)}));
    try testing.expectEqualStrings("9.000e-1", print("{}", .{comptime NiceFormatter(f32).value(0.9)}));
    try testing.expectEqualStrings("true", print("{}", .{comptime NiceFormatter(bool).value(true)}));
    {
        const Color = enum { Red, Green, Blue };
        try testing.expectEqualStrings(
            "Green",
            print("{}", .{comptime NiceFormatter(Color).value(.Green)}),
        );
    }
    {
        const Person = struct { age: u32, name: String };
        try testing.expectEqualStrings(
            "helper.test.NiceFormatter Base.Person{ .age = 18, .name = { 74, 97, 99, 107 } }",
            print("{}", .{comptime NiceFormatter(Person).value(.{ .age = 18, .name = "Jack" })}),
        );
    }
}

test "NiceFormatter Optional" {
    try testing.expectEqualStrings("1", print("{}", .{comptime NiceFormatter(?u32).value(1)}));
    try testing.expectEqualStrings("null", print("{}", .{comptime NiceFormatter(?u32).value(null)}));
}

test "NiceFormatter Multiple" {
    try testing.expectEqualStrings(
        "{}",
        print("{}", .{comptime NiceFormatter([]String).value(&[_]String{})}),
    );
    try testing.expectEqualStrings(
        "{hello, world}",
        print("{}", .{comptime NiceFormatter([]const String).value(&[_]String{ "hello", "world" })}),
    );
    try testing.expectEqualStrings(
        "{hello, world}",
        print("{}", .{comptime NiceFormatter([2]String).value([_]String{ "hello", "world" })}),
    );
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
    _ = Collection;
    _ = Compare;
    _ = Type;
    _ = Parser;
}
