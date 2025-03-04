const std = @import("std");
const testing = std.testing;

pub fn any(T: type, s: []const u8) ?T {
    if (T == []const u8) {
        return s;
    }
    return switch (@typeInfo(T)) {
        .Int => std.fmt.parseInt(T, s, 0) catch null,
        .Float => std.fmt.parseFloat(T, s) catch null,
        .Bool => Builtin.parseBoolean(s),
        .Enum => if (@hasDecl(T, "parser")) T.parser(s) else std.meta.stringToEnum(T, s),
        .Struct => if (@hasDecl(T, "parser")) T.parser(s) else @compileError("require a public parser for " ++ @typeName(T)),
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
        .Array => |i| i.child,
        .Pointer => |i| i.child,
        .Optional => |i| i.child,
        else => T,
    };
}

test {
    _ = Builtin;
}

pub const Builtin = struct {
    fn parseBoolean(s: []const u8) ?bool {
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
    test parseBoolean {
        try testing.expectEqual(true, parseBoolean("y"));
        try testing.expectEqual(true, parseBoolean("Y"));
        try testing.expectEqual(true, parseBoolean("t"));
        try testing.expectEqual(true, parseBoolean("T"));
        try testing.expectEqual(false, parseBoolean("n"));
        try testing.expectEqual(false, parseBoolean("N"));
        try testing.expectEqual(false, parseBoolean("f"));
        try testing.expectEqual(false, parseBoolean("F"));
        try testing.expectEqual(true, parseBoolean("yEs"));
        try testing.expectEqual(true, parseBoolean("TRue"));
        try testing.expectEqual(false, parseBoolean("nO"));
        try testing.expectEqual(false, parseBoolean("False"));
        try testing.expectEqual(null, parseBoolean("xxx"));
    }
};
