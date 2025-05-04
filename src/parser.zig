const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const helper = @import("helper.zig");
const print = helper.Alias.print;
const String = helper.Alias.String;

/// parse String to any base T
///
/// for enum and struct, if find `pub fn parse(s: String, a: ?Allocator) ?T`, use it
///
/// for String, allocate if Allocator is given
pub fn parseAny(T: type, s: String, a: ?Allocator) ?T {
    if (T == String) {
        return if (a) |allocator| blk: {
            const allocS = allocator.alloc(u8, s.len) catch return null;
            @memcpy(allocS, s);
            break :blk allocS;
        } else s;
    }
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, s, 0) catch null,
        .float => std.fmt.parseFloat(T, s) catch null,
        .bool => helper.Parser.boolean(s),
        .@"enum" => if (std.meta.hasMethod(T, "parse")) T.parse(s, a) else std.meta.stringToEnum(T, s),
        .@"struct" => if (std.meta.hasMethod(T, "parse")) T.parse(s, a) else @compileError(print("No parse method implemented for {s}", .{@typeName(T)})),
        .vector => |vec| blk: {
            if (@typeInfo(vec.child) == .pointer) unreachable;
            const ss = std.mem.trim(u8, s, "(){}[] ");
            var it = std.mem.splitAny(u8, ss, ";:,");
            var v = std.mem.zeroes(T);
            inline for (0..vec.len) |i| {
                var token = it.next() orelse return null;
                token = std.mem.trim(u8, token, " ");
                v[i] = parseAny(vec.child, token, null) orelse return null;
            }
            if (it.next() != null) return null;
            break :blk v;
        },
        else => @compileError(print("No parse method implemented for {s}", .{@typeName(T)})),
    };
}

/// destroy any base T value
///
/// for struct, if find `pub fn destroy(self: T, a: Allocator) void`, use it
pub fn destroyAny(v: anytype, a: Allocator) void {
    const T = @TypeOf(v);
    if (T == String) {
        a.free(v);
        return;
    }
    switch (@typeInfo(T)) {
        .@"struct" => if (std.meta.hasMethod(T, "destroy")) v.destroy(a),
        else => {},
    }
}

/// Parser of Base(T)
pub fn Fn(T: type) type {
    return fn (String, ?Allocator) ?helper.Type.Base(T);
}

test "Compile Errors" {
    return error.SkipZigTest;
}

test "Parse anytype" {
    try testing.expectEqual(null, parseAny(u32, "-2", null));
    try testing.expectEqual(2, parseAny(u32, "2", null));

    try testing.expectEqual(null, parseAny(f32, "1.a", null));
    try testing.expectEqual(1.0, parseAny(f32, "1.0", null));

    try testing.expectEqual(null, parseAny(bool, "tru", null));
    try testing.expectEqual(true, parseAny(bool, "true", null));

    {
        const Color = enum { green, red, blue };
        try testing.expectEqual(null, parseAny(Color, "gree", null));
        try testing.expectEqual(.green, parseAny(Color, "green", null));
    }

    {
        const Color = enum {
            green,
            red,
            blue,
            pub fn parse(s: []const u8, _: ?std.mem.Allocator) ?@This() {
                const max = @tagName(@This().green).len;
                if (s.len > max) return null;
                var buffer: [max]u8 = undefined;
                const ss = std.ascii.lowerString(&buffer, s);
                return std.meta.stringToEnum(@This(), ss);
            }
        };
        try testing.expectEqual(null, parseAny(Color, "greenn", null));
        try testing.expectEqual(.green, parseAny(Color, "gREen", null));
    }

    try testing.expectEqual(null, parseAny(@Vector(2, u32), "(1)", null));
    try testing.expectEqual(null, parseAny(@Vector(2, u32), "(1,)", null));
    try testing.expectEqual(null, parseAny(@Vector(2, u32), "(1,1,)", null));
    try testing.expectEqual(null, parseAny(@Vector(2, u32), "(1,1,1)", null));
    try testing.expectEqual(.{ 1, 1 }, parseAny(@Vector(2, u32), "(1,1)", null));
    try testing.expectEqual(.{ 1, 1 }, parseAny(@Vector(2, u32), "(1;1)", null));
    try testing.expectEqual(.{ 1, 1 }, parseAny(@Vector(2, u32), "(1:1)", null));
    try testing.expectEqual(.{ 1, 1 }, parseAny(@Vector(2, u32), "{ 1, 1 }", null));
    try testing.expectEqual(.{ 1, 1 }, parseAny(@Vector(2, u32), "[1; 1]", null));
    try testing.expectEqual(.{ true, false }, parseAny(@Vector(2, bool), "(y,n)", null));
    try testing.expectEqual(.{ 1.0, 2.0 }, parseAny(@Vector(2, f32), "(1.0,2.0)", null));
}
