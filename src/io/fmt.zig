const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const Type = ztype.Type;

pub const Options = struct {
    optional: Optional = .default,
    multiple: Multiple = .array,

    const Optional = struct {
        show_null: bool,
        pub const default: @This() = .{ .show_null = true };
    };
    const Multiple = struct {
        begin: String,
        separator: String,
        end: String,
        groupSize: usize = 1,
        pub fn dump(separator: String, groupSize: usize) @This() {
            return .{ .begin = "", .separator = separator, .end = "", .groupSize = groupSize };
        }
        pub const array: @This() = .{ .begin = "{ ", .separator = ", ", .end = " }" };
        pub const memory: @This() = dump("", 1);
    };
    fn assert(self: @This()) void {
        std.debug.assert(self.multiple.groupSize != 0);
    }
};

pub fn Any(V: type) type {
    return struct {
        value: V,
        options: Options,
        const Self = @This();

        pub fn init(value: V, options: Options) Self {
            return .{ .value = value, .options = options };
        }
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
            if (comptime Type.isOptional(V)) {
                if (self.value) |v| {
                    try any(v, self.options).format(fmt, options, writer);
                } else {
                    if (self.options.optional.show_null) try std.fmt.formatBuf("null", options, writer);
                }
                return;
            }
            if (V == LiteralString or V == String) {
                if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "s")) {
                    try std.fmt.formatBuf(self.value, options, writer);
                    return;
                }
            }
            if (comptime Type.isMultiple(V) or V == LiteralString or V == String) {
                self.options.assert();
                try std.fmt.formatBuf(self.options.multiple.begin, .{}, writer);
                for (self.value, 0..) |v, i| {
                    if (i != 0 and i % self.options.multiple.groupSize == 0)
                        try std.fmt.formatBuf(self.options.multiple.separator, .{}, writer);
                    try any(v, self.options).format(fmt, options, writer);
                }
                try std.fmt.formatBuf(self.options.multiple.end, .{}, writer);
                return;
            }
            if (comptime Type.isBase(V)) {
                switch (@typeInfo(V)) {
                    .@"enum" => try std.fmt.formatBuf(@tagName(self.value), options, writer),
                    else => try std.fmt.formatType(self.value, fmt, options, writer, std.options.fmt_max_depth),
                }
                return;
            }
            @compileError(comptimePrint("Unable to format {s}", .{@typeName(V)}));
        }
    };
}

pub fn any(value: anytype, options: Options) Any(@TypeOf(value)) {
    return .init(value, options);
}

pub fn Stringify(V: type, method: LiteralString) type {
    return struct {
        v: V,
        pub fn count(self: @This()) usize {
            var writer = std.io.countingWriter(std.io.null_writer);
            @setEvalBranchQuota(100000); // TODO why?
            // or use `@field(Cls, fname)(obj, args...)` directly
            @call(.auto, @field(V, method), .{ self.v, writer.writer() }) catch unreachable;
            return writer.bytes_written;
        }
        pub inline fn literal(self: @This()) *const [self.count():0]u8 {
            comptime {
                var buf: [self.count():0]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);
                @setEvalBranchQuota(100000); // TODO why?
                // @call(.auto, @field(V, method), .{ self.v, fbs.writer() }) catch unreachable;
                @field(V, method)(self.v, fbs.writer()) catch unreachable;
                buf[buf.len] = 0;
                const final = buf;
                return &final;
            }
        }
    };
}
pub fn stringify(v: anytype, comptime method: LiteralString) Stringify(@TypeOf(v), method) {
    return .{ .v = v };
}

pub fn comptimeUpperString(comptime src: LiteralString) [src.len:0]u8 {
    var dst = std.mem.zeroes([src.len:0]u8);
    _ = std.ascii.upperString(dst[0..], src);
    return dst;
}

const testing = std.testing;

test "Base" {
    {
        var buffer: [64]u8 = undefined;
        try testing.expectEqualStrings("1", try bufPrint(&buffer, "{}", .{Any(u32).init(1, .{})}));
        try testing.expectEqualStrings("9.000e-1", try bufPrint(&buffer, "{:.3}", .{Any(f32).init(0.9, .{})}));
        try testing.expectEqualStrings("true", try bufPrint(&buffer, "{}", .{Any(bool).init(true, .{})}));
        try testing.expectEqualStrings("1", comptimePrint("{}", .{comptime Any(u32).init(1, .{})}));
        {
            const ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{ a, b }", comptimePrint("{c}", .{comptime Any([2]u8).init(ab, .{})}));
            try testing.expectEqualStrings("{ a, b }", comptimePrint("{c}", .{comptime any(ab, .{})}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{c}", .{Any([2]u8).init(ab, .{})}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{c}", .{any(ab, .{})}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{c}", .{Any([]const u8).init(&ab, .{})}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{s}", .{Any([]const u8).init(&ab, .{})}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{s}", .{any(@as([]const u8, &ab), .{})}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{}", .{any(@as([]const u8, &ab), .{})}));
        }
        {
            var ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{c}", .{Any([]u8).init(&ab, .{})}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{c}", .{Any([2]u8).init(ab, .{})}));
        }
        {
            const s: [:0]const u8 = "hello";
            try testing.expectEqualStrings("{ h, e, l, l, o }", try bufPrint(&buffer, "{c}", .{any(s, .{})}));
            try testing.expectEqualStrings("hello", try bufPrint(&buffer, "{s}", .{any(s, .{})}));
            try testing.expectEqualStrings("hello", try bufPrint(&buffer, "{}", .{any(s, .{})}));
        }
    }
    {
        const Color = enum { Red, Green, Blue };
        try testing.expectEqualStrings(
            "Green",
            comptimePrint("{}", .{comptime Any(Color).init(.Green, .{})}),
        );
    }
    {
        const Person = struct { age: u32, name: String };
        const expect = "Person{ .age = 18, .name = { 74, 97, 99, 107 } }";
        try testing.expect(std.mem.endsWith(
            u8,
            comptimePrint("{}", .{comptime Any(Person).init(.{ .age = 18, .name = "Jack" }, .{})}),
            expect,
        ));
    }
}

