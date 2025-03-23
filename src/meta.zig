const std = @import("std");
const testing = std.testing;
const helper = @import("helper.zig");
const print = helper.Alias.print;
const String = helper.Alias.String;

const FormatHelper = struct {
    pub fn opt(short: ?u8, long: ?[]const u8) []const u8 {
        var usage: []const u8 = "";
        if (short) |s| {
            usage = print("-{c}", .{s});
        }
        if (short != null and long != null) {
            usage = print("{s}|", .{usage});
        }
        if (long) |l| {
            usage = print("{s}--{s}", .{ usage, l });
        }
        return usage;
    }
    pub fn arg(name: []const u8, T: type) []const u8 {
        const pre = switch (@typeInfo(T)) {
            .array => |info| print("[{d}]", .{info.len}),
            .pointer => if (T == String) "" else "[]",
            else => "",
        };
        return print("{{{s}{s}}}", .{ pre, name });
    }
    pub fn optional(has_default: bool, u: []const u8) []const u8 {
        return if (has_default) print("[{s}]", .{u}) else u;
    }
    test opt {
        try testing.expectEqualStrings("-o", comptime opt('o', null));
        try testing.expectEqualStrings("--out", comptime opt(null, "out"));
        try testing.expectEqualStrings("-o|--out", comptime opt('o', "out"));
    }
    test arg {
        try testing.expectEqualStrings("{OUT}", comptime arg("OUT", u32));
        try testing.expectEqualStrings("{[2]OUT}", comptime arg("OUT", [2]u32));
        try testing.expectEqualStrings("{[]OUT}", comptime arg("OUT", []const u32));
    }
    test optional {
        try testing.expectEqualStrings("usage", comptime optional(false, "usage"));
        try testing.expectEqualStrings("[usage]", comptime optional(true, "usage"));
    }
};

