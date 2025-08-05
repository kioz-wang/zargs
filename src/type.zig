//! Import this module with name `ztype` in `build.zig`, then add these in your source files:
//!
//! ```zig
//! const ztype = @import("ztype");
//! const String = ztype.String;
//! const LiteralString = ztype.LiteralString;
//! const checker = ztype.checker;
//! ```

const std = @import("std");

const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;

pub const String = []const u8;
pub const LiteralString = [:0]const u8;

pub const checker = struct {
    pub fn isBase(T: type) bool {
        if (T == String) return true;
        return switch (@typeInfo(T)) {
            .int, .float, .bool, .@"enum", .@"struct" => true,
            .vector => |vec| @typeInfo(vec.child) != .pointer,
            else => false,
        };
    }
    pub fn TryBase(T: type) type {
        return if (isBase(T)) T else @compileError(comptimePrint("Expected .int, .float, .bool, .@\"enum\", .@\"struct\", .vector (exclude Pointers) or []cosnt u8 type, found '{s}'", .{@typeName(T)}));
    }
    pub fn isArray(T: type) bool {
        return @typeInfo(T) == .array;
    }
    pub fn TryArray(T: type) type {
        return if (isArray(T)) @typeInfo(T).array.child else T;
    }
    pub fn isSlice(T: type) bool {
        return @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice and T != String and T != LiteralString;
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
    pub fn Try(T: type) type {
        return if (isMultiple(T)) TryMultiple(T) else if (isOptional(T)) TryOptional(T) else T;
    }
    pub fn Base(T: type) type {
        return TryBase(Try(T));
    }
};

const testing = std.testing;
test "Check type about Slice" {
    {
        var ab = [_]u8{ 'a', 'b' };
        ab[0] = ab[0];
        try testing.expectEqual([2]u8, @TypeOf(ab));
        try testing.expectEqual(*[2]u8, @TypeOf(&ab));
        try testing.expectEqual(*[2]u8, @TypeOf(ab[0..]));
        try testing.expectEqual(*[1]u8, @TypeOf(ab[1..]));
        try testing.expectEqual([]u8, @TypeOf(@as([]u8, ab[1..])));
        {
            var i: usize = 0;
            i = 1;
            try testing.expectEqual([]u8, @TypeOf(ab[i..]));
        }
    }
    {
        const ab = [_]u8{ 'a', 'b' };
        try testing.expectEqual([2]u8, @TypeOf(ab));
        try testing.expectEqual(*const [2]u8, @TypeOf(&ab));
        try testing.expectEqual(*const [2]u8, @TypeOf(ab[0..]));
        try testing.expectEqual(*const [1]u8, @TypeOf(ab[1..]));
        try testing.expectEqual([]const u8, @TypeOf(@as([]const u8, ab[1..])));
        {
            var i: usize = 0;
            i = 1;
            try testing.expectEqual([]const u8, @TypeOf(ab[i..]));
            try testing.expectEqual([]u8, @TypeOf(@constCast(ab[i..])));
        }
    }
}
test "Check type about String" {
    {
        const s = "hello";
        try testing.expectEqual(*const [5:0]u8, @TypeOf(s));
    }
    {
        const s = "hello".*;
        try testing.expectEqual([5:0]u8, @TypeOf(s));
    }
    {
        const s: []const u8 = "hello";
        try testing.expectEqual([]const u8, @TypeOf(s));
        try testing.expectEqual(5, s.len);
        try testing.expectEqual('o', s[s.len - 1]);
        // error: index 5 outside slice of length 5
        // try testing.expectEqual(0, s[s.len]);
    }
    {
        const s: [:0]const u8 = "hello";
        try testing.expectEqual([:0]const u8, @TypeOf(s));
        try testing.expectEqual(5, s.len);
        try testing.expectEqual('o', s[s.len - 1]);
        try testing.expectEqual(0, s[s.len]);
    }
}
test "Type: isMultiple" {
    try testing.expect(checker.isMultiple([4]u8));
    try testing.expect(checker.isSlice([]u8));
    try testing.expect(!checker.isSlice(LiteralString));
    {
        var ab = [_]u8{ 'a', 'b' };
        try testing.expect(checker.isMultiple(@TypeOf(ab)));
        try testing.expect(checker.isArray(@TypeOf(ab)));
        try testing.expect(checker.isSlice(@TypeOf(@as([]u8, &ab))));
        try testing.expect(checker.isSlice(@TypeOf(@as([]u8, ab[0..]))));
        {
            var i: usize = 0;
            i = 1;
            try testing.expect(checker.isSlice(@TypeOf(ab[i..])));
        }
    }
    {
        const ab = [_]u8{ 'a', 'b' };
        try testing.expect(checker.isMultiple(@TypeOf(ab)));
        try testing.expect(checker.isArray(@TypeOf(ab)));
        try testing.expectEqual(String, @TypeOf(@as([]const u8, &ab)));
        try testing.expectEqual(String, @TypeOf(@as([]const u8, ab[0..])));
        {
            var i: usize = 0;
            i = 1;
            try testing.expectEqual(String, @TypeOf(ab[i..]));
            try testing.expect(checker.isSlice(@TypeOf(@constCast(ab[i..]))));
        }
    }
}
test "Type: Base" {
    try testing.expectEqual(u32, checker.Base(?u32));
    try testing.expectEqual(u32, checker.Base([]u32));
    try testing.expectEqual(u32, checker.Base([4]u32));
    try testing.expectEqual(u8, checker.Base([]u8));
    try testing.expectEqual(u8, checker.Base([4]u8));
    {
        const ab = [_]u8{ 'a', 'b', 'c' };
        try testing.expectEqual(u8, checker.Base(@TypeOf(ab)));
    }
    try testing.expectEqual(String, checker.Base(?String));
    try testing.expectEqual(String, checker.Base([]String));
    try testing.expectEqual(LiteralString, checker.Try([]LiteralString));
    try testing.expect(!checker.isBase(checker.Try([]LiteralString)));
    {
        const T = struct { a: i32 };
        try testing.expectEqual(T, checker.Base(?T));
    }
    {
        const T = enum { Red, Blue };
        try testing.expectEqual(T, checker.Base([]T));
    }
}
