const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const TokenIter = zargs.TokenIter;

pub fn main() !void {
    comptime var install: Command = .{ .name = "install" };
    _ = install.posArg("name", []const u8, .{}).optArg("count", u32, .{ .short = 'c', .default = 1 });
    comptime install.callBack(struct {
        const C = install;
        fn f(r: *C.Result()) void {
            r.count *= 2;
            std.debug.print("[{s}] Installing {s} (count:{d})\n", .{ C.name, r.name, r.count });
        }
    }.f);

    comptime var remove: Command = .{ .name = "remove" };
    _ = remove.posArg("name", []const u8, .{}).optArg("count", u32, .{ .short = 'c', .default = 1 });
    comptime remove.callBack(struct {
        const C = remove;
        fn f(r: *C.Result()) void {
            r.count *= 10;
            std.debug.print("[{s}] Removing {s} (count:{d})\n", .{ C.name, r.name, r.count });
        }
    }.f);

    comptime var cmd: Command = .{ .name = "demo", .use_subCmd = "action", .description = "This is a simple demo" };
    _ = cmd.opt("verbose", u32, .{ .short = 'v' });
    _ = cmd.subCmd(install).subCmd(remove);
    comptime cmd.callBack(struct {
        const C = cmd;
        fn f(r: *C.Result()) void {
            std.debug.print("[{s}] Success to do {s}\n", .{ C.name, @tagName(r.action) });
        }
    }.f);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var it = try TokenIter.init(allocator, .{});
    defer it.deinit();
    _ = try it.next();

    _ = cmd.parse(&it) catch |err| {
        std.debug.print("Fail to parse because of {any}\n", .{err});
        std.debug.print("\n{s}\n", .{cmd.usage()});
        std.process.exit(1);
    };
}