pub const Meta = struct {
    const token = @import("token.zig");
    const parser = @import("parser.zig");
    const Allocator = std.mem.Allocator;
    const Base = helper.Type.Base;
    const isSlice = helper.Type.isSlice;
    const isOptional = helper.Type.isOptional;
    const isArray = helper.Type.isArray;
    const isMultiple = helper.Type.isMultiple;
    const TryOptional = helper.Type.TryOptional;
    const TryMultiple = helper.Type.TryMultiple;
    const NiceFormatter = helper.NiceFormatter;
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

    pub fn format(self: Self, comptime _: []const u8, _: helper.Alias.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll(print("{s}({s},{s})", .{ @tagName(self.class), self.name, @typeName(self.T) }));
    }
    fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(print("{} {s}\n", .{ self, fmt }), args);
    }

    pub fn opt(name: [:0]const u8, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .opt };
        // Check T
        if (T != bool and @typeInfo(T) != .int) {
            @compileError(print("{} illegal type, expect .bool or .int", .{meta}));
        }
        // Initialize Meta
        return meta;
    }
    pub fn optArg(name: [:0]const u8, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .optArg };
        // Check T
        _ = Base(T);
        // Initialize Meta
        return meta;
    }
    pub fn posArg(name: [:0]const u8, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .posArg };
        // Check T
        _ = Base(T);
        if (isSlice(T)) {
            @compileError(print("{} illegal type, consider to use .nextAllBase of TokenIter", .{meta}));
        }
        // Initialize Meta
        return meta;
    }
    pub fn help(self: Self, s: []const u8) Self {
        var meta = self;
        meta.common.help = s;
        return meta;
    }
    pub fn default(self: Self, v: self.T) Self {
        if (isOptional(self.T)) {
            @compileError(print("{} not support .default, it's forced to be null", .{self}));
        }
        if (isSlice(self.T)) {
            @compileError(print("{} not support .default, it's forced to be empty slice", .{self}));
        }
        var meta = self;
        meta.common.default = @ptrCast(&v);
        return meta;
    }
    pub fn parseFn(self: Self, f: parser.Fn(self.T)) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .parseFn", .{self}));
        }
        var meta = self;
        meta.common.parseFn = @ptrCast(&f);
        return meta;
    }
    pub fn callBackFn(self: Self, f: fn (*TryOptional(self.T)) void) Self {
        var meta = self;
        meta.common.callBackFn = @ptrCast(&f);
        return meta;
    }
    pub fn short(self: Self, c: u8) Self {
        if (self.class == .posArg) {
            @compileError(print("{} not support .short", .{self}));
        }
        var meta = self;
        meta.common.short = c;
        return meta;
    }
    pub fn long(self: Self, s: []const u8) Self {
        if (self.class == .posArg) {
            @compileError(print("{} not support .long", .{self}));
        }
        var meta = self;
        meta.common.long = s;
        return meta;
    }
    pub fn argName(self: Self, s: []const u8) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .argName", self));
        }
        var meta = self;
        meta.common.argName = s;
        return meta;
    }

    pub fn _checkOut(self: Self) Self {
        var meta = self;
        if (self.class == .opt) {
            // Set default `default`
            if (self.common.default == null) {
                if (self.T == bool) {
                    meta.common.default = @ptrCast(&false);
                } else {
                    const zero: meta.T = 0;
                    meta.common.default = @ptrCast(&zero);
                }
            }
        }
        if (self.class == .optArg or self.class == .posArg) {
            // Set default `default`
            if (self.common.default == null) {
                if (isOptional(self.T)) {
                    const nul: meta.T = null;
                    meta.common.default = @ptrCast(&nul);
                }
            }
        }
        if (self.class == .opt or self.class == .optArg) {
            // Check short and long
            if (self.common.short == null and self.common.long == null) {
                @compileError(print("{} requires short or long", .{self}));
            }
        }
        if (self.class == .optArg or self.class == .posArg) {
            // Set default `argName`
            if (self.common.argName == null) {
                meta.common.argName = &helper.upper(self.name);
            }
        }
        return meta;
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
    fn _parseAny(self: Self, s: String, a: ?Allocator) ?Base(self.T) {
        if (self.common.parseFn) |f| {
            const p: *const parser.Fn(self.T) = @ptrCast(@alignCast(f));
            return p(s, a);
        }
        return parser.parseAny(Base(self.T), s, a);
    }
    pub fn _destroy(self: Self, r: anytype, a: Allocator) void {
        if (comptime isMultiple(self.T)) {
            for (@field(r, self.name)) |v| {
                parser.destroyAny(TryMultiple(self.T), v, a);
            }
            if (comptime isSlice(self.T)) {
                a.free(@field(r, self.name));
            }
        } else if (comptime isOptional(self.T)) {
            if (@field(r, self.name)) |v| {
                parser.destroyAny(TryOptional(self.T), v, a);
            }
        } else {
            parser.destroyAny(self.T, @field(r, self.name), a);
        }
    }
    pub fn _match(self: Self, t: token.Type) bool {
        std.debug.assert(t == .opt);
        std.debug.assert(self.class != .posArg);
        switch (t.opt) {
            .short => |c| {
                if (c == self.common.short) return true;
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
        const FH = FormatHelper;
        return switch (self.class) {
            .opt => print("{s}{s}", .{
                FH.optional(true, FH.opt(self.common.short, self.common.long)),
                if (self.T == bool) "" else "...",
            }),
            .optArg => print("{s}{s}", .{
                FH.optional(
                    self.common.default != null,
                    print("{s} {s}", .{
                        FH.opt(self.common.short, self.common.long),
                        FH.arg(self.common.argName.?, self.T),
                    }),
                ),
                if (isSlice(self.T)) "..." else "",
            }),
            .posArg => FH.optional(
                self.common.default != null,
                FH.arg(self.common.argName.?, self.T),
            ),
        };
    }
    pub fn _help(self: Self) []const u8 {
        var msg: []const u8 = self._usage();
        if (self.common.help == null and self.common.default == null) {
            return msg;
        }
        const space: usize = @max(24, helper.alignIntUp(usize, msg.len, 4) + 4);
        msg = print("{s}{s}", .{ msg, " " ** (space - msg.len) });
        if (self.common.help) |s| {
            msg = print("{s}{s}", .{ msg, s });
        }
        if (self.common.default) |_| {
            msg = print("{s}{s}(default: {s})", .{
                msg,
                if (self.common.help) |_| "\n" ++ " " ** space else "",
                NiceFormatter(self.T).value(self._toField().defaultValue().?),
            });
        }
        return msg;
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
                @field(r, self.name) = !self._toField().defaultValue().?;
            } else {
                @field(r, self.name) += 1;
            }
            return true;
        }
        return false;
    }
    fn _consumeOptArg(self: Self, r: anytype, it: *token.Iter, a: ?Allocator) Error!bool {
        const prefix = it.viewMust() catch unreachable;
        if (self._match(prefix)) {
            _ = it.next() catch unreachable;
            var s: String = undefined;
            if (comptime isArray(self.T)) {
                for (&@field(r, self.name), 0..) |*item, i| {
                    const t = it.nextMust() catch |err| {
                        self.log("requires {s}[{d}] after {s} but {any}", .{ self.common.argName.?, i, prefix, err });
                        return Error.Missing;
                    };
                    if (t != .arg) {
                        self.log("requires {s}[{d}] after {s} but {}", .{ self.common.argName.?, i, prefix, t });
                        return Error.Missing;
                    }
                    s = t.arg;
                    item.* = self._parseAny(s, a) orelse {
                        self.log("unable to parse {s} to {s}[{d}]", .{ s, self.common.argName.?, i });
                        return Error.Invalid;
                    };
                }
            } else {
                const t = it.nextMust() catch |err| {
                    self.log("requires {s} after {s} but {any}", .{ self.common.argName.?, prefix, err });
                    return Error.Missing;
                };
                s = switch (t) {
                    .optArg, .arg => |arg| arg,
                    else => {
                        self.log("requires {s} after {s} but {}", .{ self.common.argName.?, prefix, t });
                        return Error.Missing;
                    },
                };
                const value = self._parseAny(s, a) orelse {
                    self.log("unable to parse {s} to {s}", .{ s, self.common.argName.? });
                    return Error.Invalid;
                };
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
    fn _consumePosArg(self: Self, r: anytype, it: *token.Iter, a: ?Allocator) Error!bool {
        var s: String = undefined;
        if (comptime isArray(self.T)) {
            for (&@field(r, self.name), 0..) |*item, i| {
                const t = it.nextMust() catch |err| {
                    self.log("requires {s}[{d}] but {any}", .{ self.common.argName.?, i, err });
                    return Error.Missing;
                };
                s = t.as_posArg().posArg;
                item.* = self._parseAny(s, a) orelse {
                    self.log("unable to parse {s} to {s}[{d}]", .{ s, self.common.argName.?, i });
                    return Error.Invalid;
                };
            }
        } else {
            const t = it.nextMust() catch |err| {
                self.log("requires {s} but {any}", .{ self.common.argName.?, err });
                return Error.Missing;
            };
            s = t.as_posArg().posArg;
            const value = self._parseAny(s, a) orelse {
                self.log("unable to parse {s} to {s}", .{ s, self.common.argName.? });
                return Error.Invalid;
            };
            @field(r, self.name) = value;
        }
        return true;
    }
    pub fn _consume(self: Self, r: anytype, it: *token.Iter, a: ?Allocator) Error!bool {
        const consumed =
            switch (self.class) {
                .opt => self._consumeOpt(r, it),
                .optArg => try self._consumeOptArg(r, it, a),
                .posArg => try self._consumePosArg(r, it, a),
            };
        if (self.common.callBackFn) |f| {
            const p: *const fn (*self.T) void = @ptrCast(@alignCast(f));
            p(&@field(r, self.name));
        }
        return consumed;
    }

    test "Compile Errors" {
        // TODO https://github.com/ziglang/zig/issues/513
        return error.SkipZigTest;
    }

    test "Check out" {
        {
            const meta = Self.opt("out", bool).short('o')._checkOut();
            try testing.expectEqual(false, meta._toField().defaultValue());
        }
        {
            const meta = Self.opt("out", u32).short('o')._checkOut();
            try testing.expectEqual(0, meta._toField().defaultValue());
        }
        {
            const meta = Self.optArg("out", u32).short('o')._checkOut();
            try testing.expectEqualStrings("OUT", meta.common.argName.?);
        }
        {
            const meta = Self.posArg("out", u32)._checkOut();
            try testing.expectEqualStrings("OUT", meta.common.argName.?);
        }
    }

    test "Match prefix" {
        {
            const meta = Self.opt("out", bool).short('o').long("out")._checkOut();
            try testing.expect(meta._match(.{ .opt = .{ .short = 'o' } }));
            try testing.expect(!meta._match(.{ .opt = .{ .short = 'i' } }));
            try testing.expect(meta._match(.{ .opt = .{ .long = "out" } }));
            try testing.expect(!meta._match(.{ .opt = .{ .long = "input" } }));
        }
        {
            const meta = Self.optArg("out", bool).short('o').long("out")._checkOut();
            try testing.expect(meta._match(.{ .opt = .{ .short = 'o' } }));
            try testing.expect(!meta._match(.{ .opt = .{ .short = 'i' } }));
            try testing.expect(meta._match(.{ .opt = .{ .long = "out" } }));
            try testing.expect(!meta._match(.{ .opt = .{ .long = "input" } }));
        }
    }

    test "Format usage" {
        {
            try testing.expectEqualStrings("[-o]", comptime Self.opt("out", bool).short('o')._usage());
            try testing.expectEqualStrings("[-o]...", comptime Self.opt("out", u32).short('o')._usage());
        }
        {
            try testing.expectEqualStrings(
                "-o {OUT}",
                comptime Self.optArg("out", bool).short('o')._checkOut()._usage(),
            );
            try testing.expectEqualStrings(
                "[-o {OUT}]",
                comptime Self.optArg("out", bool).short('o').default(false)._checkOut()._usage(),
            );
            try testing.expectEqualStrings(
                "[-o {OUT}]",
                comptime Self.optArg("out", ?bool).short('o')._checkOut()._usage(),
            );
            try testing.expectEqualStrings(
                "-o {[2]OUT}",
                comptime Self.optArg("out", [2]u32).short('o')._checkOut()._usage(),
            );
            try testing.expectEqualStrings(
                "-o {[]OUT}...",
                comptime Self.optArg("out", []const u32).short('o')._checkOut()._usage(),
            );
        }
        {
            try testing.expectEqualStrings("{[2]OUT}", comptime Self.posArg("out", [2]u32)._checkOut()._usage());
            try testing.expectEqualStrings("[{OUT}]", comptime Self.posArg("out", u32).default(1)._checkOut()._usage());
        }
    }

    test "Format help" {
        {
            try testing.expectEqualStrings(
                \\[-o]                    Help of out
                \\                        (default: false)
            ,
                comptime Self.opt("out", bool)
                    .short('o').help("Help of out")
                    ._checkOut()._help(),
            );
        }
        {
            try testing.expectEqualStrings(
                \\-o {OUT}                Help of out
            ,
                comptime Self.optArg("out", String)
                    .short('o').help("Help of out")
                    ._checkOut()._help(),
            );
        }
        {
            try testing.expectEqualStrings(
                \\[-o|--out {OUT}]        Help of out
                \\                        (default: a.out)
            ,
                comptime Self.optArg("out", String)
                    .short('o').long("out")
                    .default("a.out")
                    .help("Help of out")
                    ._checkOut()._help(),
            );
        }
        {
            const Color = enum { Red, Green, Blue };
            try testing.expectEqualStrings(
                \\[-c|--color {[3]COLORS}]    Help of colors
                \\                            (default: {Red, Green, Blue})
            ,
                comptime Self.optArg("colors", [3]Color)
                    .short('c').long("color")
                    .default([_]Color{ .Red, .Green, .Blue })
                    .help("Help of colors")
                    ._checkOut()._help(),
            );
        }
    }

    test "Consume opt" {
        const R = struct { out: bool, verbose: u32 };
        var r = std.mem.zeroes(R);
        var it = try token.Iter.initList(&[_]String{ "--out", "-v", "-v", "--out", "-t" }, .{});
        const meta_out = Self.opt("out", bool).long("out")._checkOut();
        const meta_verbose = Self.opt("verbose", u32).short('v')._checkOut();
        try testing.expect(meta_out._consumeOpt(&r, &it));
        try testing.expect(!meta_out._consumeOpt(&r, &it));
        try testing.expect(meta_verbose._consumeOpt(&r, &it));
        try testing.expect(meta_verbose._consumeOpt(&r, &it));
        try testing.expect(meta_out._consumeOpt(&r, &it));
        try testing.expectEqual(R{ .out = true, .verbose = 2 }, r);
    }

    test "Consume optArg" {
        const R = struct { out: bool, verbose: u32, files: []const String, twins: [2]u32 };
        var r = std.mem.zeroes(R);
        const meta_out = Self.optArg("out", bool).long("out")._checkOut();
        const meta_verbose = Self.optArg("verbose", u32).short('v')._checkOut();
        const meta_files = Self.optArg("files", []const String).short('f')._checkOut();
        const meta_twins = Self.optArg("twins", [2]u32).short('t')._checkOut();

        {
            var it = try token.Iter.initList(&[_]String{"--out"}, .{});
            try testing.expect(!try meta_verbose._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"--out"}, .{});
            try testing.expectError(Error.Missing, meta_out._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{ "--out", "-v=0xf" }, .{});
            try testing.expectError(Error.Missing, meta_out._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"-v=a"}, .{});
            try testing.expectError(Error.Invalid, meta_verbose._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"-f=bin"}, .{});
            try testing.expectError(Error.Allocator, meta_files._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"-t"}, .{});
            try testing.expectError(Error.Missing, meta_twins._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"-t=a"}, .{});
            try testing.expectError(Error.Missing, meta_twins._consumeOptArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{ "-t", "a" }, .{});
            try testing.expectError(Error.Invalid, meta_twins._consumeOptArg(&r, &it, null));
        }
        {
            var res = std.mem.zeroes(R);
            var it = try token.Iter.initList(
                &[_]String{ "--out", "n", "-v=1", "-f", "bin0", "-t", "1", "2", "-f=bin1" },
                .{},
            );
            try testing.expect(try meta_out._consumeOptArg(&res, &it, null));
            try testing.expect(try meta_verbose._consumeOptArg(&res, &it, null));
            try testing.expect(try meta_files._consumeOptArg(&res, &it, testing.allocator));
            try testing.expect(try meta_twins._consumeOptArg(&res, &it, null));
            try testing.expect(try meta_files._consumeOptArg(&res, &it, testing.allocator));
            defer meta_files._destroy(&res, testing.allocator);
            try testing.expectEqualDeep(R{
                .out = false,
                .verbose = 1,
                .files = &[_]String{ "bin0", "bin1" },
                .twins = [2]u32{ 1, 2 },
            }, res);
        }
    }

    test "Consume posArg" {
        const R = struct { out: bool, twins: [2]u32 };
        var r = std.mem.zeroes(R);
        const meta_out = Self.posArg("out", bool)._checkOut();
        const meta_twins = Self.posArg("twins", [2]u32)._checkOut();

        {
            var it = try token.Iter.initList(&[_]String{}, .{});
            try testing.expectError(Error.Missing, meta_out._consumePosArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"a"}, .{});
            try testing.expectError(Error.Invalid, meta_out._consumePosArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{"1"}, .{});
            try testing.expectError(Error.Missing, meta_twins._consumePosArg(&r, &it, null));
        }
        {
            var it = try token.Iter.initList(&[_]String{ "1", "a" }, .{});
            try testing.expectError(Error.Invalid, meta_twins._consumePosArg(&r, &it, null));
        }
        {
            var res = std.mem.zeroes(R);
            var it = try token.Iter.initList(&[_]String{ "n", "1", "2" }, .{});
            try testing.expect(try meta_out._consumePosArg(&res, &it, null));
            try testing.expect(try meta_twins._consumePosArg(&res, &it, null));
            try testing.expectEqualDeep(R{ .out = false, .twins = [2]u32{ 1, 2 } }, res);
        }
    }
};

test {
    _ = FormatHelper;
    _ = Meta;
}
