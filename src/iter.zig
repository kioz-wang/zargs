const std = @import("std");
const testing = std.testing;
const String = @import("helper.zig").String;

/// Wrap an iterator type that has a `go` method, adding caching features (`next` and `view`) to it.
///
/// The type `R` is the return type of the `go` method, which could be `?T` or `E!?T`. The `specifier` is the format string for the type `R`.
pub fn Wrapper(I: type, R: type, specifier: ?[]const u8) type {
    if (!std.meta.hasMethod(I, "go")) {
        @compileError(std.fmt.comptimePrint("Require {s}.go", .{@typeName(I)}));
    }
    const is_ErrorUnion = @typeInfo(R) == .error_union;
    const BaseR = switch (@typeInfo(R)) {
        .optional => |info| info.child,
        .error_union => |info| switch (@typeInfo(info.payload)) {
            .optional => |info_| info_.child,
            else => @compileError(std.fmt.comptimePrint("Require {s}.go return E!?T instead of {s}", .{ @typeName(I), @typeName(R) })),
        },
        else => @compileError(std.fmt.comptimePrint("Require {s}.go return (E!)?T instead of {s}", .{ @typeName(I), @typeName(R) })),
    };
    return struct {
        const Self = @This();
        /// An iterator with a `go` method
        it: I,
        cache: ?R = null,
        /// If set to `true`, the cache status will be displayed when calling `next` and `view`.
        debug: bool = false,
        fn log(self: *const Self, comptime fmt: []const u8, args: anytype) void {
            if (!self.debug) return;
            std.debug.print(fmt, args);
        }
        /// If a cache exists, it will be consumed and returned; otherwise, the `go` method will be called.
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
        /// If no cache exists, the `go` method will be called, and the result will be stored in the cache. The cache is then returned.
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
        /// If the iterator has a `deinit` method, it will be called.
        pub fn deinit(self: *Self) void {
            if (std.meta.hasMethod(I, "deinit")) {
                self.it.deinit();
            }
        }
        /// Complete the remaining iteration.
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

/// A list iterator type with a `go` method that returns a value of type `?T`.
pub fn ListIter(T: type) type {
    return struct {
        const Self = @This();
        /// A list used for iteration.
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
