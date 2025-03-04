const std = @import("std");
const token = @import("token.zig");
const parser = @import("parser.zig");

pub const Meta = struct {
    log: ?*const @TypeOf(std.debug.print) = null,

    name: [:0]const u8,
    T: type,
    help: ?[]const u8 = null,
    default: ?*const anyopaque = null,
    parseFn: ?*const anyopaque = null,
    callBackFn: ?*const anyopaque = null,

    pub fn isSlice(self: Meta) bool {
        return @typeInfo(self.T) == .Pointer and self.T != []const u8;
    }

    pub fn toField(self: Meta) std.builtin.Type.StructField {
        return .{
            .alignment = @alignOf(self.T),
            .default_value = self.default,
            .is_comptime = false,
            .name = self.name,
            .type = self.T,
        };
    }

    fn parseAny(self: Meta, s: []const u8) ?parser.Base(self.T) {
        if (self.parseFn) |f| {
            const p: *const parser.Fn(parser.Base(self.T)) = @ptrCast(@alignCast(f));
            return p(s);
        }
        return parser.any(parser.Base(self.T), s);
    }
};

pub fn hitOpt(self: anytype, opt: token.Type) bool {
    switch (opt.Opt) {
        .Short => |s| {
            if (s == self.short) return true;
        },
        .Long => |l| {
            if (self.long) |long|
                if (std.mem.eql(u8, long, l)) return true;
        },
    }
    return false;
}

const Usage = struct {
    const print = std.fmt.comptimePrint;
    fn opt(short: ?u8, long: ?[]const u8) []const u8 {
        var u: []const u8 = "";
        if (short) |s| {
            u = "-" ++ [_]u8{s};
        }
        if (short != null and long != null) {
            u = u ++ "|";
        }
        if (long) |l| {
            u = u ++ "--" ++ l;
        }
        return u;
    }
    fn arg(name: []const u8, info: std.builtin.Type) []const u8 {
        return print("{{{s}{s}}}", .{ if (info == .Array) print("[{d}]", .{info.Array.len}) else "", name });
    }
    fn optional(has_default: bool, u: []const u8) []const u8 {
        return if (has_default) print("[{s}]", .{u}) else u;
    }
};

pub const Error = error{
    Missing,
    Invalid,
    Allocator,
};

pub const Opt = struct {
    meta: Meta,
    short: ?u8 = null,
    long: ?[]const u8 = null,

    const Self = @This();

    pub fn usage(self: Self) []const u8 {
        return Usage.print("{s}{s}", .{
            Usage.optional(true, Usage.opt(self.short, self.long)),
            if (self.meta.T == bool) "" else "...",
        });
    }
    pub fn help(self: Self) []const u8 {
        return if (self.meta.help) |s| Usage.print("{s:<30} {s}", .{ self.usage(), s }) else self.usage();
    }
    pub fn consume(self: Self, r: anytype, it: *token.Iter) bool {
        const opt = it.viewMust() catch unreachable;
        if (hitOpt(self, opt)) {
            _ = it.next() catch unreachable;
            if (self.meta.T == bool) {
                @field(r, self.meta.name) = !@field(r, self.meta.name);
            } else {
                @field(r, self.meta.name) += 1;
            }
            if (self.meta.callBackFn) |f| {
                const p: *const fn (*self.meta.T) void = @ptrCast(@alignCast(f));
                p(&@field(r, self.meta.name));
            }
            return true;
        }
        return false;
    }
};

