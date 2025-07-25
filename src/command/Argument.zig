const std = @import("std");
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;

const helper = @import("helper");
const Ranges = helper.Ranges;
const equal = helper.Compare.equal;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const Type = ztype.Type;
const Allocator = std.mem.Allocator;
const Base = Type.Base;
const isSlice = Type.isSlice;
const isOptional = Type.isOptional;
const isArray = Type.isArray;
const isMultiple = Type.isMultiple;
const TryOptional = Type.TryOptional;

const token = @import("token.zig");

const par = @import("par");
const any = @import("fmt").any;
const stringify = @import("fmt").stringify;
const comptimeUpperString = @import("fmt").comptimeUpperString;

const AFormatter = @import("AFormatter.zig");
const Config = @import("Config.zig");

const Self = @This();

name: LiteralString,
T: type,
class: Class,
meta: Meta = .{},

const Meta = struct {
    help: ?LiteralString = null,
    default: ?*const anyopaque = null,
    parseFn: ?*const anyopaque = null, // optArg, posArg
    callbackFn: ?*const anyopaque = null,
    short: []const u8 = &.{}, // opt, optArg
    long: []const String = &.{}, // opt, optArg
    argName: ?LiteralString = null, // optArg, posArg
    ranges: ?*const anyopaque = null, // optArg, posArg
    choices: ?*const anyopaque = null, // optArg, posArg
    rawChoices: ?[]const String = null, // optArg, posArg
};
const Class = enum { opt, optArg, posArg };

// TODO remove this ?
pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(comptimePrint("{s}({s},{s})", .{ @tagName(self.class), self.name, @typeName(self.T) }));
}
fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
    // TODO maybe compileErrorf()?
    std.debug.print(comptimePrint("{} {s}\n", .{ self, fmt }), args);
}

pub fn opt(name: LiteralString, T: type) Self {
    const arg: Self = .{ .name = name, .T = T, .class = .opt };
    // Check T
    if (T != bool and @typeInfo(T) != .int) {
        @compileError(comptimePrint("{} expect .bool or .int type, found '{s}'", .{ arg, @typeName(T) }));
    }
    // Initialize Arg
    return arg;
}
pub fn optArg(name: LiteralString, T: type) Self {
    const arg: Self = .{ .name = name, .T = T, .class = .optArg };
    // Check T
    _ = Base(T);
    // Initialize Arg
    return arg;
}
pub fn posArg(name: LiteralString, T: type) Self {
    const arg: Self = .{ .name = name, .T = T, .class = .posArg };
    // Check T
    _ = Base(T);
    if (isSlice(T)) {
        @compileError(comptimePrint("{} illegal type, consider to use .nextAllBase of TokenIter", .{arg}));
    }
    // Initialize Arg
    return arg;
}
pub fn help(self: Self, s: LiteralString) Self {
    var arg = self;
    arg.meta.help = s;
    return arg;
}
pub fn default(self: Self, v: self.T) Self {
    if (isOptional(self.T)) {
        @compileError(comptimePrint("{} not support .default, it's forced to be null", .{self}));
    }
    if (isSlice(self.T)) {
        @compileError(comptimePrint("{} not support .default, it's forced to be empty slice", .{self}));
    }
    var arg = self;
    arg.meta.default = @ptrCast(&v);
    return arg;
}
pub fn parseFn(self: Self, f: par.Fn(self.T)) Self {
    if (self.class == .opt) {
        @compileError(comptimePrint("{} not support .parseFn", .{self}));
    }
    var arg = self;
    arg.meta.parseFn = @ptrCast(&f);
    return arg;
}
pub fn callbackFn(self: Self, f: fn (*TryOptional(self.T)) void) Self {
    var arg = self;
    arg.meta.callbackFn = @ptrCast(&f);
    return arg;
}
pub fn short(self: Self, c: u8) Self {
    if (self.class == .posArg) {
        @compileError(comptimePrint("{} not support .short", .{self}));
    }
    var arg = self;
    arg.meta.short = arg.meta.short ++ .{c};
    return arg;
}
pub fn long(self: Self, s: String) Self {
    if (self.class == .posArg) {
        @compileError(comptimePrint("{} not support .long", .{self}));
    }
    var arg = self;
    arg.meta.long = arg.meta.long ++ .{s};
    return arg;
}
pub fn argName(self: Self, s: LiteralString) Self {
    if (self.class == .opt) {
        @compileError(comptimePrint("{} not support .argName", .{self}));
    }
    var arg = self;
    arg.meta.argName = s;
    return arg;
}
pub fn ranges(self: Self, rs: Ranges(Base(self.T))) Self {
    if (self.class == .opt) {
        @compileError(comptimePrint("{} not support .ranges", .{self}));
    }
    if (self.meta.rawChoices) |_| {
        @compileError(comptimePrint("{} .ranges conflicts with .rawChoices", .{self}));
    }
    var arg = self;
    arg.meta.ranges = @ptrCast(&rs._checkOut());
    return arg;
}
pub fn choices(self: Self, cs: []const Base(self.T)) Self {
    if (self.class == .opt) {
        @compileError(comptimePrint("{} not support .choices", .{self}));
    }
    if (self.meta.rawChoices) |_| {
        @compileError(comptimePrint("{} .choices conflicts with .rawChoices", .{self}));
    }
    if (cs.len == 0) {
        @compileError(comptimePrint("requires at least one choice", .{}));
    }
    var arg = self;
    arg.meta.choices = @ptrCast(&cs);
    return arg;
}
pub fn rawChoices(self: Self, cs: []const String) Self {
    if (self.class == .opt) {
        @compileError(comptimePrint("{} not support .rawChoices", .{self}));
    }
    if (self.meta.ranges != null or self.meta.choices != null) {
        @compileError(comptimePrint("{} .rawChoices conflicts with .ranges or .choices", .{self}));
    }
    if (cs.len == 0) {
        @compileError(comptimePrint("requires at least one raw_choice", .{}));
    }
    var arg = self;
    arg.meta.rawChoices = cs;
    return arg;
}

