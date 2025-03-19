const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;

pub fn main() !void {
    comptime var install = Command.new("install")
        .arg(Arg.posArg("name", []const u8))
        .arg(Arg.optArg("count", u32).short('c').default(1));
    comptime install.callBack(struct {
        const C = install;
        fn f(r: *C.Result()) void {
            r.count *= 2;
            std.debug.print("[{s}] Installing {s} (count:{d})\n", .{ C.name, r.name, r.count });
        }
    }.f);

    comptime var remove = Command.new("remove")
        .arg(Arg.posArg("name", []const u8))
        .arg(Arg.optArg("count", u32).short('c').default(2));
    comptime remove.callBack(struct {
        const C = remove;
        fn f(r: *C.Result()) void {
            r.count *= 10;
            std.debug.print("[{s}] Removing {s} (count:{d})\n", .{ C.name, r.name, r.count });
        }
    }.f);

    comptime var cmd = Command.new("demo").requireSub("action")
        .about("This is a demo showcasing command callbacks.")
        .arg(Arg.opt("verbose", u32).short('v'))
        .sub(install)
        .sub(remove);
    comptime cmd.callBack(struct {
        const C = cmd;
        fn f(r: *C.Result()) void {
            std.debug.print("[{s}] Success to do {s}\n", .{ C.name, @tagName(r.action) });
        }
    }.f);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    _ = cmd.parse(allocator) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
}
