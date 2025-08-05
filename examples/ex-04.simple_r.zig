const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const String = @import("ztype").String;

pub fn main() !void {
    const cmd = Command.new("demo").requireSub("action")
        .about("This is a demo using APIs in a style similar to Python3's `argparse`.")
        .opt("verbose", u32, .{ .short = 'v', .help = "help of verbose" })
        .optArg("output", String, .{ .short = 'o', .long = "out" })
        .sub(Command.new("install").posArg("name", String, .{}))
        .sub(Command.new("remove").posArg("name", String, .{}));

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args = cmd.parse(allocator) catch |e|
        zargs.exitf(e, 1, "\n{s}\n", .{cmd.usageString()});
    defer cmd.destroy(&args, allocator);
    switch (args.action) {
        .install => |a| {
            std.debug.print("Installing {s}\n", .{a.name});
        },
        .remove => |a| {
            std.debug.print("Removing {s}\n", .{a.name});
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