pub const OptArg = struct {
    meta: Meta,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    arg_name: []const u8,

    const Self = @This();

    pub fn usage(self: Self) []const u8 {
        return Usage.print("{s}{s}", .{
            Usage.optional(
                self.meta.default != null,
                Usage.print("{s} {s}", .{
                    Usage.opt(self.short, self.long),
                    Usage.arg(self.arg_name, @typeInfo(self.meta.T)),
                }),
            ),
            if (@typeInfo(self.meta.T) == .Pointer and self.meta.T != []const u8) "..." else "",
        });
    }
    pub fn help(self: Self) []const u8 {
        return if (self.meta.help) |s| Usage.print("{s:<30} {s}", .{ self.usage(), s }) else self.usage();
    }
    pub fn consume(self: Self, r: anytype, it: *token.Iter, allocator: ?std.mem.Allocator) Error!bool {
        const opt = it.viewMust() catch unreachable;
        if (hitOpt(self, opt)) {
            _ = it.next() catch unreachable;
            var s: []const u8 = undefined;
            if (@typeInfo(self.meta.T) == .Array) {
                for (&@field(r, self.meta.name), 0..) |*item, i| {
                    const t = it.nextMust() catch |err| {
                        if (self.meta.log) |log| {
                            log("{s}: Expect {s}[{d}] but {any}", .{ opt, self.arg_name, i, err });
                        }
                        return Error.Missing;
                    };
                    if (t != .Arg) {
                        if (self.meta.log) |log| {
                            log("{s}: Expect {s}[{d}] but {}", .{ opt, self.arg_name, i, t });
                        }
                        return Error.Missing;
                    }
                    s = t.Arg;
                    item.* = self.meta.parseAny(s) orelse {
                        if (self.meta.log) |log| {
                            log("{s}: Parse {s}[{d}] but fail from {s}", .{ opt, self.arg_name, i, s });
                        }
                        return Error.Invalid;
                    };
                }
            } else {
                const t = it.nextMust() catch |err| {
                    if (self.meta.log) |log| {
                        log("{s}: Expect {s} but {any}", .{ opt, self.arg_name, err });
                    }
                    return Error.Missing;
                };
                s = switch (t) {
                    .OptArg => |o| o.arg,
                    .Arg => |a| a,
                    else => {
                        if (self.meta.log) |log| {
                            log("{s}: Expect {s} but {}", .{ opt, self.arg_name, t });
                        }
                        return Error.Missing;
                    },
                };
                var value = self.meta.parseAny(s) orelse {
                    if (self.meta.log) |log| {
                        log("{s}: Parse {s} but fail from {s}", .{ opt, self.arg_name, s });
                    }
                    return Error.Invalid;
                };
                if (self.meta.T == []const u8) {
                    if (allocator) |a| {
                        const allocS = a.alloc(u8, value.len) catch return Error.Allocator;
                        @memcpy(allocS, value);
                        value = allocS;
                    }
                }
                @field(r, self.meta.name) = if (comptime self.meta.isSlice()) blk: {
                    var list = std.ArrayList(parser.Base(self.meta.T)).initCapacity(allocator.?, @field(r, self.meta.name).len + 1) catch return Error.Allocator;
                    list.appendSliceAssumeCapacity(@field(r, self.meta.name));
                    list.appendAssumeCapacity(value);
                    allocator.?.free(@field(r, self.meta.name));
                    break :blk list.toOwnedSlice() catch return Error.Allocator;
                } else value;
            }
            if (self.meta.callBackFn) |f| {
                const p: *const fn (*self.meta.T) void = @ptrCast(@alignCast(f));
                p(&@field(r, self.meta.name));
            }
            return true;
        }
        return false;
    }
};

pub const PosArg = struct {
    meta: Meta,
    arg_name: []const u8,

    const Self = @This();

    pub fn usage(self: Self) []const u8 {
        return Usage.optional(
            self.meta.default != null,
            Usage.arg(self.arg_name, @typeInfo(self.meta.T)),
        );
    }
    pub fn help(self: Self) []const u8 {
        return if (self.meta.help) |s| Usage.print("{s:<30} {s}", .{ self.usage(), s }) else self.usage();
    }
    pub fn consume(self: Self, r: anytype, it: *token.Iter, allocator: ?std.mem.Allocator) Error!void {
        var s: []const u8 = undefined;
        if (@typeInfo(self.meta.T) == .Array) {
            for (&@field(r, self.meta.name), 0..) |*item, i| {
                const t = it.nextMust() catch |err| {
                    if (self.meta.log) |log| {
                        log("Expect {s}[{d}] but {any}", .{ self.arg_name, i, err });
                    }
                    return Error.Missing;
                };
                s = t.as_posArg().PosArg;
                item.* = self.meta.parseAny(s) orelse {
                    if (self.meta.log) |log| {
                        log("Parse {s}[{d}] but fail from {s}", .{ self.arg_name, i, s });
                    }
                    return Error.Invalid;
                };
            }
        } else {
            const t = it.nextMust() catch |err| {
                if (self.meta.log) |log| {
                    log("Expect {s} but {any}", .{ self.arg_name, err });
                }
                return Error.Missing;
            };
            s = t.as_posArg().PosArg;
            var value = self.meta.parseAny(s) orelse {
                if (self.meta.log) |log| {
                    log("Parse {s} but fail from {s}", .{ self.arg_name, s });
                }
                return Error.Invalid;
            };
            if (self.meta.T == []const u8) {
                if (allocator) |a| {
                    const allocS = a.alloc(u8, value.len) catch return Error.Allocator;
                    @memcpy(allocS, value);
                    value = allocS;
                }
            }
            @field(r, self.meta.name) = value;
        }
        if (self.meta.callBackFn) |f| {
            const p: *const fn (*self.meta.T) void = @ptrCast(@alignCast(f));
            p(&@field(r, self.meta.name));
        }
    }
};
