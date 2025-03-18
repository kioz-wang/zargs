const std = @import("std");
const token = @import("token.zig");
const parser = @import("parser.zig");
const h = @import("helper.zig");

const Self = @This();

name: [:0]const u8,
T: type,
class: Class,
common: Common = .{},

const Common = struct {
    help: ?[]const u8 = null,
    default: ?*const anyopaque = null,
    parseFn: ?*const anyopaque = null, // optArg, posArg
    callBackFn: ?*const anyopaque = null,
    short: ?u8 = null, // opt, optArg
    long: ?[]const u8 = null, // opt, optArg
    argName: ?[]const u8 = null, // optArg, posArg
};
const Class = enum { opt, optArg, posArg };

pub fn format(self: Self, comptime _: []const u8, _: h.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(h.print("{s}({s},{s})", .{ @tagName(self.class), self.name, @typeName(self.T) }));
}
fn _log(self: Self, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(h.print("{} {s}\n", .{ self, fmt }), args);
}
pub fn opt(name: [:0]const u8, T: type) Self {
    const m: Self = .{ .name = name, .T = T, .class = .opt };
    // Check T
    if (T != bool and @typeInfo(T) != .int) {
        @compileError(h.print("{} illegal type", .{m}));
    }
    // Initialize Meta
    return m;
}
pub fn optArg(name: [:0]const u8, T: type) Self {
    const m: Self = .{ .name = name, .T = T, .class = .optArg };
    // Check T
    const info = @typeInfo(T);
    if (info == .pointer) {
        if (info.pointer.size != .slice or !info.pointer.is_const) {
            @compileError(h.print("{} illegal type", .{m}));
        }
    }
    // Initialize Meta
    return m;
}
pub fn posArg(name: [:0]const u8, T: type) Self {
    const m: Self = .{ .name = name, .T = T, .class = .posArg };
    // Check T
    if (@typeInfo(T) == .pointer and T != []const u8) {
        @compileError(h.print("{} illegal type", .{m}));
    }
    // Initialize Meta
    return m;
}
pub fn help(self: Self, s: []const u8) Self {
    var m = self;
    m.common.help = s;
    return m;
}
pub fn default(self: Self, d: self.T) Self {
    var m = self;
    // Check
    if (m.class == .optArg) {
        if (@typeInfo(m.T) == .pointer and m.T != []const u8) {
            @compileError(h.print("{} not support default", .{self}));
        }
    }
    // Set
    m.common.default = @ptrCast(&d);
    return m;
}
pub fn parseFn(self: Self, f: parser.Fn(parser.Base(self.T))) Self {
    var m = self;
    // Check
    if (m.class == .opt) {
        @compileError(h.print("{} not support parseFn", .{self}));
    }
    // Set
    m.common.parseFn = @ptrCast(&f);
    return m;
}
pub fn callBackFn(self: Self, f: fn (*self.T) void) Self {
    var m = self;
    m.common.callBackFn = @ptrCast(&f);
    return m;
}
pub fn short(self: Self, c: u8) Self {
    var m = self;
    switch (m.class) {
        .opt, .optArg => m.common.short = c,
        .posArg => @compileError(h.print("{} not support short", self)),
    }
    return m;
}
pub fn long(self: Self, s: []const u8) Self {
    var m = self;
    switch (m.class) {
        .opt, .optArg => m.common.long = s,
        .posArg => @compileError(h.print("{} not support long", self)),
    }
    return m;
}
pub fn argName(self: Self, s: []const u8) Self {
    var m = self;
    switch (m.class) {
        .opt => @compileError(h.print("{} not support argName", self)),
        .optArg, .posArg => m.common.argName = s,
    }
    return m;
}

pub fn _checkOut(self: *Self) void {
    if (self.class == .opt) {
        // Set default `default`
        if (self.common.default == null) {
            if (self.T == bool) {
                self.common.default = @ptrCast(&false);
            } else {
                const zero: self.T = 0;
                self.common.default = @ptrCast(&zero);
            }
        }
    }
    if (self.class == .opt or self.class == .optArg) {
        // Check short and long
        if (self.common.short == null and self.common.long == null) {
            @compileError(h.print("{} requires short or long", .{self}));
        }
    }
    if (self.class == .optArg or self.class == .posArg) {
        // Set argName if
        if (self.common.argName == null) {
            self.common.argName = &h.upper(self.name);
        }
    }
}

