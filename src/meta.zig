const std = @import("std");
const testing = std.testing;
const helper = @import("helper.zig");
const print = helper.Alias.print;
const String = helper.Alias.String;
const LiteralString = helper.Alias.LiteralString;
const Prefix = helper.Config.Prefix;

const FormatHelper = struct {
    pub fn opt(short: ?u8, long: ?String, prefix: Prefix) []const u8 {
        var usage: []const u8 = "";
        if (short) |s| {
            usage = print("{s}{c}", .{ prefix.short, s });
        }
        if (short != null and long != null) {
            usage = print("{s}|", .{usage});
        }
        if (long) |l| {
            usage = print("{s}{s}{s}", .{ usage, prefix.long, l });
        }
        return usage;
    }
    pub fn arg(name: LiteralString, T: type) []const u8 {
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

    const _test = struct {
        test opt {
            try testing.expectEqualStrings("-o", comptime opt('o', null, .{}));
            try testing.expectEqualStrings("--out", comptime opt(null, "out", .{}));
            try testing.expectEqualStrings("-o|--out", comptime opt('o', "out", .{}));
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
};

pub fn Ranges(T: type) type {
    const Range = helper.Collection.Range(T);
    return struct {
        const Self = @This();
        rs: []const Range = &.{},
        pub fn new() Self {
            return .{};
        }
        pub fn u(self: Self, l: ?T, r: ?T) Self {
            const range = Range.init(l, r);
            if (range.is_empty() or range.is_universal()) {
                @compileError(print("mustn't union range {}", .{r}));
            }
            var ranges = self;
            ranges.rs = ranges.rs ++ [_]Range{range};
            return ranges;
        }
        pub fn _checkOut(self: Self) Self {
            if (self.rs.len == 0) {
                @compileError(print("requires to union at least one range", .{}));
            }
            // TODO: Merge ranges
            return self;
        }
        pub fn contain(self: Self, v: T) bool {
            for (self.rs) |r| {
                if (r.contain(v)) return true;
            }
            return false;
        }
    };
}

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
    const nice = helper.Formatter.nice;
    const equal = helper.Compare.equal;
    const Self = @This();

    name: LiteralString,
    T: type,
    class: Class,
    common: Common = .{},

    const Common = struct {
        help: ?LiteralString = null,
        default: ?*const anyopaque = null,
        parseFn: ?*const anyopaque = null, // optArg, posArg
        callBackFn: ?*const anyopaque = null,
        short: []const u8 = &.{}, // opt, optArg
        long: []const String = &.{}, // opt, optArg
        argName: ?LiteralString = null, // optArg, posArg
        ranges: ?*const anyopaque = null, // optArg, posArg
        choices: ?*const anyopaque = null, // optArg, posArg
        raw_choices: ?[]const String = null, // optArg, posArg
    };
    const Class = enum { opt, optArg, posArg };

    pub fn format(self: Self, comptime _: []const u8, _: helper.Alias.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll(print("{s}({s},{s})", .{ @tagName(self.class), self.name, @typeName(self.T) }));
    }
    fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(print("{} {s}\n", .{ self, fmt }), args);
    }

    pub fn opt(name: LiteralString, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .opt };
        // Check T
        if (T != bool and @typeInfo(T) != .int) {
            @compileError(print("{} illegal type, expect .bool or .int", .{meta}));
        }
        // Initialize Meta
        return meta;
    }
    pub fn optArg(name: LiteralString, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .optArg };
        // Check T
        _ = Base(T);
        // Initialize Meta
        return meta;
    }
    pub fn posArg(name: LiteralString, T: type) Self {
        const meta: Self = .{ .name = name, .T = T, .class = .posArg };
        // Check T
        _ = Base(T);
        if (isSlice(T)) {
            @compileError(print("{} illegal type, consider to use .nextAllBase of TokenIter", .{meta}));
        }
        // Initialize Meta
        return meta;
    }
    pub fn help(self: Self, s: LiteralString) Self {
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
        meta.common.short = meta.common.short ++ [_]u8{c};
        return meta;
    }
    pub fn long(self: Self, s: String) Self {
        if (self.class == .posArg) {
            @compileError(print("{} not support .long", .{self}));
        }
        var meta = self;
        meta.common.long = meta.common.long ++ [_]String{s};
        return meta;
    }
    pub fn argName(self: Self, s: LiteralString) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .argName", .{self}));
        }
        var meta = self;
        meta.common.argName = s;
        return meta;
    }
    pub fn ranges(self: Self, rs: Ranges(Base(self.T))) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .ranges", .{self}));
        }
        if (self.common.raw_choices) |_| {
            @compileError(print("{} .ranges conflicts with .raw_choices", .{self}));
        }
        var meta = self;
        meta.common.ranges = @ptrCast(&rs._checkOut());
        return meta;
    }
    pub fn choices(self: Self, cs: []const Base(self.T)) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .choices", .{self}));
        }
        if (self.common.raw_choices) |_| {
            @compileError(print("{} .choices conflicts with .raw_choices", .{self}));
        }
        if (cs.len == 0) {
            @compileError(print("requires at least one choice", .{}));
        }
        var meta = self;
        meta.common.choices = @ptrCast(&cs);
        return meta;
    }
    pub fn raw_choices(self: Self, cs: []const String) Self {
        if (self.class == .opt) {
            @compileError(print("{} not support .raw_choices", .{self}));
        }
        if (self.common.ranges != null or self.common.choices != null) {
            @compileError(print("{} .raw_choices conflicts with .ranges or .choices", .{self}));
        }
        if (cs.len == 0) {
            @compileError(print("requires at least one raw_choice", .{}));
        }
        var meta = self;
        meta.common.raw_choices = cs;
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
            if (self.common.short.len == 0 and self.common.long.len == 0) {
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
    fn _ranges(self: Self) ?*const Ranges(Base(self.T)) {
        return if (self.common.ranges) |opa| @ptrCast(@alignCast(opa)) else null;
    }
    fn _choices(self: Self) ?*const []const Base(self.T) {
        return if (self.common.choices) |opa| @ptrCast(@alignCast(opa)) else null;
    }
    fn _checkValue(self: Self, value: Base(self.T)) bool {
        if (comptime self._choices()) |cs| {
            const cs_found = for (cs.*) |c| {
                if (equal(c, value)) break true;
            } else false;
            if (comptime self._ranges()) |rs| {
                const rs_found = rs.contain(value);
                if (!cs_found and !rs_found) {
                    self.log("parsed as {} but out of choices{} and ranges{}", .{ nice(value), nice(cs.*), nice(rs.rs) });
                }
                return cs_found or rs_found;
            } else {
                if (!cs_found) {
                    self.log("parsed as {} but out of choices{}", .{ nice(value), nice(cs.*) });
                }
                return cs_found;
            }
        } else {
            if (comptime self._ranges()) |rs| {
                const rs_found = rs.contain(value);
                if (!rs_found) {
                    self.log("parsed as {} but out of ranges{}", .{ nice(value), nice(rs.rs) });
                }
                return rs_found;
            } else {
                return true;
            }
        }
    }
    fn _parseAny(self: Self, s: String, a: ?Allocator) ?Base(self.T) {
        if (self.common.raw_choices) |rcs| {
            const rcs_found = for (rcs) |rc| {
                if (equal(rc, s)) break true;
            } else false;
            if (!rcs_found) {
                self.log("to parse {s} but out of raw_choices{}", .{ s, nice(rcs) });
                return null;
            }
        }
        if (if (self.common.parseFn) |f| blk: {
            const p: *const parser.Fn(self.T) = @ptrCast(@alignCast(f));
            break :blk p(s, a);
        } else parser.parseAny(Base(self.T), s, a)) |value| {
            if (!self._checkValue(value)) {
                if (a) |_| parser.destroyAny(value, a.?);
                return null;
            }
            return value;
        } else {
            self.log("unable to parse {s} to {s}", .{ s, self.common.argName.? });
            return null;
        }
    }
    pub fn _match(self: Self, t: token.Type) bool {
        std.debug.assert(t == .opt);
        std.debug.assert(self.class != .posArg);
        switch (t.opt) {
            .short => |c| {
                for (self.common.short) |_c| {
                    if (c == _c) return true;
                }
            },
            .long => |s| {
                for (self.common.long) |_l| {
                    if (std.mem.eql(u8, _l, s)) return true;
                }
            },
        }
        return false;
    }
    pub fn _usage(self: Self, prefix: Prefix) []const u8 {
        const FH = FormatHelper;
        const _short = self.common.short;
        const main_short = if (_short.len == 0) null else _short[0];
        const _long = self.common.long;
        const main_long = if (_long.len == 0) null else _long[0];
        return switch (self.class) {
            .opt => print("{s}{s}", .{
                FH.optional(true, FH.opt(main_short, main_long, prefix)),
                if (self.T == bool) "" else "...",
            }),
            .optArg => print("{s}{s}", .{
                FH.optional(
                    self.common.default != null,
                    print("{s} {s}", .{
                        FH.opt(main_short, main_long, prefix),
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
    pub fn _help(self: Self, prefix: Prefix) []const u8 {
        var msg: []const u8 = self._usage(prefix);
        const space: usize = @max(24, helper.alignIntUp(usize, msg.len, 4) + 4);

        const newline: []const u8 = "\n" ++ " " ** space;
        var gap: []const u8 = " " ** (space - msg.len);

        if (self.common.help) |s| {
            msg = print("{s}{s}{s}", .{ msg, gap, s });
            gap = newline;
        }
        if (self.common.default) |_| {
            msg = print("{s}{s}(default={})", .{ msg, gap, nice(self._toField().defaultValue().?) });
            gap = newline;
        }
        if (self.common.ranges) |rs| {
            const p: *const Ranges(Base(self.T)) = @ptrCast(@alignCast(rs));
            msg = print("{s}{s}(ranges{})", .{ msg, gap, nice(p.rs) });
            gap = newline;
        }
        if (self.common.choices) |cs| {
            const p: *const []const Base(self.T) = @ptrCast(@alignCast(cs));
            msg = print("{s}{s}(choices{})", .{ msg, gap, nice(p.*) });
            gap = newline;
        }
        if (self.common.raw_choices) |cs| {
            msg = print("{s}{s}(raw_choices{})", .{ msg, gap, nice(cs) });
            gap = newline;
        }
        if (self.common.ranges == null and self.common.choices == null and self.common.raw_choices == null) {
            if (@typeInfo(Base(self.T)) == .@"enum" and self.common.parseFn == null and !std.meta.hasMethod(Base(self.T), "parse")) {
                msg = print("{s}{s}(enum{any})", .{ msg, gap, nice(helper.EnumUtil.names(Base(self.T))) });
            }
        }

        if (self.common.short.len > 1 or self.common.long.len > 1) {
            msg = print("{s}\n(alias ", .{msg});
            if (self.common.short.len > 1) {
                msg = print("{s}short{c}", .{ msg, nice(@as([]const u8, self.common.short[1..])) });
            }
            if (self.common.short.len > 1 and self.common.long.len > 1) {
                msg = print("{s} ", .{msg});
            }
            if (self.common.long.len > 1) {
                msg = print("{s}long{s}", .{ msg, nice(@as([]const String, self.common.long[1..])) });
            }
            msg = print("{s})", .{msg});
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
                    item.* = self._parseAny(s, a) orelse return Error.Invalid;
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
                const value = self._parseAny(s, a) orelse return Error.Invalid;
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
                item.* = self._parseAny(s, a) orelse return Error.Invalid;
            }
        } else {
            const t = it.nextMust() catch |err| {
                self.log("requires {s} but {any}", .{ self.common.argName.?, err });
                return Error.Missing;
            };
            s = t.as_posArg().posArg;
            const value = self._parseAny(s, a) orelse return Error.Invalid;
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
    pub fn _destroy(self: Self, r: anytype, a: Allocator) void {
        if (comptime isMultiple(self.T)) {
            for (@field(r, self.name)) |v| {
                parser.destroyAny(v, a);
            }
            if (comptime isSlice(self.T)) {
                a.free(@field(r, self.name));
            }
        } else if (comptime isOptional(self.T)) {
            if (@field(r, self.name)) |v| {
                parser.destroyAny(v, a);
            }
        } else {
            if (comptime self.common.default) |_ptr| {
                const ptr: *const self.T = @ptrCast(@alignCast(_ptr));
                if (std.meta.eql(@field(r, self.name), ptr.*)) {
                    return;
                }
            }
            parser.destroyAny(@field(r, self.name), a);
        }
    }

    const _test = struct {
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
                const meta = Self.optArg("out", bool).short('o').long("out").long("output")._checkOut();
                try testing.expect(meta._match(.{ .opt = .{ .short = 'o' } }));
                try testing.expect(!meta._match(.{ .opt = .{ .short = 'i' } }));
                try testing.expect(meta._match(.{ .opt = .{ .long = "out" } }));
                try testing.expect(meta._match(.{ .opt = .{ .long = "output" } }));
                try testing.expect(!meta._match(.{ .opt = .{ .long = "input" } }));
            }
        }
        test "Format usage" {
            {
                try testing.expectEqualStrings("[-o]", comptime Self.opt("out", bool).short('o')._usage(.{}));
                try testing.expectEqualStrings("[-o]...", comptime Self.opt("out", u32).short('o')._usage(.{}));
            }
            {
                try testing.expectEqualStrings(
                    "-o {OUT}",
                    comptime Self.optArg("out", bool).short('o')._checkOut()._usage(.{}),
                );
                try testing.expectEqualStrings(
                    "[-o {OUT}]",
                    comptime Self.optArg("out", bool).short('o').default(false)._checkOut()._usage(.{}),
                );
                try testing.expectEqualStrings(
                    "[-o {OUT}]",
                    comptime Self.optArg("out", ?bool).short('o')._checkOut()._usage(.{}),
                );
                try testing.expectEqualStrings(
                    "-o {[2]OUT}",
                    comptime Self.optArg("out", [2]u32).short('o')._checkOut()._usage(.{}),
                );
                try testing.expectEqualStrings(
                    "-o {[]OUT}...",
                    comptime Self.optArg("out", []const u32).short('o')._checkOut()._usage(.{}),
                );
            }
            {
                try testing.expectEqualStrings("{[2]OUT}", comptime Self.posArg("out", [2]u32)._checkOut()._usage(.{}));
                try testing.expectEqualStrings("[{OUT}]", comptime Self.posArg("out", u32).default(1)._checkOut()._usage(.{}));
            }
        }
        test "Format help" {
            {
                try testing.expectEqualStrings(
                    \\[-o|--out]              Help of out
                    \\                        (default=false)
                    \\(alias short{ u, t } long{ output })
                ,
                    comptime Self.opt("out", bool)
                        .short('o').short('u').short('t')
                        .long("out").long("output").help("Help of out")
                        ._checkOut()._help(.{}),
                );
            }
            {
                try testing.expectEqualStrings(
                    \\-o {OUT}                Help of out
                ,
                    comptime Self.optArg("out", String)
                        .short('o').help("Help of out")
                        ._checkOut()._help(.{}),
                );
            }
            {
                try testing.expectEqualStrings(
                    \\[-o|--out {OUT}]        Help of out
                    \\                        (default=a.out)
                    \\(alias long{ output })
                ,
                    comptime Self.optArg("out", String)
                        .short('o').long("out").long("output")
                        .default("a.out")
                        .help("Help of out")
                        ._checkOut()._help(.{}),
                );
            }
            {
                const Color = enum { Red, Green, Blue };
                try testing.expectEqualStrings(
                    \\[-c|--color {[3]COLORS}]    Help of colors
                    \\                            (default={ Red, Green, Blue })
                    \\                            (enum{ Red, Green, Blue })
                ,
                    comptime Self.optArg("colors", [3]Color)
                        .short('c').long("color")
                        .default([_]Color{ .Red, .Green, .Blue })
                        .help("Help of colors")
                        ._checkOut()._help(.{}),
                );
            }
            {
                try testing.expectEqualStrings(
                    \\[{U32}]                 (default=3)
                    \\                        (ranges{ [5,10), [32,∞) })
                    \\                        (choices{ 15, 29 })
                ,
                    comptime Self.posArg("u32", u32)
                        .default(3)
                        .ranges(Ranges(u32).new().u(5, 10).u(32, null))
                        .choices(&.{ 15, 29 })
                        ._checkOut()._help(.{}),
                );
            }
            {
                try testing.expectEqualStrings(
                    \\{CC}                    (choices{ gcc, clang })
                ,
                    comptime Self.posArg("cc", String)
                        .choices(&.{ "gcc", "clang" })
                        ._checkOut()._help(.{}),
                );
            }
            {
                try testing.expectEqualStrings(
                    \\{CC}                    (raw_choices{ gcc, clang })
                ,
                    comptime Self.posArg("cc", String)
                        .raw_choices(&.{ "gcc", "clang" })
                        ._checkOut()._help(.{}),
                );
            }
        }
        test "Consume opt" {
            const R = struct { out: bool, verbose: u32 };
            var r = std.mem.zeroes(R);
            var it = try token.Iter.initList(&.{ "--out", "-v", "-v", "--out", "-t" }, .{});
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
                var it = try token.Iter.initList(&.{"--out"}, .{});
                try testing.expect(!try meta_verbose._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"--out"}, .{});
                try testing.expectError(Error.Missing, meta_out._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{ "--out", "-v=0xf" }, .{});
                try testing.expectError(Error.Missing, meta_out._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"-v=a"}, .{});
                try testing.expectError(Error.Invalid, meta_verbose._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"-f=bin"}, .{});
                try testing.expectError(Error.Allocator, meta_files._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"-t"}, .{});
                try testing.expectError(Error.Missing, meta_twins._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"-t=a"}, .{});
                try testing.expectError(Error.Missing, meta_twins._consumeOptArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{ "-t", "a" }, .{});
                try testing.expectError(Error.Invalid, meta_twins._consumeOptArg(&r, &it, null));
            }
            {
                var res = std.mem.zeroes(R);
                var it = try token.Iter.initList(
                    &.{ "--out", "n", "-v=1", "-f", "bin0", "-t", "1", "2", "-f=bin1" },
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
        test "Consume optArg with both ranges and choices" {
            const R = struct { int: []i32 };
            const meta = Self.optArg("int", []i32).short('i');
            {
                const meta_int = meta.choices(&.{ 3, 5, 7 }).ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
                var r = std.mem.zeroes(R);
                var it = try token.Iter.initLine("-i=-1 -i 3 -i 5 -i=23", null, .{});
                try testing.expect(try meta_int._consumeOptArg(&r, &it, testing.allocator));
                try testing.expect(try meta_int._consumeOptArg(&r, &it, testing.allocator));
                try testing.expect(try meta_int._consumeOptArg(&r, &it, testing.allocator));
                try testing.expect(try meta_int._consumeOptArg(&r, &it, testing.allocator));
                try testing.expectEqualDeep(&[_]i32{ -1, 3, 5, 23 }, r.int);
                meta_int._destroy(r, testing.allocator);
            }
            {
                const meta_int = meta.choices(&.{ 3, 5, 7 }).ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
                var r = std.mem.zeroes(R);
                var it = try token.Iter.initLine("-i 6", null, .{});
                try testing.expectError(Error.Invalid, meta_int._consumeOptArg(&r, &it, testing.allocator));
            }
            {
                const meta_int = meta.ranges(Ranges(i32).new().u(null, 3).u(20, 32))._checkOut();
                var r = std.mem.zeroes(R);
                var it = try token.Iter.initLine("-i 6", null, .{});
                try testing.expectError(Error.Invalid, meta_int._consumeOptArg(&r, &it, testing.allocator));
            }
            {
                const meta_int = meta.choices(&.{ 3, 5, 7 })._checkOut();
                var r = std.mem.zeroes(R);
                var it = try token.Iter.initLine("-i 6", null, .{});
                try testing.expectError(Error.Invalid, meta_int._consumeOptArg(&r, &it, testing.allocator));
            }
        }
        test "Consume posArg" {
            const R = struct { out: bool, twins: [2]u32 };
            var r = std.mem.zeroes(R);
            const meta_out = Self.posArg("out", bool)._checkOut();
            const meta_twins = Self.posArg("twins", [2]u32)._checkOut();

            {
                var it = try token.Iter.initList(&.{}, .{});
                try testing.expectError(Error.Missing, meta_out._consumePosArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"a"}, .{});
                try testing.expectError(Error.Invalid, meta_out._consumePosArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{"1"}, .{});
                try testing.expectError(Error.Missing, meta_twins._consumePosArg(&r, &it, null));
            }
            {
                var it = try token.Iter.initList(&.{ "1", "a" }, .{});
                try testing.expectError(Error.Invalid, meta_twins._consumePosArg(&r, &it, null));
            }
            {
                var res = std.mem.zeroes(R);
                var it = try token.Iter.initList(&.{ "n", "1", "2" }, .{});
                try testing.expect(try meta_out._consumePosArg(&res, &it, null));
                try testing.expect(try meta_twins._consumePosArg(&res, &it, null));
                try testing.expectEqualDeep(R{ .out = false, .twins = [2]u32{ 1, 2 } }, res);
            }
        }
        test "Consume posArg with ranges or raw_choices" {
            const Mem = struct {
                buf: []u8 = undefined,
                len: usize,
                pub fn parse(s: String, a: ?Allocator) ?@This() {
                    const allocator = a orelse return null;
                    const len = parser.parseAny(usize, s, null) orelse return null;
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
            const meta = Self.posArg("mem", Mem);
            {
                const meta_mem = meta.ranges(Ranges(Mem).new().u(null, Mem{ .len = 5 }))._checkOut();
                var r = std.mem.zeroes(R);
                {
                    var it = try token.Iter.initList(&.{"3"}, .{});
                    try testing.expect(try meta_mem._consumePosArg(&r, &it, testing.allocator));
                    try testing.expectEqual(3, r.mem.len);
                    try testing.expectEqual(3, r.mem.buf.len);
                    meta_mem._destroy(r, testing.allocator);
                }
                {
                    var it = try token.Iter.initList(&.{"8"}, .{});
                    try testing.expectError(
                        Error.Invalid,
                        meta_mem._consumePosArg(&r, &it, testing.allocator),
                    );
                }
            }
            {
                const meta_mem = meta.raw_choices(&.{ "1", "2", "3", "16" })._checkOut();
                var r = std.mem.zeroes(R);
                var it = try token.Iter.initList(&.{"32"}, .{});
                try testing.expectError(
                    Error.Invalid,
                    meta_mem._consumePosArg(&r, &it, testing.allocator),
                );
            }
        }
        test "Consume posArg with choices" {
            const R = struct { out: String };
            var r = std.mem.zeroes(R);
            const meta_out = Self.posArg("out", String).choices(&.{ "install", "remove" })._checkOut();
            {
                var it = try token.Iter.initList(&.{"remove"}, .{});
                try testing.expect(try meta_out._consumePosArg(&r, &it, testing.allocator));
                try testing.expectEqualStrings("remove", r.out);
                meta_out._destroy(r, testing.allocator);
            }
            {
                var it = try token.Iter.initList(&.{"update"}, .{});
                try testing.expectError(Error.Invalid, meta_out._consumePosArg(&r, &it, testing.allocator));
            }
        }
    };
};

test {
    _ = FormatHelper._test;
    _ = Meta._test;
}
