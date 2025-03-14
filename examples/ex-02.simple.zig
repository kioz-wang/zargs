const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;
const Opt = zargs.Opt;
const OptArg = zargs.OptArg;
const PosArg = zargs.PosArg;

pub fn main() !void {
    // comptime var install: Command = .{ .name = "install" };
    // comptime var remove: Command = .{ .name = "remove" };
    // comptime var cmd: Command = .{ .name = "demo", .use_subCmd = "action", .description = "This is a simple demo" };
    const cmd = Command.init("demo", "action")
        .opt__(
            Opt.init("verbose", u32)
                .short_('v')
                .help_("help of verbose"),
        )
        .optArg_("output", []const u8, .{ .short = 'o', .long = "out" })
        .subCmd_(
            Command.init("install", null)
                .posArg_("name", []const u8, .{}),
        )
        .subCmd_(
        Command.init("remove", null)
            .posArg_("name", []const u8, .{}),
    );

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
