const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;
const Ranges = zargs.Ranges;
const String = @import("ztype").String;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .about("Remove something")
        .alias("rm").alias("uninstall").alias("del")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", String, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo intended to be showcased in the README.")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", u32).short('v').help("help of verbose"))
        .arg(Arg.optArg("logfile", ?String).long("log").help("Store log into a file"))
        .sub(Command.new("install")
            .about("Install something")
            .arg(Arg.optArg("count", u32).default(10)
                .short('c').short('n').short('t')
                .long("count").long("cnt")
                .ranges(Ranges(u32).new().u(5, 7).u(13, null)).choices(&.{ 10, 11 }))
            .arg(Arg.posArg("name", String).rawChoices(&.{ "gcc", "clang" }))
            .arg(Arg.optArg("output", String).short('o').long("out"))
            .arg(Arg.optArg("vector", ?@Vector(3, i32)).long("vec")))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var args = cmd.config(.{ .style = .classic }).parse(allocator) catch |e|
        zargs.exitf(e, 1, "\n{s}\n", .{cmd.usageString()});
    defer cmd.destroy(&args, allocator);
    if (args.logfile) |logfile| std.debug.print("Store log into {s}\n", .{logfile});
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
