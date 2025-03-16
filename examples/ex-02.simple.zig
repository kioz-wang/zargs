const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;
const Meta = zargs.Meta;

pub fn main() !void {
    const cmd = Command.new("demo").requireSub("action")
        .arg(Meta.opt("verbose", u32)
            .short('v')
            .help("help of verbose"))
        .arg(Meta.optArg("output", []const u8)
            .short('o')
            .long("out"))
        .sub(Command.new("install")
            .arg(Meta.posArg("name", []const u8)))
        .sub(Command.new("remove")
        .arg(Meta.posArg("name", []const u8)));

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
        },
    }
    std.debug.print("Success to do {s}\n", .{@tagName(args.action)});
}
