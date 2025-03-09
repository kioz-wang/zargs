const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;

var sum: i32 = 0;
pub fn main() !void {
    comptime var cmd: Command = .{ .name = "add", .use_subCmd = "use" };

    const add_remain: Command = .{ .name = "remain", .description = "summary remain args" };

    comptime var add_optArgs: Command = .{ .name = "opt", .description = "summary optArgs" };
    _ = add_optArgs.optArg("nums", []const i32, .{ .short = 'n', .long = "num", .help = "Give me an integer to add" });

    comptime var add_optArgs_auto_per: Command = .{ .name = "opt_auto_per", .description = "summary optArgs automatically" };
    _ = add_optArgs_auto_per.optArg("nums", []const i32, .{
        .short = 'n',
        .long = "num",
        .help = "Give me an integer to add",
        .parseFn = struct {
            fn f(s: []const u8) ?i32 {
                const n = zargs.parseAny(i32, s) orelse return null;
                std.log.info("add {d}", .{n});
                sum += n;
                return n;
            }
        }.f,
    });

    comptime var add_optArgs_auto_cb: Command = .{ .name = "opt_auto_cb", .description = "summary optArgs automatically" };
    _ = add_optArgs_auto_cb.optArg("nums", []const i32, .{
        .short = 'n',
        .long = "num",
        .help = "Give me an integer to add",
        .callBackFn = struct {
            fn f(v: *[]const i32) void {
                if (v.len != 0) {
                    const n = v.*[v.len - 1];
                    std.log.info("add {d}", .{n});
                    sum += n;
                }
            }
        }.f,
    });

    _ = cmd.subCmd(add_remain).subCmd(add_optArgs).subCmd(add_optArgs_auto_per).subCmd(add_optArgs_auto_cb);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var it = try TokenIter.init(allocator, .{});
    _ = try it.next();
    defer it.deinit();

    // it.debug(true);

    const args = try cmd.parseAlloc(&it, allocator);
    defer cmd.destroy(&args, allocator);

    std.log.debug("parse done for {s}", .{@tagName(args.use)});

    switch (args.use) {
        .opt => |a| {
            for (a.nums) |n| {
                std.log.info("add {d}", .{n});
                sum += n;
            }
        },
        .remain => |_| {
            const nums = try it.nextAllBase(allocator);
            defer allocator.free(nums);
            for (nums) |s| {
                const n = zargs.parseAny(@TypeOf(sum), s) orelse {
                    std.log.err("Fail to parse {s} to {s}", .{ s, @typeName(@TypeOf(sum)) });
                    std.process.exit(1);
                };
                std.log.info("add {d}", .{n});
                sum += n;
            }
        },
        else => {},
    }
    std.log.info("Sum is {d}", .{sum});
}
