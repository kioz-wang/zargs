const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;

pub fn main() !void {
    // Like Py3 argparse, https://docs.python.org/3.13/library/argparse.html
    const remove = Command.new("remove")
        .opt("verbose", u32, .{ .short = 'v' })
        .optArg("count", u32, .{ .short = 'c', .argName = "CNT", .default = 9 })
        .posArg("name", []const u8, .{});

    // Like Rust clap, https://docs.rs/clap/latest/clap/
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo intended to be showcased in the README.")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", u32)
            .short('v')
            .help("help of verbose"))
        .arg(Arg.optArg("logfile", ?[]const u8)
            .long("log")
            .help("Store log into a file"))
        .sub(Command.new("install")
            .arg(Arg.posArg("name", []const u8))
            .arg(Arg.optArg("output", []const u8)
                .short('o')
                .long("out"))
            .arg(Arg.optArg("count", u32)
            .short('c')
            .default(6)
            .ranges(&.{ .init(5, 7), .init(13, null) })))
        .sub(remove);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args = cmd.parse(allocator) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
    defer cmd.destroy(&args, allocator);
    if (args.logfile) |logfile| {
        std.debug.print("Store log into {s}\n", .{logfile});
    }
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
