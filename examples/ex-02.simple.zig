const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;
const Meta = zargs.Meta;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", []const u8, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Meta.opt("verbose", u32)
            .short('v')
            .help("help of verbose"))
        .sub(Command.new("install")
            .arg(Meta.posArg("name", []const u8))
            .arg(
            Meta.optArg("output", []const u8)
                .short('o')
                .long("out"),
        ))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var it = try TokenIter.init(allocator, .{});
    defer it.deinit();
    _ = try it.next();

    const args = cmd.parse(&it) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    switch (args.action) {
        .install => |a| {
            std.debug.print("Installing {s}\n", .{a.name});
        },
        .remove => |a| {
            std.debug.print("Removing {s}\n", .{a.name});
            std.debug.print("{any}\n", .{a});
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
