const std = @import("std");
const testing = std.testing;

const Meta = @import("meta.zig").Meta;
const Command = @import("Command.zig");
const attr = @import("attr");
const Alias = @import("helper.zig").Alias;
const String = Alias.String;
const Prefix = @import("helper.zig").Config.Prefix;

pub fn MetaFormatter(W: type) type {
    return struct {
        m: Meta,
        w: W,

        const Self = @This();
        const Error = W.Error;

        pub fn formatOptions(self: Self, prefix: Prefix, sep: String) Error!bool {
            var first = true;

            for (self.m.common.short) |short| {
                try std.fmt.formatBuf(prefix.short, .{}, self.w);
                try self.w.writeByte(short);
                first = false;
                break;
            }
            for (self.m.common.long) |long| {
                if (!first) {
                    try self.w.writeAll(sep);
                }
                try std.fmt.formatBuf(prefix.long, .{}, self.w);
                try self.w.writeAll(long);
                first = false;
                break;
            }

            return !first;
        }
    };
}
