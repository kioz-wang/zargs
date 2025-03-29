const std = @import("std");
const testing = std.testing;

pub const Alias = struct {
    pub const String = []const u8;
    pub const print = std.fmt.comptimePrint;
    pub const sprint = std.fmt.bufPrint;
    pub const FormatOptions = std.fmt.FormatOptions;
};

const String = Alias.String;
const print = Alias.print;
const sprint = Alias.sprint;
const FormatOptions = Alias.FormatOptions;

pub const Collection = struct {
    pub fn StringSet(capacity: comptime_int) type {
        const A = std.ArrayListUnmanaged(String);
        return struct {
            const Self = @This();
            base: A = undefined,
            buffer: [capacity]String = undefined,
            pub fn init(self: *Self) void {
                self.base = A.initBuffer(self.buffer[0..]);
            }
            pub fn contain(self: *const Self, s: String) bool {
                return for (self.base.items) |item| {
                    if (std.mem.eql(u8, item, s)) break true;
                } else false;
            }
            pub fn add(self: *Self, s: String) bool {
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

    pub fn Range(T: type) type {
        const _compare = Compare.compare;
        return struct {
            const Self = @This();
            left: ?T,
            right: ?T,
            pub fn init(l: ?T, r: ?T) Self {
                return .{ .left = l, .right = r };
            }
            pub const empty = Self.init(std.mem.zeroes(T), std.mem.zeroes(T));
            pub const universal = Self.init(null, null);
            pub fn is_empty(self: Self) bool {
                return self.left != null and self.right != null and _compare(self.left.?, self.right.?) == .Equal;
            }
            pub fn is_universal(self: Self) bool {
                return self.left == null and self.right == null;
            }
            pub fn format(self: Self, comptime fmt: []const u8, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
                const s_empty = "∅";
                const s_universal = "U";
                const s_infinity = "∞";
                if (self.is_empty()) {
                    try writer.writeAll(s_empty);
                    return;
                }
                if (self.is_universal()) {
                    try writer.writeAll(s_universal);
                    return;
                }
                if (self.left) |left| {
                    try writer.writeAll("[");
                    try niceFormatType(left, fmt, options, writer);
                } else {
                    try writer.writeAll(print("(-{s}", .{s_infinity}));
                }
                try writer.writeAll(",");
                if (self.right) |right| {
                    try niceFormatType(right, fmt, options, writer);
                } else {
                    try writer.writeAll(s_infinity);
                }
                try writer.writeAll(")");
            }
            pub fn contain(self: Self, v: T) bool {
                if (self.left) |left| {
                    if (_compare(left, v) == .Greater) return false;
                }
                if (self.right) |right| {
                    if (_compare(v, right) != .Less) return false;
                }
                return true;
            }
            pub fn compare(self: Self, v: Self) Compare.Order {
                return if (self.left) |left|
                    if (v.left) |v_left| _compare(left, v_left) else .Greater
                else if (v.left) |_| .Less else .Equal;
            }
        };
    }

    test "Range format" {
        var buffer: [16]u8 = undefined;
        try testing.expectEqualStrings("U", try sprint(&buffer, "{}", .{Range(u32).universal}));
        try testing.expectEqualStrings("∅", try sprint(&buffer, "{}", .{Range(u32).empty}));
        try testing.expectEqualStrings("(-∞,1)", try sprint(&buffer, "{}", .{comptime Range(i32).init(null, 1)}));
        try testing.expectEqualStrings("[-1,1)", try sprint(&buffer, "{}", .{comptime Range(i32).init(-1, 1)}));
        try testing.expectEqualStrings("[-1,∞)", try sprint(&buffer, "{}", .{comptime Range(i32).init(-1, null)}));
        try testing.expectEqualStrings("[  -f,  +c)", try sprint(&buffer, "{x:>4}", .{comptime Range(i32).init(-0xf, 0xc)}));
    }

    test "Range contain" {
        try testing.expect(Range(u32).universal.contain(std.mem.zeroes(u32)));
        try testing.expect(Range(u32).universal.contain(1));
        try testing.expect(Range(u32).universal.contain(9999));
        try testing.expect(!Range(u32).empty.contain(std.mem.zeroes(u32)));
        try testing.expect(!Range(u32).empty.contain(1));
        try testing.expect(!Range(u32).empty.contain(9999));
        {
            const range = Range(i32).init(null, 5);
            try testing.expect(range.contain(-1000));
            try testing.expect(range.contain(0));
            try testing.expect(!range.contain(5));
        }
        {
            const range = Range(i32).init(-5, 5);
            try testing.expect(!range.contain(-1000));
            try testing.expect(range.contain(-5));
            try testing.expect(range.contain(0));
            try testing.expect(!range.contain(5));
        }
        {
            const range = Range(i32).init(-5, null);
            try testing.expect(!range.contain(-1000));
            try testing.expect(range.contain(-5));
            try testing.expect(range.contain(0));
            try testing.expect(range.contain(5));
        }
    }

    test "Range compare" {
        const compare = Compare.compare;
        try testing.expectEqual(compare(Range(i32).empty, Range(i32).universal), .Greater);
        try testing.expectEqual(compare(Range(i32).empty, Range(i32).init(0, null)), .Equal);
        try testing.expectEqual(compare(Range(i32).empty, Range(i32).init(1, null)), .Less);
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
        const T = @TypeOf(a);
        return switch (@typeInfo(T)) {
            .int, .comptime_int, .float, .comptime_float => if (a > b) .Greater else if (a == b) .Equal else .Less,
            .@"enum" => if (std.meta.hasMethod(T, "compare")) a.compare(b) else blk: {
                const _a = @intFromEnum(a);
                const _b = @intFromEnum(b);
                break :blk if (_a > _b) .Greater else if (_a == _b) .Equal else .Less;
            },
            .@"struct" => if (std.meta.hasMethod(T, "compare")) a.compare(b) else @compileError(print("No compare method implemented for {s}", .{@typeName(T)})),
            else => @compileError(print("No compare method implemented for {s}", .{@typeName(T)})),
        };
    }

    /// check equal between two values of base T
    ///
    /// for struct, if find `pub fn equal(self: T, v: T) bool`, use it
    ///
    /// for packed struct, just check equal directly
    pub fn equal(a: anytype, b: @TypeOf(a)) bool {
        const T = @TypeOf(a);
        if (T == String) return std.mem.eql(u8, a, b);
        return switch (@typeInfo(T)) {
            .int, .comptime_int, .float, .comptime_float, .bool => a == b,
            .@"enum" => if (std.meta.hasMethod(T, "equal")) a.equal(b) else if (std.meta.hasMethod(T, "compare")) a.compare(b) == Order.Equal else a == b,
            .@"struct" => |info| if (std.meta.hasMethod(T, "equal")) a.equal(b) else if (std.meta.hasMethod(T, "compare")) a.compare(b) == Order.Equal else if (info.layout == .@"packed") a == b else @compileError(print("No equal method implemented for {s}", .{@typeName(T)})),
            else => @compileError(print("No equal method implemented for {s}", .{@typeName(T)})),
        };
    }

    // TODO implement sort algo using compare and equal

    test compare {
        try testing.expectEqual(compare(1, 2), .Less);
        try testing.expectEqual(compare(2, 2), .Equal);
        try testing.expectEqual(compare(3, 2), .Greater);
        try testing.expectEqual(compare(@as(u32, 1), 2), .Less);
        try testing.expectEqual(compare(@as(u32, 2), 2), .Equal);
        try testing.expectEqual(compare(@as(u32, 3), 2), .Greater);
        try testing.expectEqual(compare(1.0, 2.0), .Less);
        try testing.expectEqual(compare(2.0, 2.0), .Equal);
        try testing.expectEqual(compare(3.0, 2.0), .Greater);
        try testing.expectEqual(compare(@as(f32, 1.0), 2.0), .Less);
        try testing.expectEqual(compare(@as(f32, 2.0), 2.0), .Equal);
        try testing.expectEqual(compare(@as(f32, 3.0), 2.0), .Greater);
        {
            const Color = enum { Red, Green, Blue };
            try testing.expectEqual(compare(Color.Red, Color.Green), .Less);
            try testing.expectEqual(compare(Color.Green, Color.Green), .Equal);
            try testing.expectEqual(compare(Color.Blue, Color.Green), .Greater);
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
            try testing.expectEqual(compare(Color.Red, Color.Green), .Less);
            try testing.expectEqual(compare(Color.Green, Color.Green), .Equal);
            try testing.expectEqual(compare(Color.Blue, Color.Green), .Greater);
        }
        {
            const Person = struct {
                age: u32,
                name: String = undefined,
                const _compare = Compare.compare;
                pub fn compare(self: @This(), v: @This()) Order {
                    return _compare(self.age, v.age);
                }
            };
            try testing.expectEqual(compare(Person{ .age = 1 }, Person{ .age = 2 }), .Less);
            try testing.expectEqual(compare(Person{ .age = 2 }, Person{ .age = 2 }), .Equal);
            try testing.expectEqual(compare(Person{ .age = 3 }, Person{ .age = 2 }), .Greater);
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
            const Person = struct {
                age: u32,
                name: String = undefined,
                const _compare = Compare.compare;
                pub fn compare(self: @This(), v: @This()) Order {
                    return _compare(self.age, v.age);
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
        return @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice and T != String;
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

    test isMultiple {
        try testing.expect(isMultiple([4]u8));
        try testing.expect(isSlice([]u8));
        {
            var ab = [_]u8{ 'a', 'b' };
            try testing.expect(isMultiple(@TypeOf(ab)));
            try testing.expect(isArray(@TypeOf(ab)));
            try testing.expect(isSlice(@TypeOf(@as([]u8, @ptrCast(&ab)))));
            try testing.expect(isSlice(@TypeOf(@as([]u8, @ptrCast(ab[0..1])))));
        }
        {
            const ab = [_]u8{ 'a', 'b' };
            try testing.expect(isMultiple(@TypeOf(ab)));
            try testing.expect(isArray(@TypeOf(ab)));
            try testing.expectEqual(String, @TypeOf(@as([]const u8, &ab)));
            try testing.expectEqual(String, @TypeOf(@as([]const u8, ab[0..])));
        }
    }

    test Base {
        try testing.expect(u32 == Base(?u32));
        try testing.expect(u32 == Base([]u32));
        try testing.expect(u32 == Base([4]u32));
        try testing.expect(u8 == Base([]u8));
        try testing.expect(u8 == Base([4]u8));
        {
            const ab = [_]u8{ 'a', 'b', 'c' };
            try testing.expect(u8 == Base(@TypeOf(ab)));
        }
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

fn niceFormatType(value: anytype, comptime fmt: []const u8, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    const T = @TypeOf(value);
    if (T == String) {
        return std.fmt.formatBuf(value, options, writer);
    }
    return switch (@typeInfo(T)) {
        .@"enum" => std.fmt.formatBuf(@tagName(value), options, writer),
        else => std.fmt.formatType(value, fmt, options, writer, std.options.fmt_max_depth),
    };
}

pub fn NiceFormatter(T: type) type {
    return struct {
        const Self = @This();
        v: T,
        pub fn format(self: Self, comptime fmt: []const u8, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            if (comptime Type.Base(T) == T) {
                return niceFormatType(self.v, fmt, options, writer);
            }
            if (comptime Type.isOptional(T)) {
                return if (self.v) |v_| niceFormatType(v_, fmt, options, writer) else writer.writeAll("null");
            }
            if (comptime Type.isMultiple(T)) {
                try writer.writeAll("{");
                for (self.v, 0..) |v_, i| {
                    if (i != 0) {
                        try writer.writeAll(", ");
                    }
                    try niceFormatType(v_, fmt, options, writer);
                }
                try writer.writeAll("}");
                return;
            }
            @compileError(print("Unable to format {s}", .{@typeName(T)}));
        }
        pub fn value(v: T) Self {
            return .{ .v = v };
        }
    };
}

pub fn niceFormatter(value: anytype) NiceFormatter(@TypeOf(value)) {
    return NiceFormatter(@TypeOf(value)).value(value);
}

test "NiceFormatter Base" {
    {
        var buffer: [16]u8 = undefined;
        try testing.expectEqualStrings("1", try sprint(&buffer, "{}", .{NiceFormatter(u32).value(1)}));
        try testing.expectEqualStrings("9.000e-1", try sprint(&buffer, "{:.3}", .{NiceFormatter(f32).value(0.9)}));
        try testing.expectEqualStrings("true", try sprint(&buffer, "{}", .{NiceFormatter(bool).value(true)}));
        try testing.expectEqualStrings("1", print("{}", .{comptime NiceFormatter(u32).value(1)}));
        {
            const ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{a, b}", print("{c}", .{comptime NiceFormatter([2]u8).value(ab)}));
            try testing.expectEqualStrings("{a, b}", print("{c}", .{comptime niceFormatter(ab)}));
            try testing.expectEqualStrings("{a, b}", try sprint(&buffer, "{c}", .{niceFormatter(ab)}));
            try testing.expectEqualStrings("ab", try sprint(&buffer, "{c}", .{NiceFormatter([]const u8).value(&ab)}));
        }
        {
            var ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{a, b}", try sprint(&buffer, "{c}", .{NiceFormatter([]u8).value(&ab)}));
            try testing.expectEqualStrings("{a, b}", try sprint(&buffer, "{c}", .{NiceFormatter([2]u8).value(ab)}));
        }
    }
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
    var buffer: [16]u8 = undefined;
    try testing.expectEqualStrings("1", try sprint(&buffer, "{}", .{NiceFormatter(?u32).value(1)}));
    try testing.expectEqualStrings("f", try sprint(&buffer, "{x}", .{NiceFormatter(?u32).value(0xf)}));
    try testing.expectEqualStrings("##f", try sprint(&buffer, "{x:#>3}", .{NiceFormatter(?u32).value(0xf)}));
    try testing.expectEqualStrings("null", try sprint(&buffer, "{}", .{NiceFormatter(?u32).value(null)}));
    try testing.expectEqualStrings(" hello", try sprint(&buffer, "{:>6}", .{NiceFormatter(?String).value("hello")}));
    try testing.expectEqualStrings("1", print("{}", .{comptime NiceFormatter(?u32).value(1)}));
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
        "{_hello, _world}",
        print("{:_>6}", .{comptime NiceFormatter([2]String).value([_]String{ "hello", "world" })}),
    );
    try testing.expectEqualStrings(
        "{15, 192}",
        print("{}", .{comptime NiceFormatter([]const i32).value(&[_]i32{ 0xf, 0xc0 })}),
    );
    try testing.expectEqualStrings(
        "{0f, c0}",
        print("{x:02}", .{comptime NiceFormatter([]const u32).value(&[_]u32{ 0xf, 0xc0 })}),
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
