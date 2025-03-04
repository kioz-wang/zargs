const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Iter = zargs.Iter;

pub fn main() !void {
    comptime var cmd: Command = .{ .name = "add", .use_subCmd = "use" };

    const add_posArgs: Command = .{ .name = "pos" };

    comptime var add_optArgs: Command = .{ .name = "opt" };
    _ = add_optArgs.optArg("nums", []const i32, .{
        .short = 'n',
        .long = "num",
        .help = "Give me an integer to add",
    });

    _ = cmd.subCmd(add_posArgs).subCmd(add_optArgs);

    const allocator = (std.heap.GeneralPurposeAllocator(.{}){}).allocator();

    var it = try Iter.init(allocator, .{});
    _ = try it.next();
    defer it.deinit();

    const args = try cmd.parseAlloc(&it, allocator);
    defer cmd.destory(&args, allocator);

    switch (args.use) {
        .add => |a| {
            _ = a;
        },
        .pos => |a| {
            _ = a;
        },
    }
}
