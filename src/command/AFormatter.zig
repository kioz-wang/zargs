const std = @import("std");

const Arg = @import("Argument.zig");
const Ranges = @import("helper").Ranges;

const Prefix = @import("token.zig").Prefix;

const ztype = @import("ztype");
const String = ztype.String;

const any = @import("fmt").any;

pub const Options = struct {
    prefix: Prefix = .{},
    indent: usize = 2,
    left_max: usize = 24,
};

const Self = @This();

arg: Arg,
options: Options,
left_length: usize = undefined,

pub fn init(arg: Arg, options: Options) Self {
    var self = Self{
        .arg = arg,
        .options = options,
    };
    var counting = std.io.countingWriter(std.io.null_writer);
    try self.usage1(counting.writer());
    self.left_length = counting.bytes_written;
    return self;
}
pub fn usage(self: Self, w: anytype) !void {
    var is_first = true;
    if (self.arg.meta.default != null) {
        try w.writeByte('[');
    }
    if (self.arg.meta.short.len > 0) {
        try w.writeAll(self.options.prefix.short);
        try w.writeByte(self.arg.meta.short[0]);
        is_first = false;
    }
    if (self.arg.meta.long.len > 0) {
        if (!is_first) try w.writeByte('|');
        try w.writeAll(self.options.prefix.long);
        try w.writeAll(self.arg.meta.long[0]);
        is_first = false;
    }
    if (self.arg.meta.argName) |s| {
        if (!is_first) try w.writeByte(' ');
        if (!is_first or self.arg.meta.default == null) {
            try w.writeByte('{');
        }
        switch (@typeInfo(self.arg.T)) {
            .array => |info| try w.print("[{d}]", .{info.len}),
            .pointer => if (self.arg.T != String) try w.writeAll("[]"),
            else => {},
        }
        try w.writeAll(s);
        if (!is_first or self.arg.meta.default == null) {
            try w.writeByte('}');
        }
    }
    if (self.arg.meta.default != null) {
        try w.writeByte(']');
    }
    if (self.arg.class == .opt and self.arg.T != bool or self.arg.class == .optArg and ztype.Type.isSlice(self.arg.T)) {
        try w.writeAll("...");
    }
}
fn usage1(self: Self, w: anytype) !void {
    var is_first = true;
    for (self.arg.meta.short) |short| {
        if (is_first) is_first = false else try w.writeAll(", ");
        try w.writeAll(self.options.prefix.short);
        try w.writeByte(short);
    }
    for (self.arg.meta.long) |long| {
        if (is_first) is_first = false else try w.writeAll(", ");
        try w.writeAll(self.options.prefix.long);
        try w.writeAll(long);
    }
    if (self.arg.meta.argName) |s| {
        if (!is_first) try w.writeByte(' ');
        try w.writeByte('{');
        switch (@typeInfo(self.arg.T)) {
            .array => |info| try w.print("[{d}]", .{info.len}),
            .pointer => if (self.arg.T != String) try w.writeAll("[]"),
            else => {},
        }
        try w.writeAll(s);
        try w.writeByte('}');
    }
}
fn indent(self: Self, w: anytype, is_firstline: *bool) !void {
    if (is_firstline.*) {
        is_firstline.* = false;
        if (self.left_length >= self.options.left_max) {
            try w.writeByte('\n');
            try w.writeAll(" " ** (self.options.left_max + self.options.indent));
        } else {
            try w.writeAll(" " ** (self.options.left_max - self.left_length));
        }
    } else {
        try w.writeByte('\n');
        try w.writeAll(" " ** (self.options.left_max + self.options.indent));
    }
}
pub fn help(self: Self, w: anytype) !void {
    const Base = ztype.Type.Base;
    const meta = self.arg.meta;

    var is_firstline = true;

    try w.writeAll(" " ** self.options.indent);
    try self.usage1(w);

    if (meta.help != null or meta.default != null) {
        try self.indent(w, &is_firstline);
        if (meta.help) |s| {
            try w.writeAll(s);
        }
        if (meta.default) |_| {
            if (meta.help != null) try w.writeByte(' ');
            try w.print("(default is {})", .{any(self.arg._toField().defaultValue().?, .{})});
        }
    }

    if (meta.ranges != null or meta.choices != null) {
        try self.indent(w, &is_firstline);
        try w.writeAll("possible values: ");
        if (meta.ranges) |_| {
            try w.print("{}", .{any(self.arg.getRanges().?.rs, .{ .multiple = .dump(" or ", 1) })});
        }
        if (meta.choices) |_| {
            if (meta.ranges != null) try w.writeAll(" or ");
            try w.print("{}", .{any(self.arg.getChoices().?.*, .{})});
        }
    }

    if (meta.rawChoices) |cs| {
        try self.indent(w, &is_firstline);
        try w.print("possible inputs: {}", .{any(cs, .{})});
    }

    if (meta.ranges == null and meta.choices == null and meta.rawChoices == null) {
        if (@typeInfo(Base(self.arg.T)) == .@"enum" and self.arg.getParseFn() == null and !std.meta.hasMethod(Base(self.arg.T), "parse")) {
            try self.indent(w, &is_firstline);
            try w.print("Enum: {}", .{any(std.meta.fieldNames(Base(self.arg.T)).*, .{})});
            is_firstline = false;
        }
    }

    try w.writeByte('\n');
}

