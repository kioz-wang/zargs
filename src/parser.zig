const std = @import("std");
const testing = std.testing;
const h = @import("helper.zig");
const String = h.String;
const Allocator = std.mem.Allocator;

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
        .bool => h.Parser.boolean(s),
        .@"enum" => if (@hasDecl(T, "parse")) T.parse(s, a) else std.meta.stringToEnum(T, s),
        .@"struct" => if (@hasDecl(T, "parse")) T.parse(s, a) else @compileError(h.print("require parser for {s}", .{@typeName(T)})),
        else => {
            @compileError(h.print("unable parse to {s}", .{@typeName(T)}));
        },
    };
}

/// destroy slice and any base T value
///
/// for struct, if find `pub fn destroy(self: T, a: Allocator) void`, use it
pub fn destroyAny(T: type, v: T, a: Allocator) void {
    switch (@typeInfo(T)) {
        .pointer => a.free(v), // h.isSlice(T) and T == String
        .@"struct" => if (@hasDecl(T, "destroy")) v.destroy(a),
        else => {},
    }
}

/// parser of base T
pub fn Fn(T: type) type {
    return fn (String, ?Allocator) ?T;
}

/// get base of T
pub fn Base(T: type) type {
    if (T == String) return T;
    const info = @typeInfo(T);
    return switch (info) {
        .array => |i| i.child,
        .pointer => |i| i.child,
        else => T,
    };
}

test "Compile Errors" {
    return error.SkipZigTest;
}
