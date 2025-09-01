const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const bufPrint = std.fmt.bufPrint;

const ztype = @import("ztype");
const String = ztype.String;
const LiteralString = ztype.LiteralString;
const checker = ztype.checker;

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
        pub fn formatInner(self: Self, writer: *std.io.Writer, comptime fmode: u8, number: ?std.fmt.Number) std.io.Writer.Error!void {
            const options: std.fmt.Options = if (number) |num| .{
                .alignment = num.alignment,
                .fill = num.fill,
                .precision = num.precision,
                .width = num.width,
            } else .{};
            if (comptime checker.isOptional(V)) {
                if (self.value) |v| {
                    try any(v, self.options).formatInner(writer, fmode, number);
                } else {
                    if (self.options.optional.show_null) try writer.alignBufferOptions("null", options);
                }
                return;
            }
            if (V == LiteralString or V == String) {
                if (fmode == 's' or fmode == 'f') {
                    try writer.alignBufferOptions(self.value, options);
                    return;
                }
            }
            if (comptime checker.isMultiple(V) or V == LiteralString or V == String) {
                self.options.assert();
                try writer.alignBufferOptions(self.options.multiple.begin, .{});
                for (self.value, 0..) |v, i| {
                    if (i != 0 and i % self.options.multiple.groupSize == 0)
                        try writer.alignBufferOptions(self.options.multiple.separator, .{});
                    try any(v, self.options).formatInner(writer, fmode, number);
                }
                try writer.alignBufferOptions(self.options.multiple.end, .{});
                return;
            }
            if (V == u8 and fmode == 'c') {
                return writer.printAsciiChar(self.value, options);
            }
            if (comptime checker.isBase(V) and fmode == 'f') {
                switch (@typeInfo(V)) {
                    .@"enum" => try writer.alignBufferOptions(@tagName(self.value), options),
                    else => {
                        if (std.meta.hasMethod(V, "format")) {
                            try self.value.format(writer);
                        } else {
                            try writer.printValue("", options, self.value, std.options.fmt_max_depth);
                        }
                    },
                }
                return;
            }
            if (fmode == 'n') {
                switch (number.?.mode) {
                    .decimal => switch (@typeInfo(@TypeOf(self.value))) {
                        .float, .comptime_float, .int, .comptime_int, .@"struct", .@"enum", .vector => {
                            try writer.printValue("d", options, self.value, std.options.fmt_max_depth);
                        },
                        else => unreachable,
                    },
                    .binary => switch (@typeInfo(@TypeOf(self.value))) {
                        .int, .comptime_int, .@"enum", .@"struct", .vector => {
                            try writer.printValue("b", options, self.value, std.options.fmt_max_depth);
                        },
                        else => unreachable,
                    },
                    .octal => switch (@typeInfo(@TypeOf(self.value))) {
                        .int, .comptime_int, .@"enum", .@"struct", .vector => {
                            try writer.printValue("o", options, self.value, std.options.fmt_max_depth);
                        },
                        else => unreachable,
                    },
                    .hex => switch (@typeInfo(@TypeOf(self.value))) {
                        .float, .comptime_float, .int, .comptime_int, .@"enum", .@"struct", .pointer, .vector => {
                            switch (number.?.case) {
                                .lower => try writer.printValue("x", options, self.value, std.options.fmt_max_depth),
                                .upper => try writer.printValue("X", options, self.value, std.options.fmt_max_depth),
                            }
                        },
                        else => unreachable,
                    },
                    .scientific => switch (@typeInfo(@TypeOf(self.value))) {
                        .float, .comptime_float, .@"struct" => {
                            switch (number.?.case) {
                                .lower => try writer.printValue("e", options, self.value, std.options.fmt_max_depth),
                                .upper => try writer.printValue("E", options, self.value, std.options.fmt_max_depth),
                            }
                        },
                        else => unreachable,
                    },
                }
                return;
            }
            @compileError(comptimePrint("Unable to format {s}", .{@typeName(V)}));
        }
        pub fn format(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
            return self.formatInner(writer, 'f', null);
        }
        pub fn formatNumber(self: Self, writer: *std.io.Writer, number: std.fmt.Number) std.io.Writer.Error!void {
            @setEvalBranchQuota(5000);
            return self.formatInner(writer, 'n', number);
        }
        pub fn formatString(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
            return self.formatInner(writer, 's', null);
        }
        pub fn formatChar(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
            return self.formatInner(writer, 'c', null);
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
            var counting = std.Io.Writer.Discarding.init(&@as([0]u8, .{}));
            @setEvalBranchQuota(100000); // TODO why?
            // or use `@field(Cls, fname)(obj, args...)` directly
            @call(.auto, @field(V, method), .{ self.v, &counting.writer }) catch unreachable;
            return counting.fullCount();
        }
        pub inline fn literal(self: @This()) *const [self.count():0]u8 {
            comptime {
                var buf: [self.count():0]u8 = undefined;
                var fbs = std.Io.Writer.fixed(&buf);
                @setEvalBranchQuota(1000000); // TODO why?
                // @call(.auto, @field(V, method), .{ self.v, &fbs }) catch unreachable;
                @field(V, method)(self.v, &fbs) catch unreachable;
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
        try testing.expectEqualStrings("1", try bufPrint(&buffer, "{f}", .{Any(u32).init(1, .{})}));
        try testing.expectEqualStrings("9.000e-1", try bufPrint(&buffer, "{e:.3}", .{Any(f32).init(0.9, .{})}));
        try testing.expectEqualStrings("true", try bufPrint(&buffer, "{f}", .{Any(bool).init(true, .{})}));
        try testing.expectEqualStrings("1", comptimePrint("{f}", .{comptime Any(u32).init(1, .{})}));
        {
            const ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{ a, b }", comptimePrint("{f}", .{comptime std.fmt.alt(Any([2]u8).init(ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("{ a, b }", comptimePrint("{f}", .{comptime std.fmt.alt(any(ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([2]u8).init(ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(any(ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([]const u8).init(&ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([]const u8).init(&ab, .{}), .formatString)}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{f}", .{std.fmt.alt(any(@as([]const u8, &ab), .{}), .formatString)}));
            try testing.expectEqualStrings("ab", try bufPrint(&buffer, "{f}", .{any(@as([]const u8, &ab), .{})}));
        }
        {
            var ab = [_]u8{ 'a', 'b' };
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([]u8).init(&ab, .{}), .formatChar)}));
            try testing.expectEqualStrings("{ a, b }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([2]u8).init(ab, .{}), .formatChar)}));
        }
        {
            const s: [:0]const u8 = "hello";
            try testing.expectEqualStrings("{ h, e, l, l, o }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(any(s, .{}), .formatChar)}));
            try testing.expectEqualStrings("hello", try bufPrint(&buffer, "{f}", .{std.fmt.alt(any(s, .{}), .formatString)}));
            try testing.expectEqualStrings("hello", try bufPrint(&buffer, "{f}", .{any(s, .{})}));
        }
    }
    {
        const Color = enum { Red, Green, Blue };
        try testing.expectEqualStrings(
            "Green",
            comptimePrint("{f}", .{comptime Any(Color).init(.Green, .{})}),
        );
    }
    {
        const Person = struct { age: u32, name: String };
        // NOTE: The standard printing behavior of structures in `std` has changed in 0.15.1.
        // const expect = "Person{ .age = 18, .name = { 74, 97, 99, 107 } }";
        const expect = ".{ .age = 18, .name = { 74, 97, 99, 107 } }";
        try testing.expect(std.mem.endsWith(
            u8,
            comptimePrint("{f}", .{comptime Any(Person).init(.{ .age = 18, .name = "Jack" }, .{})}),
            expect,
        ));
    }
}

