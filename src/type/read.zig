const std = @import("std");

const String = @import("base.zig").String;
const LiteralString = @import("base.zig").LiteralString;

fn ReadFn(lazy: bool) type {
    return struct {
        const Self = @This();
        v: String = undefined,
        s: String = undefined,
        @".is_inited": bool = false,
        pub fn parse(s: String, a_maybe: ?std.mem.Allocator) ?Self {
            var self: Self = .{};

            self.s = blk: {
                const s_alloc = a_maybe.?.alloc(u8, s.len) catch return null;
                @memcpy(s_alloc, s);
                break :blk s_alloc;
            };

            if (!lazy) _ = self.unlazy(a_maybe) catch return null;

            return self;
        }
        pub fn unlazy(self: *Self, a_maybe: ?std.mem.Allocator) !String {
            if (!self.@".is_inited") {
                var fp = if (std.mem.eql(u8, self.s, "-")) std.io.getStdIn() else try std.fs.cwd().openFile(self.s, .{});
                defer fp.close();
                self.v = try fp.readToEndAlloc(a_maybe.?, 4 << 10);
                self.@".is_inited" = true;
            }
            return self.v;
        }
        pub fn destroy(self: *Self, a_maybe: ?std.mem.Allocator) void {
            if (self.@".is_inited") a_maybe.?.free(self.v);
            a_maybe.?.free(self.s);
        }
        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("Read({s})", .{self.s});
        }
    };
}

pub const Read = struct {
    pub fn f() type {
        return ReadFn(false);
    }
}.f;
pub const ReadLazy = struct {
    pub fn f() type {
        return ReadFn(true);
    }
}.f;
