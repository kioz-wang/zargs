const std = @import("std");
const testing = std.testing;

const String = []const u8;

pub fn Wrapper(I: type, R: type, specifier: ?[]const u8) type {
    if (!@hasDecl(I, "go")) {
        @compileError(std.fmt.comptimePrint("Require {s}.go", .{@typeName(I)}));
    }
    const is_ErrorUnion = @typeInfo(R) == .ErrorUnion;
    const BaseR = switch (@typeInfo(R)) {
        .Optional => |info| info.child,
        .ErrorUnion => |info| switch (@typeInfo(info.payload)) {
            .Optional => |info_| info_.child,
            else => @compileError(std.fmt.comptimePrint("Require {s}.go return E!?T instead of {s}", .{ @typeName(I), @typeName(R) })),
        },
        else => @compileError(std.fmt.comptimePrint("Require {s}.go return (E!)?T instead of {s}", .{ @typeName(I), @typeName(R) })),
    };
    return struct {
        const Self = @This();
        it: I,
        cache: ?R = null,
        debug: bool = false,
        fn log(self: *const Self, comptime fmt: []const u8, args: anytype) void {
            if (!self.debug) return;
            std.debug.print(fmt, args);
        }
        pub fn next(self: *Self) R {
            var s: []const u8 = "";
            const item = if (self.cache) |i| blk: {
                self.cache = null;
                s = "(Cached)";
                break :blk i;
            } else self.it.go();
            self.log("\x1b[95mnext\x1b[90m{s}\x1b[0m {" ++ (specifier orelse "") ++ "}\n", .{ s, item });
            return item;
        }
        pub fn view(self: *Self) R {
            var s: []const u8 = "(Cached)";
            if (self.cache == null) {
                self.cache = self.it.go();
                s = "";
            }
            const item = self.cache.?;
            self.log("\x1b[92mview\x1b[90m{s}\x1b[0m {" ++ (specifier orelse "") ++ "}\n", .{ s, item });
            return item;
        }
        pub fn init(it: I) Self {
            return .{ .it = it };
        }
        pub fn deinit(self: *Self) void {
            if (@hasDecl(I, "deinit")) {
                self.it.deinit();
            }
        }
        pub fn nextAll(self: *Self, allocator: std.mem.Allocator) ![]const BaseR {
            var items = std.ArrayList(BaseR).init(allocator);
            defer items.deinit();
            while (if (is_ErrorUnion) (try self.next()) else self.next()) |item| {
                try items.append(item);
            }
            return try items.toOwnedSlice();
        }
    };
}

test "Wrap Compile, T" {
    // error: Require token.ListIter(i32).go return (E!)?T instead of i32
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    _ = Wrapper(ListIter(i32), i32, null);
}

test "Wrap Compile, E!T" {
    // error: Require token.ListIter(i32).go return E!?T instead of error{Compile}!i32
    const skip = true;
    if (skip)
        return error.SkipZigTest;
    _ = Wrapper(ListIter(i32), error{Compile}!i32, null);
}

test "Wrap, normal" {
    var it = Wrapper(ListIter(u32), ?u32, "?").init(.{ .list = &[_]u32{ 1, 2, 3, 4 } });
    it.debug = true;
    defer it.deinit();
    try testing.expectEqual(1, it.view().?);
    try testing.expectEqual(1, it.view().?);
    try testing.expectEqual(1, it.next().?);
    try testing.expectEqual(2, it.next().?);
    try testing.expectEqual(3, it.next().?);
    try testing.expectEqual(4, it.view().?);
    try testing.expectEqual(4, it.next().?);
    try testing.expectEqual(null, it.view());
    try testing.expectEqual(null, it.next());
}

test "Wrap, nextAll" {
    var it = Wrapper(ListIter(u32), ?u32, "?").init(.{ .list = &[_]u32{ 1, 2, 3, 4 } });
    it.debug = true;
    defer it.deinit();
    try testing.expectEqual(1, it.view().?);
    const remain = try it.nextAll(testing.allocator);
    defer testing.allocator.free(remain);
    try testing.expectEqualSlices(u32, &[_]u32{ 1, 2, 3, 4 }, remain);
    try testing.expectEqual(null, it.next());
}

pub fn ListIter(T: type) type {
    return struct {
        const Self = @This();
        list: []const T,
        pub fn go(self: *Self) ?T {
            if (self.list.len == 0) {
                return null;
            }
            const item = self.list[0];
            self.list = self.list[1..];
            return item;
        }
    };
}