test "Optional" {
    var buffer: [16]u8 = undefined;
    try testing.expectEqualStrings("1", try bufPrint(&buffer, "{f}", .{Any(?u32).init(1, .{})}));
    try testing.expectEqualStrings("f", try bufPrint(&buffer, "{x}", .{Any(?u32).init(0xf, .{})}));
    try testing.expectEqualStrings("##f", try bufPrint(&buffer, "{x:#>3}", .{Any(?u32).init(0xf, .{})}));
    try testing.expectEqualStrings("null", try bufPrint(&buffer, "{f}", .{Any(?u32).init(null, .{})}));
    try testing.expectEqualStrings("", try bufPrint(&buffer, "{f}", .{Any(?u32).init(null, .{ .optional = .{ .show_null = false } })}));
    // Custom `format` with formatting options is no longer supported in zig 0.15.1, and no replacement has been found.
    // A possible alternative for this requirement is a dedicated function that converts `Any` to `[]const u8`, specifying formatting options.
    // try testing.expectEqualStrings(" hello", try bufPrint(&buffer, "{s:>6}", .{Any(?String).init("hello", .{})}));
    try testing.expectEqualStrings("hello", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any(?String).init("hello", .{}), .formatString)}));
    try testing.expectEqualStrings("1", comptimePrint("{f}", .{comptime Any(?u32).init(1, .{})}));
}

test "Multiple" {
    try testing.expectEqualStrings(
        "{  }",
        comptimePrint("{f}", .{comptime std.fmt.alt(Any([]String).init(&[_]String{}, .{}), .formatString)}),
    );
    try testing.expectEqualStrings(
        "{ hello, world }",
        comptimePrint("{f}", .{comptime std.fmt.alt(Any([]const String).init(&[_]String{ "hello", "world" }, .{}), .formatString)}),
    );
    // Custom `format` with formatting options is no longer supported in zig 0.15.1, and no replacement has been found.
    // A possible alternative for this requirement is a dedicated function that converts `Any` to `[]const u8`, specifying formatting options.
    // try testing.expectEqualStrings(
    //     "{ _hello, _world }",
    //     comptimePrint("{s:_>6}", .{comptime Any([2]String).init([_]String{ "hello", "world" }, .{})}),
    // );
    try testing.expectEqualStrings(
        "{ 15, 192 }",
        comptimePrint("{f}", .{comptime Any([]const i32).init(&[_]i32{ 0xf, 0xc0 }, .{})}),
    );
    try testing.expectEqualStrings(
        "{ 0f, c0 }",
        comptimePrint("{x:02}", .{comptime Any([]const u32).init(&[_]u32{ 0xf, 0xc0 }, .{})}),
    );
    {
        var buffer: [64]u8 = undefined;
        var ab = [_]LiteralString{ "hello", "world" };
        try testing.expectEqualStrings("{ { h, e, l, l, o }, { w, o, r, l, d } }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([]LiteralString).init(&ab, .{}), .formatChar)}));
        try testing.expectEqualStrings("{ { h, e, l, l, o }, { w, o, r, l, d } }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([2]LiteralString).init(ab, .{}), .formatChar)}));
        try testing.expectEqualStrings("{ hello, world }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([]LiteralString).init(&ab, .{}), .formatString)}));
        try testing.expectEqualStrings("{ hello, world }", try bufPrint(&buffer, "{f}", .{std.fmt.alt(Any([2]LiteralString).init(ab, .{}), .formatString)}));
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