const testing = std.testing;

test "usageString" {
    try testing.expectEqualStrings("[-o]", Arg.opt("out", bool).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("[-o]...", Arg.opt("out", u32).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("-o {OUT}", Arg.optArg("out", bool).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("[-o {OUT}]", Arg.optArg("out", bool).short('o').default(false)._checkOut().usageString());
    try testing.expectEqualStrings("[-o {OUT}]", Arg.optArg("out", ?bool).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("-o {[2]OUT}", Arg.optArg("out", [2]u32).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("-o {[]OUT}...", Arg.optArg("out", []const u32).short('o')._checkOut().usageString());
    try testing.expectEqualStrings("{[2]OUT}", Arg.posArg("out", [2]u32)._checkOut().usageString());
    try testing.expectEqualStrings("[OUT]", Arg.posArg("out", u32).default(1)._checkOut().usageString());
}

test "helpString" {
    try testing.expectEqualStrings(
        \\  -c, -n, --count, --cnt {COUNT}
        \\                          This is a help message, with a very very long long long sentence (default is 1)
        \\                          possible values: [-16,3) or [16,∞) or { 5, 6 }
        \\
    , Arg.optArg("count", i32)
        .short('c').short('n')
        .long("count").long("cnt")
        .help("This is a help message, with a very very long long long sentence")
        .ranges(Ranges(i32).new().u(-16, 3).u(16, null))
        .choices(&.{ 5, 6 })
        .default(1)
        ._checkOut().helpString());

    try testing.expectEqualStrings(
        \\  -c, -n {COUNT}          This is a help message, with a very very long long long sentence
        \\                          possible values: { 5, 6 }
        \\
    , Arg.optArg("count", i32)
        .short('c').short('n')
        .help("This is a help message, with a very very long long long sentence")
        .choices(&.{ 5, 6 })
        ._checkOut().helpString());

    try testing.expectEqualStrings(
        \\  -c, -n {COUNT}          possible inputs: { 0x05, 0x06 }
        \\
    , Arg.optArg("count", i32)
        .short('c').short('n')
        .rawChoices(&.{ "0x05", "0x06" })
        ._checkOut().helpString());

    {
        const Color = enum { Red, Green, Blue };
        try testing.expectEqualStrings(
            \\  {COLOR}                 Enum: { Red, Green, Blue }
            \\
        , Arg.posArg("color", Color)
            ._checkOut().helpString());
    }

    try testing.expectEqualStrings(
        \\  -o, -u, -t, --out, --output
        \\                          Help of out (default is false)
        \\
    , Arg.opt("out", bool)
        .short('o').short('u').short('t')
        .long("out").long("output").help("Help of out")
        ._checkOut().helpString());

    try testing.expectEqualStrings(
        \\  -o {OUT}                Help of out
        \\
    , Arg.optArg("out", String)
        .short('o').help("Help of out")
        ._checkOut().helpString());

    try testing.expectEqualStrings(
        \\  -o, --out, --output {OUT}
        \\                          Help of out (default is a.out)
        \\
    , Arg.optArg("out", String)
        .short('o').long("out").long("output")
        .default("a.out")
        .help("Help of out")
        ._checkOut().helpString());

    try testing.expectEqualStrings(
        \\  -p, --point {POINT}     (default is { 1, 1 })
        \\
    , Arg.optArg("point", @Vector(2, i32))
        .short('p').long("point").default(.{ 1, 1 })
        ._checkOut().helpString());

    {
        const Color = enum { Red, Green, Blue };
        try testing.expectEqualStrings(
            \\  -c, --color {[3]COLORS} Help of colors (default is { Red, Green, Blue })
            \\                          Enum: { Red, Green, Blue }
            \\
        , Arg.optArg("colors", [3]Color)
            .short('c').long("color")
            .default(.{ .Red, .Green, .Blue })
            .help("Help of colors")
            ._checkOut().helpString());
    }

    try testing.expectEqualStrings(
        \\  {U32}                   (default is 3)
        \\                          possible values: [5,10) or [32,∞) or { 15, 29 }
        \\
    ,
        Arg.posArg("u32", u32)
            .default(3)
            .ranges(Ranges(u32).new().u(5, 10).u(32, null))
            .choices(&.{ 15, 29 })
            ._checkOut().helpString(),
    );

    try testing.expectEqualStrings(
        \\  {CC}                    possible values: { gcc, clang }
        \\
    ,
        Arg.posArg("cc", String)
            .choices(&.{ "gcc", "clang" })
            ._checkOut().helpString(),
    );

    try testing.expectEqualStrings(
        \\  {CC}                    possible inputs: { gcc, clang }
        \\
    ,
        Arg.posArg("cc", String)
            .rawChoices(&.{ "gcc", "clang" })
            ._checkOut().helpString(),
    );
}
