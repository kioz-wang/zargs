const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;
const TokenIter = zargs.TokenIter;
const String = @import("ztype").String;

const _d = Command.new("D")
    .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
    .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
    .arg(Arg.optArg("output", ?String).long("out").short('o'))
    .arg(Arg.posArg("input", ?String));
const _c = Command.new("C")
    .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
    .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
    .arg(Arg.optArg("output", ?String).long("out").short('o'));
const _b = Command.new("B")
    .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
    .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
    .arg(Arg.optArg("output", ?String).long("out").short('o'));
const _a = Command.new("A")
    .arg(Arg.opt("verbose", u32).short('v').long("verbose"))
    .arg(Arg.opt("ignore", bool).short('i').long("ignore"))
    .arg(Arg.optArg("output", ?String).long("out").short('o'));
const a = _a.requireSub("sub").sub(
    _b.config(.{ .token = .{
        .prefix = .{ .long = "==" },
        .terminator = "##",
        .connector = ":",
    } }).requireSub("sub").sub(
        _c.requireSub("sub").sub(_d).config(.{ .token = .{
            .prefix = .{ .long = "+++", .short = "@" },
            .terminator = "**",
            .connector = "=>",
        } }),
    ),
);

const Sub = enum { A, B, C, D };

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
const allocator = gpa.allocator();

pub fn main() !void {
    const cmd = Command.new("config")
        .arg(Arg.posArg("sub", Sub)
        .callbackFn(struct {
        fn f(v: *Sub) void {
            const line = switch (v.*) {
                .A => "-h",
                .B => "B -h",
                .C => "B C @h",
                .D => "B C D @h",
            };
            var it = TokenIter.initLine(line, null, .{}) catch unreachable;
            it.debug(true);
            var args = a.parseFrom(&it, allocator) catch unreachable;
            defer a.destroy(&args, allocator);
        }
    }.f));

    var it = try TokenIter.init(allocator, .{});
    defer it.deinit();
    _ = try it.next();
    _ = try cmd.parseFrom(&it, null);
}
