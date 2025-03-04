const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Iter = zargs.Iter;

fn limitPlusOne(s: []const u8) ?u32 {
    const limit = std.fmt.parseInt(u32, s, 0) catch return null;
    return limit + 1;
}
const Color = enum { Red, Green, Blue };
const ColorWithParser = enum {
    White,
    Black,
    Gray,
    pub fn parser(s: []const u8) ?@This() {
        return if (std.ascii.eqlIgnoreCase(s, "White")) .White else if (std.ascii.eqlIgnoreCase(s, "Black")) .Black else if (std.ascii.eqlIgnoreCase(s, "Gray")) .Gray else null;
    }
};
const lastCharacter = struct {
    fn p(s: []const u8) ?u8 {
        return if (s.len == 0) null else s[s.len - 1];
    }
}.p;

fn showUint32(v: *u32) void {
    std.debug.print("Found U32 {d}\n", .{v.*});
}

pub fn main() !void {
    comptime var sub0: Command = .{ .name = "sub0" };

    _ = sub0.opt("verbose", u8, .{ .short = 'v' });

    _ = sub0.optArg("optional_int", u32, .{ .long = "oint", .default = 1 });
    _ = sub0.optArg("int", u32, .{ .long = "int", .help = "give me a u32", .arg_name = "PositiveNumber", .callBackFn = showUint32 });
    _ = sub0.optArg("bool", bool, .{ .long = "bool", .help = "give me a bool", .callBackFn = struct {
        fn f(v: *bool) void {
            std.debug.print("Found Bool {}\n", .{v.*});
            v.* = !v.*;
        }
    }.f });
    _ = sub0.optArg("color", Color, .{ .long = "color", .help = "give me a color", .default = Color.Blue });
    _ = sub0.optArg("colorp", ColorWithParser, .{ .long = "colorp", .help = "give me another color", .default = ColorWithParser.White });
    _ = sub0.optArg("lastc", u8, .{ .long = "lastc", .help = "give me a word", .arg_name = "word", .parseFn = lastCharacter });
    _ = sub0.optArg("word", []const u8, .{ .long = "word" });
    _ = sub0.optArg("3word", [3][]const u8, .{ .long = "3word", .help = "give me three words" });
    _ = sub0.optArg("nums", []const u32, .{ .long = "num", .arg_name = "N" });

    _ = sub0.posArg("optional_pos_int", u32, .{ .help = "give me a u32", .arg_name = "Num", .default = 9 });
    _ = sub0.posArg("pos_int", u32, .{ .help = "give me a u32", .parseFn = limitPlusOne });
    _ = sub0.posArg("optional_2pos_int", [2]u32, .{ .help = "give me two u32", .arg_name = "Num", .default = .{ 1, 2 } });

    comptime var cmd: Command = .{
        .name = "demo",
        .description = "This is a demo",
        .version = "1.0",
        .author = "kioz.wang@gmail.com",
        .use_subCmd = "sub",
    };
    _ = cmd.opt("verbose", u8, .{ .short = 'v' });
    _ = cmd.subCmd(sub0).subCmd(.{ .name = "sub1", .description = "This is an empty subCmd" });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var it = try Iter.init(allocator, .{});
    _ = try it.next();
    // var it = try Iter.initLine("-vv --int 1 --bool t --lastc hi --word ok --3word a b c 1", null, .{});
    // var it = try Iter.initLine("a", null, .{});
    defer it.deinit();
    // it.debug = true;

    const args = cmd.parseAlloc(&it, allocator) catch |e| {
        std.debug.print("\nError => {}\n", .{e});
        std.debug.print("{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    defer cmd.destory(&args, allocator);
    // it.debug = false;
    std.debug.print("{}\n\n", .{args});

    switch (args.sub) {
        .sub0 => |a| {
            std.debug.print("Capture subCmd sub0\n{}\n", .{a});
        },
        .sub1 => |a| {
            std.debug.print("Capture subCmd sub1\n{}\n", .{a});
        },
    }

    if ((try it.view()) != null) {
        std.debug.print("\nRemain command line input:\n\t", .{});
        // const remain = try it.nextAllBase(allocator);
        const remain = try it.reinit(.{}).nextAll(allocator);
        defer allocator.free(remain);
        std.debug.print("{s}\n", .{remain});
    }
}
