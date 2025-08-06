const std = @import("std");

const String = []const u8;
const LiteralString = [:0]const u8;

const OpenType = enum { file, fileCreate, dir, dirCreate };
fn OpenFlags(openType: OpenType) type {
    return switch (openType) {
        .file => std.fs.File.OpenFlags,
        .fileCreate => std.fs.File.CreateFlags,
        .dir, .dirCreate => std.fs.Dir.OpenOptions,
    };
}
fn OpenValue(openType: OpenType) type {
    return switch (openType) {
        .file, .fileCreate => std.fs.File,
        .dir, .dirCreate => std.fs.Dir,
    };
}
fn OpenFn(openType: OpenType, lazy: bool, flags: OpenFlags(openType)) type {
    return struct {
        const Self = @This();
        v: OpenValue(openType) = undefined,
        s: String = undefined,
        @".is_stdio": bool = false,
        @".is_inited": bool = false,
        pub fn parse(s: String, a_maybe: ?std.mem.Allocator) ?Self {
            var self: Self = .{};

            self.s = if (a_maybe) |a| blk: {
                const s_alloc = a.alloc(u8, s.len) catch return null;
                @memcpy(s_alloc, s);
                break :blk s_alloc;
            } else s;

            switch (openType) {
                .file => if ((comptime flags.mode != .read_write) and std.mem.eql(u8, s, "-")) {
                    self.v = switch (flags.mode) {
                        .read_only => std.io.getStdIn(),
                        .write_only => std.io.getStdOut(),
                        else => unreachable,
                    };
                    self.@".is_stdio" = true;
                    self.@".is_inited" = true;
                },
                .fileCreate => if ((comptime !flags.read) and std.mem.eql(u8, s, "-")) {
                    self.v = std.io.getStdOut();
                    self.@".is_stdio" = true;
                    self.@".is_inited" = true;
                },
                else => {},
            }
            if (!lazy) _ = self.unlazy() catch return null;

            return self;
        }
        pub fn unlazy(self: *Self) !OpenValue(openType) {
            if (!self.@".is_inited") {
                self.v = switch (openType) {
                    .file => try std.fs.cwd().openFile(self.s, flags),
                    .fileCreate => try std.fs.cwd().createFile(self.s, flags),
                    .dir => try std.fs.cwd().openDir(self.s, flags),
                    .dirCreate => try std.fs.cwd().makeOpenPath(self.s, flags),
                };
                self.@".is_inited" = true;
            }
            return self.v;
        }
        pub fn destroy(self: *Self, a_maybe: ?std.mem.Allocator) void {
            if (!self.@".is_stdio" and self.@".is_inited") self.v.close();
            if (a_maybe) |a| a.free(self.s);
        }
        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("{s}({s})", .{ @tagName(openType), self.s });
        }
    };
}

pub const Open = struct {
    pub fn f(openType: OpenType, flags: OpenFlags(openType)) type {
        return OpenFn(openType, false, flags);
    }
}.f;
pub const OpenLazy = struct {
    pub fn f(openType: OpenType, flags: OpenFlags(openType)) type {
        return OpenFn(openType, true, flags);
    }
}.f;
