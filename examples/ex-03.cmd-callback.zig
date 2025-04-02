const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;

pub fn main() !void {
    const install = Command.new("install")
        .arg(Arg.posArg("name", []const u8))
        .arg(Arg.optArg("count", u32).short('c').default(1));

    const remove = Command.new("remove")
        .arg(Arg.posArg("name", []const u8))
        .arg(Arg.optArg("count", u32).short('c').default(2));

    const _cmd = Command.new("demo").requireSub("action")
        .about("This is a demo showcasing command callbacks.")
        .sub(
            install.callBack(struct {
                fn f(r: *install.Result()) void {
                    r.count *= 2;
                    std.debug.print("[{s}] Installing {s} (count:{d})\n", .{ install.name, r.name, r.count });
                }
            }.f),
        )
        .sub(
            remove.callBack(struct {
                fn f(r: *remove.Result()) void {
                    r.count *= 10;
                    std.debug.print("[{s}] Removing {s} (count:{d})\n", .{ remove.name, r.name, r.count });
                }
            }.f),
        )
        .arg(Arg.opt("verbose", u32).short('v'));
    const cmd = _cmd.callBack(struct {
        fn f(r: *_cmd.Result()) void {
            std.debug.print("[{s}] Success to do {s}\n", .{ _cmd.name, @tagName(r.action) });
        }
    }.f);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    _ = cmd.parse(allocator) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{_cmd.usage()});
        std.process.exit(1);
    };
}
