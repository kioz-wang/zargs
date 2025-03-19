const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;
const Arg = zargs.Arg;

fn limitPlusOne(s: []const u8, _: ?std.mem.Allocator) ?u32 {
    const limit = std.fmt.parseInt(u32, s, 0) catch return null;
    return limit + 1;
}
const Color = enum { Red, Green, Blue };
const ColorWithParser = enum {
    White,
    Black,
    Gray,
    pub fn parse(s: []const u8, _: ?std.mem.Allocator) ?@This() {
        return if (std.ascii.eqlIgnoreCase(s, "White")) .White else if (std.ascii.eqlIgnoreCase(s, "Black")) .Black else if (std.ascii.eqlIgnoreCase(s, "Gray")) .Gray else null;
    }
};
const lastCharacter = struct {
    fn p(s: []const u8, _: ?std.mem.Allocator) ?u8 {
        return if (s.len == 0) null else s[s.len - 1];
    }
}.p;

fn showUint32(v: *u32) void {
    std.debug.print("Found U32 {d}\n", .{v.*});
}

pub fn main() !void {
    const sub0 = Command.new("sub0")
        .arg(Arg.opt("verbose", u8).short('v'))
        .arg(Arg.optArg("optional_int", u32)
            .long("oint")
            .default(1))
        .arg(Arg.optArg("int", u32)
            .long("int")
            .help("give me a u32")
            .argName("PositiveNumber")
            .callBackFn(showUint32))
        .arg(Arg.optArg("bool", bool)
            .long("bool")
            .help("give me a bool")
            .callBackFn(struct {
            fn f(v: *bool) void {
                std.debug.print("Found Bool {}\n", .{v.*});
                v.* = !v.*;
            }
        }.f))
        .arg(Arg.optArg("color", Color)
            .long("color")
            .help("give me a color")
            .default(.Blue))
        .arg(Arg.optArg("colorp", ColorWithParser)
            .long("colorp")
            .help("give me another color")
            .default(.White))
        .arg(Arg.optArg("lastc", u8)
            .long("lastc")
            .help("give me a word")
            .argName("word")
            .parseFn(lastCharacter))
        .arg(Arg.optArg("word", []const u8)
            .long("word"))
        .arg(Arg.optArg("3word", [3][]const u8)
            .long("3word")
            .help("give me three words"))
        .arg(Arg.optArg("nums", []const u32)
            .long("num")
            .argName("N"))
        .arg(Arg.posArg("optional_pos_int", u32)
            .argName("Num")
            .help("give me a u32")
            .default(9))
        .arg(Arg.posArg("pos_int", u32)
            .help("give me a u32")
            .parseFn(limitPlusOne))
        .arg(Arg.posArg("optional_2pos_int", [2]u32)
        .argName("Num")
        .help("give me two u32")
        .default(.{ 1, 2 }));

    const cmd = Command.new("demo").requireSub("sub")
        .about("This is a demo")
        .version("1.0")
        .author("kioz.wang@gmail.com")
        .arg(Arg.opt("verbose", u8).short('v'))
        .sub(sub0)
        .sub(Command.new("sub1").about("This is an empty subCmd"));

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var it = try TokenIter.init(allocator, .{});
    _ = try it.next();
    // var it = try Iter.initLine("-vv --int 1 --bool t --lastc hi --word ok --3word a b c 1", null, .{});
    // var it = try Iter.initLine("a", null, .{});
    defer it.deinit();
    // it.debug(true);

    const args = cmd.parseFrom(&it, allocator) catch |e| {
        std.debug.print("\nError => {}\n", .{e});
        std.debug.print("{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    defer cmd.destroy(&args, allocator);
    // it.debug(false);
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
        const remain = try it.nextAllBase(allocator);
        defer allocator.free(remain);
        std.debug.print("{s}\n", .{remain});
    }
}