test "Optional" {
    var buffer: [16]u8 = undefined;
    try testing.expectEqualStrings("1", try bufPrint(&buffer, "{}", .{Any(?u32).init(1, .{})}));
    try testing.expectEqualStrings("f", try bufPrint(&buffer, "{x}", .{Any(?u32).init(0xf, .{})}));
    try testing.expectEqualStrings("##f", try bufPrint(&buffer, "{x:#>3}", .{Any(?u32).init(0xf, .{})}));
    try testing.expectEqualStrings("null", try bufPrint(&buffer, "{}", .{Any(?u32).init(null, .{})}));
    try testing.expectEqualStrings("", try bufPrint(&buffer, "{}", .{Any(?u32).init(null, .{ .optional = .{ .show_null = false } })}));
    try testing.expectEqualStrings(" hello", try bufPrint(&buffer, "{s:>6}", .{Any(?String).init("hello", .{})}));
    try testing.expectEqualStrings("1", comptimePrint("{}", .{comptime Any(?u32).init(1, .{})}));
}

test "Multiple" {
    try testing.expectEqualStrings(
        "{  }",
        comptimePrint("{s}", .{comptime Any([]String).init(&[_]String{}, .{})}),
    );
    try testing.expectEqualStrings(
        "{ hello, world }",
        comptimePrint("{s}", .{comptime Any([]const String).init(&[_]String{ "hello", "world" }, .{})}),
    );
    try testing.expectEqualStrings(
        "{ _hello, _world }",
        comptimePrint("{s:_>6}", .{comptime Any([2]String).init([_]String{ "hello", "world" }, .{})}),
    );
    try testing.expectEqualStrings(
        "{ 15, 192 }",
        comptimePrint("{}", .{comptime Any([]const i32).init(&[_]i32{ 0xf, 0xc0 }, .{})}),
    );
    try testing.expectEqualStrings(
        "{ 0f, c0 }",
        comptimePrint("{x:02}", .{comptime Any([]const u32).init(&[_]u32{ 0xf, 0xc0 }, .{})}),
    );
    {
        var buffer: [64]u8 = undefined;
        var ab = [_]LiteralString{ "hello", "world" };
        try testing.expectEqualStrings("{ { h, e, l, l, o }, { w, o, r, l, d } }", try bufPrint(&buffer, "{c}", .{Any([]LiteralString).init(&ab, .{})}));
        try testing.expectEqualStrings("{ { h, e, l, l, o }, { w, o, r, l, d } }", try bufPrint(&buffer, "{c}", .{Any([2]LiteralString).init(ab, .{})}));
        try testing.expectEqualStrings("{ hello, world }", try bufPrint(&buffer, "{s}", .{Any([]LiteralString).init(&ab, .{})}));
        try testing.expectEqualStrings("{ hello, world }", try bufPrint(&buffer, "{s}", .{Any([2]LiteralString).init(ab, .{})}));
    }
}

test "hexdump" {
    const ab = [_]LiteralString{ "hello", "world" };
    try testing.expectEqualStrings("{ { 68, 65, 6c, 6c, 6f }, { 77, 6f, 72, 6c, 64 } }", comptimePrint(
        "{x}",
        .{comptime Any([2]LiteralString).init(ab, .{})},
    ));
    try testing.expectEqualStrings("68656C6C6F776F726C64", comptimePrint(
        "{X}",
        .{comptime Any([2]LiteralString).init(ab, .{ .multiple = .memory })},
    ));

    const AB = [_]Any(LiteralString){
        comptime .init("hello", .{ .multiple = .dump("_", 2) }),
        comptime .init("world", .{ .multiple = .memory }),
    };
    try testing.expectEqualStrings("{ 6865_6c6c_6f, 776f726c64 }", comptimePrint(
        "{x}",
        .{comptime any(AB, .{})},
    ));
}
