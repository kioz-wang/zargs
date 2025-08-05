const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;

const ztype = @import("ztype");
const String = ztype.String;
const checker = ztype.checker;

/// parse String to any base T
///
/// for enum and struct, if find `pub fn parse(s: String, a_maybe: ?Allocator) ?T`, use it
///
/// for String, allocate if Allocator is given
pub fn any(T: type, s: String, a_maybe: ?Allocator) ?T {
    switch (T) {
        String => return if (a_maybe) |a| blk: {
            const s_alloc = a.alloc(u8, s.len) catch return null;
            @memcpy(s_alloc, s);
            break :blk s_alloc;
        } else s,
        std.fs.File => return std.fs.cwd().openFile(s, .{}) catch null,
        std.fs.Dir => return std.fs.cwd().openDir(s, .{}) catch null,
        else => {},
    }
    switch (@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, s, 0) catch null,
        .float => return std.fmt.parseFloat(T, s) catch null,
        .bool => return @import("parser/boolean.zig").parse(s),
        .@"enum" => if (std.meta.hasMethod(T, "parse")) {
            return T.parse(s, a_maybe);
        } else {
            return std.meta.stringToEnum(T, s);
        },
        .@"struct" => if (std.meta.hasMethod(T, "parse")) {
            return T.parse(s, a_maybe);
        } else @compileError(comptimePrint("No parse method found in struct {s}", .{@typeName(T)})),
        .vector => |info| {
            std.debug.assert(@typeInfo(info.child) != .pointer);
            const s_trimed = blk: {
                const ss = std.mem.trim(u8, s, " ");
                for ("[{(", "]})") |left, right| {
                    if (ss[0] == left and ss[ss.len - 1] == right) {
                        break :blk ss[1 .. ss.len - 1];
                    }
                }
                return null;
            };
            var it = std.mem.splitAny(u8, s_trimed, ";:,");
            var v = std.mem.zeroes(T);
            inline for (0..info.len) |i| {
                var token = it.next() orelse return null;
                token = std.mem.trim(u8, token, " ");
                v[i] = any(info.child, token, null) orelse return null;
            }
            if (it.next() != null) return null;
            return v;
        },
        else => @compileError(comptimePrint("Unable to parse String as {s}", .{@typeName(T)})),
    }
}

/// destroy any base T value
///
/// for struct, if find `pub fn destroy(self: *T, a_maybe: ?Allocator) void`, use it
pub fn destroy(v: anytype, a_maybe: ?Allocator) void {
    const T = @typeInfo(@TypeOf(v)).pointer.child;
    switch (T) {
        String => {
            if (a_maybe) |a| a.free(v.*);
            return;
        },
        std.fs.File, std.fs.Dir => v.close(),
        else => {},
    }
    switch (@typeInfo(T)) {
        .@"struct", .@"enum" => if (std.meta.hasMethod(T, "destroy")) v.destroy(a_maybe),
        else => {},
    }
}

/// Parser of Base(T)
pub fn Fn(T: type) type {
    return fn (String, ?Allocator) ?checker.Base(T);
}

const testing = std.testing;

test "Compile Errors" {
    return error.SkipZigTest;
}

test "Parse anytype" {
    try testing.expectEqual(null, any(u32, "-2", null));
    try testing.expectEqual(2, any(u32, "2", null));

    try testing.expectEqual(null, any(f32, "1.a", null));
    try testing.expectEqual(1.0, any(f32, "1.0", null));

    try testing.expectEqual(null, any(bool, "tru", null));
    try testing.expectEqual(true, any(bool, "true", null));

    {
        const Color = enum { green, red, blue };
        try testing.expectEqual(null, any(Color, "gree", null));
        try testing.expectEqual(.green, any(Color, "green", null));
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
        try testing.expectEqual(null, any(Color, "greenn", null));
        try testing.expectEqual(.green, any(Color, "gREen", null));
    }

    try testing.expectEqual(null, any(@Vector(2, u32), "(1)", null));
    try testing.expectEqual(null, any(@Vector(2, u32), "(1,)", null));
    try testing.expectEqual(null, any(@Vector(2, u32), "(1,1,)", null));
    try testing.expectEqual(null, any(@Vector(2, u32), "(1,1,1)", null));
    try testing.expectEqual(.{ 1, 1 }, any(@Vector(2, u32), "(1,1)", null));
    try testing.expectEqual(.{ 1, 1 }, any(@Vector(2, u32), "(1;1)", null));
    try testing.expectEqual(.{ 1, 1 }, any(@Vector(2, u32), "(1:1)", null));
    try testing.expectEqual(.{ 1, 1 }, any(@Vector(2, u32), "{ 1, 1 }", null));
    try testing.expectEqual(.{ 1, 1 }, any(@Vector(2, u32), "[1; 1]", null));
    try testing.expectEqual(.{ true, false }, any(@Vector(2, bool), "(y,n)", null));
    try testing.expectEqual(.{ 1.0, 2.0 }, any(@Vector(2, f32), "(1.0,2.0)", null));
}
