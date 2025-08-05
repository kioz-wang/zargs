const std = @import("std");
const zargs = @import("zargs");
const Command = zargs.Command;
const Arg = zargs.Arg;
const TokenIter = zargs.TokenIter;
const ztype = @import("ztype");
const String = ztype.String;
const Open = ztype.Open;

pub fn main() !void {
    const cmd = Command.new("copy").alias("cp")
        .about("Copy a file to another file")
        .author("KiozWang")
        .homepage("https://github.com/kioz-wang/zargs")
        .arg(Arg.opt("verbose", bool).short('v').long("verbose").help("Show detail"))
        .arg(Arg.optArg("max", usize).long("max").help("Max byte to copy").default(32 << 10))
        .arg(Arg.posArg("source", Open(.file, .{})))
        .arg(Arg.posArg("target", Open(.fileCreate, .{})))
        .config(.{ .style = .classic });

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var args = cmd.parse(allocator) catch |e|
        zargs.exitf(e, 1, "\n{s}\n", .{cmd.usageString()});
    defer cmd.destroy(&args, allocator);

    if (args.verbose) {
        std.debug.print("Try copy {s} to {s} with max 0x{x} bytes\n", .{ args.source.s, args.target.s, args.max });
    }
    const content = try args.source.v.reader().any().readAllAlloc(allocator, args.max);
    defer allocator.free(content);
    try args.target.v.writer().any().writeAll(content);
    if (args.verbose) {
        std.debug.print("Done with 0x{x} bytes\n", .{content.len});
    }
}

// [kioz@matexpro zargs]$ echo "hello world" | ./zig-out/bin/06.copy -v -- - /tmp/t
// Try copy - to /tmp/t with max 0x8000 bytes
// Done with 0xc bytes
// [kioz@matexpro zargs]$ ./zig-out/bin/06.copy -v /tmp/t -
// Try copy /tmp/t to - with max 0x8000 bytes
// hello world
// Done with 0xc bytes
// [kioz@matexpro zargs]$ echo "bye" | ./zig-out/bin/06.copy -v -- - - | hexdump -C
// Try copy - to - with max 0x8000 bytes
// Done with 0x4 bytes
// 00000000  62 79 65 0a                                       |bye.|
// 00000004