// TODO move into Command.zig?
pub fn _checkOut(self: Self) Self {
    var arg = self;
    if (self.class == .opt) {
        // Set default `default`
        if (self.meta.default == null) {
            if (self.T == bool) {
                arg.meta.default = @ptrCast(&false);
            } else {
                const zero: arg.T = 0;
                arg.meta.default = @ptrCast(&zero);
            }
        }
    }
    if (self.class == .optArg or self.class == .posArg) {
        // Set default `default`
        if (self.meta.default == null) {
            if (isOptional(self.T)) {
                const nul: arg.T = null;
                arg.meta.default = @ptrCast(&nul);
            }
        }
    }
    if (self.class == .opt or self.class == .optArg) {
        // Check short and long
        if (self.meta.short.len == 0 and self.meta.long.len == 0) {
            @compileError(comptimePrint("{} requires short or long", .{self}));
        }
    }
    if (self.class == .optArg or self.class == .posArg) {
        // Set default `argName`
        if (self.meta.argName == null) {
            arg.meta.argName = &comptimeUpperString(self.name);
        }
    }
    return arg;
}

pub fn _toField(self: Self) std.builtin.Type.StructField {
    return .{
        .alignment = @alignOf(self.T),
        .default_value_ptr = self.meta.default,
        .is_comptime = false,
        .name = self.name,
        .type = self.T,
    };
}
pub fn getRanges(self: Self) ?*const Ranges(Base(self.T)) {
    return @ptrCast(@alignCast(self.meta.ranges orelse return null));
}
pub fn getChoices(self: Self) ?*const []const Base(self.T) {
    return @ptrCast(@alignCast(self.meta.choices orelse return null));
}
fn checkInput(self: Self, s: String) bool {
    if (self.meta.rawChoices) |rcs| {
        const rcs_found = for (rcs) |rc| {
            if (equal(rc, s)) break true;
        } else false;
        if (!rcs_found) {
            self.log("to parse {s} but out of rawChoices{}", .{ s, any(rcs, .{}) });
        }
        return rcs_found;
    }
    return true;
}
fn checkValue(self: Self, value: Base(self.T)) bool {
    if (comptime self.getChoices()) |cs| {
        const cs_found = for (cs.*) |c| {
            if (equal(c, value)) break true;
        } else false;
        if (comptime self.meta.ranges) |_| {
            const rs_found = self.getRanges().?.contain(value);
            if (!cs_found and !rs_found) {
                self.log("parsed as {} but out of choices{} and ranges{}", .{ any(value, .{}), any(cs.*, .{}), any(self.getRanges().?.rs, .{}) });
            }
            return cs_found or rs_found;
        } else {
            if (!cs_found) {
                self.log("parsed as {} but out of choices{}", .{ any(value, .{}), any(cs.*, .{}) });
            }
            return cs_found;
        }
    } else {
        if (comptime self.meta.ranges) |_| {
            const rs_found = self.getRanges().?.contain(value);
            if (!rs_found) {
                self.log("parsed as {} but out of ranges{}", .{ any(value, .{}), any(self.getRanges().?.rs, .{}) });
            }
            return rs_found;
        } else {
            return true;
        }
    }
}
pub fn getParseFn(self: Self) ?*const par.Fn(self.T) {
    return @ptrCast(@alignCast(self.meta.parseFn orelse return null));
}
fn getCallbackFn(self: Self) ?*const fn (*TryOptional(self.T)) void {
    return @ptrCast(@alignCast(self.meta.callbackFn orelse return null));
}
fn parseValue(self: Self, s: String, a_maybe: ?Allocator) ?Base(self.T) {
    if (!self.checkInput(s)) return null;
    if (if (self.getParseFn()) |f| f(s, a_maybe) else par.any(Base(self.T), s, a_maybe)) |value| {
        if (!self.checkValue(value)) {
            if (a_maybe) |a| par.destroy(value, a);
            return null;
        }
        return value;
    } else {
        self.log("unable to parse {s} to {s}", .{ s, self.meta.argName.? });
        return null;
    }
}
pub fn _match(self: Self, t: token.Type) bool {
    std.debug.assert(t == .opt);
    std.debug.assert(self.class != .posArg);
    switch (t.opt) {
        .short => |c| {
            for (self.meta.short) |_c| {
                if (c == _c) return true;
            }
        },
        .long => |s| {
            for (self.meta.long) |_l| {
                if (std.mem.eql(u8, _l, s)) return true;
            }
        },
    }
    return false;
}
pub const Error = error{
    Missing,
    Invalid,
    Allocator,
};
fn consumeOpt(self: Self, r: anytype, it: *token.Iter) bool {
    if (self._match(it.viewMust() catch unreachable)) {
        _ = it.next() catch unreachable;
        if (self.T == bool) {
            @field(r, self.name) = !self._toField().defaultValue().?;
        } else {
            @field(r, self.name) += 1;
        }
        return true;
    }
    return false;
}
fn consumeOptArg(self: Self, r: anytype, it: *token.Iter, a: ?Allocator) Error!bool {
    const prefix = it.viewMust() catch unreachable;
    if (self._match(prefix)) {
        _ = it.next() catch unreachable;
        var s: String = undefined;
        if (comptime isArray(self.T)) {
            for (&@field(r, self.name), 0..) |*item, i| {
                const t = it.nextMust() catch |err| {
                    self.log("requires {s}[{d}] after {s} but {any}", .{ self.meta.argName.?, i, prefix, err });
                    return Error.Missing;
                };
                if (t != .arg) {
                    self.log("requires {s}[{d}] after {s} but {}", .{ self.meta.argName.?, i, prefix, t });
                    return Error.Missing;
                }
                s = t.arg;
                item.* = self.parseValue(s, a) orelse return Error.Invalid;
            }
        } else {
            const t = it.nextMust() catch |err| {
                self.log("requires {s} after {s} but {any}", .{ self.meta.argName.?, prefix, err });
                return Error.Missing;
            };
            s = switch (t) {
                .optArg, .arg => |arg| arg,
                else => {
                    self.log("requires {s} after {s} but {}", .{ self.meta.argName.?, prefix, t });
                    return Error.Missing;
                },
            };
            const value = self.parseValue(s, a) orelse return Error.Invalid;
            @field(r, self.name) = if (comptime isSlice(self.T)) blk: {
                if (a == null) {
                    self.log("requires allocator", .{});
                    return Error.Allocator;
                }
                var list = std.ArrayList(Base(self.T)).initCapacity(a.?, @field(r, self.name).len + 1) catch return Error.Allocator;
                list.appendSliceAssumeCapacity(@field(r, self.name));
                list.appendAssumeCapacity(value);
                a.?.free(@field(r, self.name));
                break :blk list.toOwnedSlice() catch return Error.Allocator;
            } else value;
        }
        return true;
    }
    return false;
}
fn consumePosArg(self: Self, r: anytype, it: *token.Iter, a: ?Allocator) Error!bool {
    var s: String = undefined;
    if (comptime isArray(self.T)) {
        for (&@field(r, self.name), 0..) |*item, i| {
            const t = it.nextMust() catch |err| {
                self.log("requires {s}[{d}] but {any}", .{ self.meta.argName.?, i, err });
                return Error.Missing;
            };
            s = t.as_posArg().posArg;
            item.* = self.parseValue(s, a) orelse return Error.Invalid;
        }
    } else {
        const t = it.nextMust() catch |err| {
            self.log("requires {s} but {any}", .{ self.meta.argName.?, err });
            return Error.Missing;
        };
        s = t.as_posArg().posArg;
        const value = self.parseValue(s, a) orelse return Error.Invalid;
        @field(r, self.name) = value;
    }
    return true;
}
pub fn _consume(self: Self, r: anytype, it: *token.Iter, a_maybe: ?Allocator) Error!bool {
    const consumed =
        switch (self.class) {
            .opt => self.consumeOpt(r, it),
            .optArg => try self.consumeOptArg(r, it, a_maybe),
            .posArg => try self.consumePosArg(r, it, a_maybe),
        };
    if (comptime self.getCallbackFn()) |f| {
        f(&@field(r, self.name));
    }
    return consumed;
}
pub fn _destroy(self: Self, r: anytype, a: Allocator) void {
    if (comptime isMultiple(self.T)) {
        for (@field(r, self.name)) |v| {
            par.destroy(v, a);
        }
        if (comptime isSlice(self.T)) {
            a.free(@field(r, self.name));
        }
    } else if (comptime isOptional(self.T)) {
        if (@field(r, self.name)) |v| {
            par.destroy(v, a);
        }
    } else {
        if (std.meta.eql(self._toField().defaultValue(), @field(r, self.name))) {
            return;
        }
        par.destroy(@field(r, self.name), a);
    }
}
fn formatter(self: Self, config: Config) AFormatter {
    return .init(self, config);
}
pub fn usageString(self: Self, comptime config: Config) *const [stringify(self.formatter(config), "usage").count():0]u8 {
    return stringify(self.formatter(config), "usage").literal();
}
pub fn helpString(self: Self, comptime config: Config) *const [stringify(self.formatter(config), "help").count():0]u8 {
    return stringify(self.formatter(config), "help").literal();
}

