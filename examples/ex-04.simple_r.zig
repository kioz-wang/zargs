const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;

pub fn main() !void {
    const cmd = Command.new("demo").requireSub("action")
        .opt("verbose", u32, .{ .short = 'v', .help = "help of verbose" })
        .optArg("output", []const u8, .{ .short = 'o', .long = "out" })
        .sub(Command.new("install").posArg("name", []const u8, .{}))
        .sub(Command.new("remove").posArg("name", []const u8, .{}));

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args = cmd.parse(allocator) catch |err| {
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
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
