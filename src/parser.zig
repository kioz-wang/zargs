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
pub fn parseAny(B: type, s: String, a: ?Allocator) ?B {
    if (B == String) {
        return if (a) |allocator| blk: {
            const allocS = allocator.alloc(u8, s.len) catch return null;
            @memcpy(allocS, s);
            break :blk allocS;
        } else s;
    }
    return switch (@typeInfo(B)) {
        .int => std.fmt.parseInt(B, s, 0) catch null,
        .float => std.fmt.parseFloat(B, s) catch null,
        .bool => h.Parser.boolean(s),
        .@"enum" => if (@hasDecl(B, "parse")) B.parse(s, a) else std.meta.stringToEnum(B, s),
        .@"struct" => if (@hasDecl(B, "parse")) B.parse(s, a) else @compileError(h.print("require parser for {s}", .{@typeName(B)})),
        else => {
            @compileError(h.print("unable parse to {s}", .{@typeName(B)}));
        },
    };
}

/// destroy any base T value
///
/// for struct, if find `pub fn destroy(self: T, a: Allocator) void`, use it
pub fn destroyAny(B: type, v: B, a: Allocator) void {
    if (B == String) {
        a.free(v);
        return;
    }
    switch (@typeInfo(B)) {
        .@"struct" => if (@hasDecl(B, "destroy")) v.destroy(a),
        else => {},
    }
}

/// Parser of Base(T)
pub fn Fn(T: type) type {
    return fn (String, ?Allocator) ?h.Base(T);
}

test "Compile Errors" {
    return error.SkipZigTest;
}