pub fn _isSlice(self: Self) bool {
    return @typeInfo(self.T) == .pointer and self.T != []const u8;
}
pub fn _toField(self: Self) std.builtin.Type.StructField {
    return .{
        .alignment = @alignOf(self.T),
        .default_value_ptr = self.common.default,
        .is_comptime = false,
        .name = self.name,
        .type = self.T,
    };
}
pub fn _parseAny(self: Self, s: []const u8) ?parser.Base(self.T) {
    if (self.common.parseFn) |f| {
        const p: *const parser.Fn(parser.Base(self.T)) = @ptrCast(@alignCast(f));
        return p(s);
    }
    return parser.any(parser.Base(self.T), s);
}
pub fn _match(self: Self, t: token.Type) bool {
    if (t == .posArg) unreachable;
    if (self.class == .posArg) unreachable;
    switch (t.opt) {
        .short => |s| {
            if (s == self.common.short) return true;
        },
        .long => |s| {
            if (self.common.long) |l| {
                if (std.mem.eql(u8, l, s)) return true;
            }
        },
    }
    return false;
}
pub fn _usage(self: Self) []const u8 {
    return switch (self.class) {
        .opt => h.print("{s}{s}", .{
            h.Usage.optional(true, h.Usage.opt(self.common.short, self.common.long)),
            if (self.T == bool) "" else "...",
        }),
        .optArg => h.print("{s}{s}", .{
            h.Usage.optional(
                self.common.default != null,
                h.print("{s} {s}", .{
                    h.Usage.opt(self.common.short, self.common.long),
                    h.Usage.arg(self.common.argName.?, @typeInfo(self.T)),
                }),
            ),
            if (self._isSlice()) "..." else "",
        }),
        .posArg => h.Usage.optional(
            self.common.default != null,
            h.Usage.arg(self.common.argName.?, @typeInfo(self.T)),
        ),
    };
}
pub fn _help(self: Self) []const u8 {
    return if (self.common.help) |s|
        h.print("{s:<30} {s}", .{ self._usage(), s })
    else
        self._usage();
}
pub const Error = error{
    Missing,
    Invalid,
    Allocator,
};
fn _consumeOpt(self: Self, r: anytype, it: *token.Iter) bool {
    if (self._match(it.viewMust() catch unreachable)) {
        _ = it.next() catch unreachable;
        if (self.T == bool) {
            @field(r, self.name) = !@field(r, self.name);
        } else {
            @field(r, self.name) += 1;
        }
        return true;
    }
    return false;
}
fn _consumeOptArg(self: Self, r: anytype, it: *token.Iter, allocator: ?std.mem.Allocator) Error!bool {
    const prefix = it.viewMust() catch unreachable;
    if (self._match(prefix)) {
        _ = it.next() catch unreachable;
        var s: []const u8 = undefined;
        if (@typeInfo(self.T) == .array) {
            for (&@field(r, self.name), 0..) |*item, i| {
                const t = it.nextMust() catch |err| {
                    self._log("requires {s}[{d}] after {s} but {any}", .{ self.common.argName.?, i, prefix, err });
                    return Error.Missing;
                };
                if (t != .arg) {
                    self._log("requires {s}[{d}] after {s} but {}", .{ self.common.argName.?, i, prefix, t });
                    return Error.Missing;
                }
                s = t.arg;
                item.* = self._parseAny(s) orelse {
                    self._log("unable to parse {s} to {s}[{d}]", .{ s, self.common.argName.?, i });
                    return Error.Invalid;
                };
            }
        } else {
            const t = it.nextMust() catch |err| {
                self._log("requires {s} after {s} but {any}", .{ self.common.argName.?, prefix, err });
                return Error.Missing;
            };
            s = switch (t) {
                .optArg, .arg => |a| a,
                else => {
                    self._log("requires {s} after {s} but {}", .{ self.common.argName.?, prefix, t });
                    return Error.Missing;
                },
            };
            var value = self._parseAny(s) orelse {
                self._log("unable to parse {s} to {s}", .{ s, self.common.argName.? });
                return Error.Invalid;
            };
            if (self.T == []const u8) {
                if (allocator) |a| {
                    const allocS = a.alloc(u8, value.len) catch return Error.Allocator;
                    @memcpy(allocS, value);
                    value = allocS;
                }
            }
            @field(r, self.name) = if (comptime self._isSlice()) blk: {
                if (allocator == null) {
                    self._log("requires allocator", .{});
                    return Error.Allocator;
                }
                var list = std.ArrayList(parser.Base(self.T)).initCapacity(allocator.?, @field(r, self.name).len + 1) catch return Error.Allocator;
                list.appendSliceAssumeCapacity(@field(r, self.name));
                list.appendAssumeCapacity(value);
                allocator.?.free(@field(r, self.name));
                break :blk list.toOwnedSlice() catch return Error.Allocator;
            } else value;
        }
        return true;
    }
    return false;
}
fn _consumePosArg(self: Self, r: anytype, it: *token.Iter, allocator: ?std.mem.Allocator) Error!bool {
    var s: []const u8 = undefined;
    if (@typeInfo(self.T) == .array) {
        for (&@field(r, self.name), 0..) |*item, i| {
            const t = it.nextMust() catch |err| {
                self._log("requires {s}[{d}] but {any}", .{ self.common.argName.?, i, err });
                return Error.Missing;
            };
            s = t.as_posArg().posArg;
            item.* = self._parseAny(s) orelse {
                self._log("unable to parse {s} to {s}[{d}]", .{ s, self.common.argName.?, i });
                return Error.Invalid;
            };
        }
    } else {
        const t = it.nextMust() catch |err| {
            self._log("requires {s} but {any}", .{ self.common.argName.?, err });
            return Error.Missing;
        };
        s = t.as_posArg().posArg;
        var value = self._parseAny(s) orelse {
            self._log("unable to parse {s} to {s}", .{ s, self.common.argName.? });
            return Error.Invalid;
        };
        if (self.T == []const u8) {
            if (allocator) |a| {
                const allocS = a.alloc(u8, value.len) catch return Error.Allocator;
                @memcpy(allocS, value);
                value = allocS;
            }
        }
        @field(r, self.name) = value;
    }
    return true;
}
pub fn _consume(self: Self, r: anytype, it: *token.Iter, allocator: ?std.mem.Allocator) Error!bool {
    const consumed =
        switch (self.class) {
            .opt => self._consumeOpt(r, it),
            .optArg => try self._consumeOptArg(r, it, allocator),
            .posArg => try self._consumePosArg(r, it, allocator),
        };
    if (self.common.callBackFn) |f| {
        const p: *const fn (*self.T) void = @ptrCast(@alignCast(f));
        p(&@field(r, self.name));
    }
    return consumed;
}

const testing = std.testing;
