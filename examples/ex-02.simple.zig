const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;

pub fn main() !void {
    comptime var cmd: Command = .{ .name = "demo", .use_subCmd = "action", .description = "This is a simple demo" };
    _ = cmd.opt("verbose", u32, .{ .short = 'v' }).optArg("output", []const u8, .{ .short = 'o', .long = "out" });
    comptime var install: Command = .{ .name = "install" };
    comptime var remove: Command = .{ .name = "remove" };
    _ = cmd.subCmd(install.posArg("name", []const u8, .{}).*).subCmd(remove.posArg("name", []const u8, .{}).*);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
