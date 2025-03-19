const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;
const Arg = zargs.Arg;

var sum: i32 = 0;
pub fn main() !void {
    const add_remain = Command.new("remain").about("summary remain args");
    const add_optArgs = Command.new("opt").about("summary optArgs")
        .arg(
        Arg.optArg("nums", []const i32)
            .short('n').long("num")
            .help("Give me an integer"),
    );
    const add_optArgs_auto_per = Command.new("opt_auto_per").about("summary optArgs automatically")
        .arg(Arg.optArg("nums", []const i32)
        .short('n').long("num")
        .help("Give me an integer")
        .parseFn(
        struct {
            fn f(s: []const u8, _: ?std.mem.Allocator) ?i32 {
                const n = zargs.parseAny(i32, s, null) orelse return null;
                std.log.info("add {d}", .{n});
                sum += n;
                return n;
            }
        }.f,
    ));
    const add_optArgs_auto_cb = Command.new("opt_auto_cb").about("summary optArgs automatically")
        .arg(
        Arg.optArg("nums", []const i32)
            .short('n').long("num")
            .help("Give me an integer to add")
            .callBackFn(struct {
            fn f(v: *[]const i32) void {
                if (v.len != 0) {
                    const n = v.*[v.len - 1];
                    std.log.info("add {d}", .{n});
                    sum += n;
                }
            }
        }.f),
    );

    const cmd = Command.new("add").requireSub("use")
        .about("This is a demo showcasing the use of `parseFn` and `callBackFn`.")
        .sub(add_remain).sub(add_optArgs)
        .sub(add_optArgs_auto_per)
        .sub(add_optArgs_auto_cb);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var it = try TokenIter.init(allocator, .{});
    _ = try it.next();
    defer it.deinit();

    // it.debug(true);

    const args = try cmd.parseFrom(&it, allocator);
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
                const n = zargs.parseAny(@TypeOf(sum), s, null) orelse {
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
