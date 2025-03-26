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