test "Compile Errors" {
    // TODO https://github.com/ziglang/zig/issues/513
    return error.SkipZigTest;
}
test "Check out" {
    {
        const arg = Self.opt("out", bool).short('o')._checkOut();
        try testing.expectEqual(false, arg._toField().defaultValue());
    }
    {
        const arg = Self.opt("out", u32).short('o')._checkOut();
        try testing.expectEqual(0, arg._toField().defaultValue());
    }
    {
        const arg = Self.optArg("out", u32).short('o')._checkOut();
        try testing.expectEqualStrings("OUT", arg.meta.argName.?);
    }
    {
        const arg = Self.posArg("out", u32)._checkOut();
        try testing.expectEqualStrings("OUT", arg.meta.argName.?);
    }
}
test "Match prefix" {
    {
        const arg = Self.opt("out", bool).short('o').long("out")._checkOut();
        try testing.expect(arg._match(.{ .opt = .{ .short = 'o' } }));
        try testing.expect(!arg._match(.{ .opt = .{ .short = 'i' } }));
        try testing.expect(arg._match(.{ .opt = .{ .long = "out" } }));
        try testing.expect(!arg._match(.{ .opt = .{ .long = "input" } }));
    }
    {
        const arg = Self.optArg("out", bool).short('o').long("out").long("output")._checkOut();
        try testing.expect(arg._match(.{ .opt = .{ .short = 'o' } }));
        try testing.expect(!arg._match(.{ .opt = .{ .short = 'i' } }));
        try testing.expect(arg._match(.{ .opt = .{ .long = "out" } }));
        try testing.expect(arg._match(.{ .opt = .{ .long = "output" } }));
        try testing.expect(!arg._match(.{ .opt = .{ .long = "input" } }));
    }
}
test "Consume opt" {
    const R = struct { out: bool, verbose: u32 };
    var r = std.mem.zeroes(R);
    var it = try token.Iter.initList(&.{ "--out", "-v", "-v", "--out", "-t" }, .{});
    const meta_out = Self.opt("out", bool).long("out")._checkOut();
    const meta_verbose = Self.opt("verbose", u32).short('v')._checkOut();
    try testing.expect(meta_out.consumeOpt(&r, &it));
    try testing.expect(!meta_out.consumeOpt(&r, &it));
    try testing.expect(meta_verbose.consumeOpt(&r, &it));
    try testing.expect(meta_verbose.consumeOpt(&r, &it));
    try testing.expect(meta_out.consumeOpt(&r, &it));
    try testing.expectEqual(R{ .out = true, .verbose = 2 }, r);
}
test "Consume optArg" {
    const R = struct { out: bool, verbose: u32, files: []const String, twins: [2]u32, point: @Vector(2, i32) };
    var r = std.mem.zeroes(R);
    const meta_out = Self.optArg("out", bool).long("out")._checkOut();
    const meta_verbose = Self.optArg("verbose", u32).short('v')._checkOut();
    const meta_files = Self.optArg("files", []const String).short('f')._checkOut();
    const meta_twins = Self.optArg("twins", [2]u32).short('t')._checkOut();
    const meta_point = Self.optArg("point", @Vector(2, i32)).short('p')._checkOut();

    {
        var it = try token.Iter.initList(&.{"--out"}, .{});
        try testing.expect(!try meta_verbose.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"--out"}, .{});
        try testing.expectError(Error.Missing, meta_out.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{ "--out", "-v=0xf" }, .{});
        try testing.expectError(Error.Missing, meta_out.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"-v=a"}, .{});
        try testing.expectError(Error.Invalid, meta_verbose.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"-f=bin"}, .{});
        try testing.expectError(Error.Allocator, meta_files.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"-t"}, .{});
        try testing.expectError(Error.Missing, meta_twins.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"-t=a"}, .{});
        try testing.expectError(Error.Missing, meta_twins.consumeOptArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{ "-t", "a" }, .{});
        try testing.expectError(Error.Invalid, meta_twins.consumeOptArg(&r, &it, null));
    }
    {
        var res = std.mem.zeroes(R);
        var it = try token.Iter.initList(
            &.{ "--out", "n", "-v=1", "-f", "bin0", "-t", "1", "2", "-f=bin1", "-p", "[1;2]" },
            .{},
        );
        try testing.expect(try meta_out.consumeOptArg(&res, &it, null));
        try testing.expect(try meta_verbose.consumeOptArg(&res, &it, null));
        try testing.expect(try meta_files.consumeOptArg(&res, &it, testing.allocator));
        try testing.expect(try meta_twins.consumeOptArg(&res, &it, null));
        try testing.expect(try meta_files.consumeOptArg(&res, &it, testing.allocator));
        try testing.expect(try meta_point.consumeOptArg(&res, &it, null));
        defer meta_files._destroy(&res, testing.allocator);
        try testing.expectEqualDeep(R{
            .out = false,
            .verbose = 1,
            .files = &.{ "bin0", "bin1" },
            .twins = [2]u32{ 1, 2 },
            .point = .{ 1, 2 },
        }, res);
    }
}
test "Consume optArg with both ranges and choices" {
    const R = struct { int: []i32 };
    const arg = Self.optArg("int", []i32).short('i');
    {
        const meta_int = arg.choices(&.{ 3, 5, 7 }).ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initLine("-i=-1 -i 3 -i 5 -i=23", null, .{});
        try testing.expect(try meta_int.consumeOptArg(&r, &it, testing.allocator));
        try testing.expect(try meta_int.consumeOptArg(&r, &it, testing.allocator));
        try testing.expect(try meta_int.consumeOptArg(&r, &it, testing.allocator));
        try testing.expect(try meta_int.consumeOptArg(&r, &it, testing.allocator));
        try testing.expectEqualDeep(&[_]i32{ -1, 3, 5, 23 }, r.int);
        meta_int._destroy(r, testing.allocator);
    }
    {
        const meta_int = arg.choices(&.{ 3, 5, 7 }).ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initLine("-i 6", null, .{});
        try testing.expectError(Error.Invalid, meta_int.consumeOptArg(&r, &it, testing.allocator));
    }
    {
        const meta_int = arg.ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initLine("-i 6", null, .{});
        try testing.expectError(Error.Invalid, meta_int.consumeOptArg(&r, &it, testing.allocator));
    }
    {
        const meta_int = arg.choices(&.{ 3, 5, 7 })._checkOut();
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initLine("-i 6", null, .{});
        try testing.expectError(Error.Invalid, meta_int.consumeOptArg(&r, &it, testing.allocator));
    }
}
test "Consume posArg" {
    const R = struct { out: bool, twins: [2]u32 };
    var r = std.mem.zeroes(R);
    const meta_out = Self.posArg("out", bool)._checkOut();
    const meta_twins = Self.posArg("twins", [2]u32)._checkOut();

    {
        var it = try token.Iter.initList(&.{}, .{});
        try testing.expectError(Error.Missing, meta_out.consumePosArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"a"}, .{});
        try testing.expectError(Error.Invalid, meta_out.consumePosArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{"1"}, .{});
        try testing.expectError(Error.Missing, meta_twins.consumePosArg(&r, &it, null));
    }
    {
        var it = try token.Iter.initList(&.{ "1", "a" }, .{});
        try testing.expectError(Error.Invalid, meta_twins.consumePosArg(&r, &it, null));
    }
    {
        var res = std.mem.zeroes(R);
        var it = try token.Iter.initList(&.{ "n", "1", "2" }, .{});
        try testing.expect(try meta_out.consumePosArg(&res, &it, null));
        try testing.expect(try meta_twins.consumePosArg(&res, &it, null));
        try testing.expectEqualDeep(R{ .out = false, .twins = [2]u32{ 1, 2 } }, res);
    }
}
test "Consume posArg with ranges or rawChoices" {
    const Mem = struct {
        buf: []u8 = undefined,
        len: usize,
        pub fn parse(s: String, a: ?Allocator) ?@This() {
            const allocator = a orelse return null;
            const len = @import("par").any(usize, s, null) orelse return null;
            const buf = allocator.alloc(u8, len) catch return null;
            return .{ .buf = buf, .len = len };
        }
        pub fn destroy(self: @This(), a: Allocator) void {
            a.free(self.buf);
        }
        pub fn compare(self: @This(), v: @This()) helper.Compare.Order {
            return helper.Compare.compare(self.len, v.len);
        }
    };
    const R = struct { mem: Mem };
    const arg = Self.posArg("mem", Mem);
    {
        const meta_mem = arg.ranges(Ranges(Mem).new().u(null, Mem{ .len = 5 }))._checkOut();
        var r = std.mem.zeroes(R);
        {
            var it = try token.Iter.initList(&.{"3"}, .{});
            try testing.expect(try meta_mem.consumePosArg(&r, &it, testing.allocator));
            try testing.expectEqual(3, r.mem.len);
            try testing.expectEqual(3, r.mem.buf.len);
            meta_mem._destroy(r, testing.allocator);
        }
        {
            var it = try token.Iter.initList(&.{"8"}, .{});
            try testing.expectError(
                Error.Invalid,
                meta_mem.consumePosArg(&r, &it, testing.allocator),
            );
        }
    }
    {
        const meta_mem = arg.rawChoices(&.{ "1", "2", "3", "16" })._checkOut();
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initList(&.{"32"}, .{});
        try testing.expectError(
            Error.Invalid,
            meta_mem.consumePosArg(&r, &it, testing.allocator),
        );
    }
}
test "Consume posArg with choices" {
    const R = struct { out: String };
    var r = std.mem.zeroes(R);
    const meta_out = Self.posArg("out", String).choices(&.{ "install", "remove" })._checkOut();
    {
        var it = try token.Iter.initList(&.{"remove"}, .{});
        try testing.expect(try meta_out.consumePosArg(&r, &it, testing.allocator));
        try testing.expectEqualStrings("remove", r.out);
        meta_out._destroy(r, testing.allocator);
    }
    {
        var it = try token.Iter.initList(&.{"update"}, .{});
        try testing.expectError(Error.Invalid, meta_out.consumePosArg(&r, &it, testing.allocator));
    }
}
