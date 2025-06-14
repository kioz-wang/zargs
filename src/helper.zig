const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const Type = ztype.Type;

const any = @import("fmt").any;

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
            pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
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
                    try any(left, .{}).format(fmt, options, writer);
                } else {
                    try writer.writeAll(comptimePrint("(-{s}", .{s_infinity}));
                }
                try writer.writeAll(",");
                if (self.right) |right| {
                    try any(right, .{}).format(fmt, options, writer);
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

    const _test = struct {
        test StringSet {
            var set: StringSet(2) = .{};
            set.init();
            try testing.expect(!set.contain("a"));
            try testing.expect(set.add("a"));
            try testing.expect(set.contain("a"));
            try testing.expect(!set.add("a"));
        }
        test "Range format" {
            var buffer: [16]u8 = undefined;
            try testing.expectEqualStrings("U", try bufPrint(&buffer, "{}", .{Range(u32).universal}));
            try testing.expectEqualStrings("∅", try bufPrint(&buffer, "{}", .{Range(u32).empty}));
            try testing.expectEqualStrings("(-∞,1)", try bufPrint(&buffer, "{}", .{comptime Range(i32).init(null, 1)}));
            try testing.expectEqualStrings("[-1,1)", try bufPrint(&buffer, "{}", .{comptime Range(i32).init(-1, 1)}));
            try testing.expectEqualStrings("[-1,∞)", try bufPrint(&buffer, "{}", .{comptime Range(i32).init(-1, null)}));
            try testing.expectEqualStrings("[  -f,  +c)", try bufPrint(&buffer, "{x:>4}", .{comptime Range(i32).init(-0xf, 0xc)}));
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
};

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
            .@"struct" => if (std.meta.hasMethod(T, "compare")) a.compare(b) else @compileError(comptimePrint("No compare method implemented for {s}", .{@typeName(T)})),
            else => @compileError(comptimePrint("No compare method implemented for {s}", .{@typeName(T)})),
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
            .@"struct" => |info| if (std.meta.hasMethod(T, "equal")) a.equal(b) else if (std.meta.hasMethod(T, "compare")) a.compare(b) == Order.Equal else if (info.layout == .@"packed") a == b else @compileError(comptimePrint("No equal method implemented for {s}", .{@typeName(T)})),
            else => @compileError(comptimePrint("No equal method implemented for {s}", .{@typeName(T)})),
        };
    }

    // TODO implement sort algo using compare and equal

    const _test = struct {
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
};

pub fn exit(catched: anyerror, status: u8) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("catch: {any}\n", .{catched}) catch unreachable;
    std.process.exit(status);
}

pub fn exitf(catched: ?anyerror, status: u8, comptime fmt: String, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    if (catched) |e|
        stderr.print("catch: {any}\n", .{e}) catch unreachable;
    stderr.print(fmt ++ "\n", args) catch unreachable;
    std.process.exit(status);
}

pub fn Ranges(T: type) type {
    const Range = Collection.Range(T);
    return struct {
        const Self = @This();
        rs: []const Range = &.{},
        pub fn new() Self {
            return .{};
        }
        pub fn u(self: Self, l: ?T, r: ?T) Self {
            const range = Range.init(l, r);
            if (range.is_empty() or range.is_universal()) {
                @compileError(comptimePrint("mustn't union range {}", .{r}));
            }
            var ranges = self;
            ranges.rs = ranges.rs ++ .{range};
            return ranges;
        }
        pub fn _checkOut(self: Self) Self {
            if (self.rs.len == 0) {
                @compileError(comptimePrint("requires to union at least one range", .{}));
            }
            // TODO: Merge ranges
            return self;
        }
        pub fn contain(self: Self, v: T) bool {
            for (self.rs) |r| {
                if (r.contain(v)) return true;
            }
            return false;
        }
    };
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

test {
    _ = Collection._test;
    _ = Compare._test;
}
