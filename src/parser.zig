const std = @import("std");
const testing = std.testing;
const h = @import("helper.zig");

pub fn any(T: type, s: []const u8) ?T {
    if (T == []const u8) {
        return s;
    }
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, s, 0) catch null,
        .float => std.fmt.parseFloat(T, s) catch null,
        .bool => h.Parser.boolean(s),
        .@"enum" => if (@hasDecl(T, "parser")) T.parser(s) else std.meta.stringToEnum(T, s),
        .@"struct" => if (@hasDecl(T, "parser")) T.parser(s) else @compileError("require a public parser for " ++ @typeName(T)),
        else => {
            @compileError("unable parse to " ++ @typeName(T));
        },
    };
}

test "any, Compile, notfound parser" {
    // error: require a public parser for
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    const T = struct {};
    _ = any(T, "");
}

test "any, Compile, unable" {
    // error: unable parse to void
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    _ = any(@TypeOf({}), "");
}

pub fn Fn(T: type) type {
    return fn ([]const u8) ?T;
}

pub fn Base(T: type) type {
    if (T == []const u8) return T;
    const info = @typeInfo(T);
    return switch (info) {
        .array => |i| i.child,
        .pointer => |i| i.child,
        .optional => |i| i.child,
        else => T,
    };
}
