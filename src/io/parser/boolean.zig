const std = @import("std");

const ztype = @import("ztype");
const String = ztype.String;

pub fn parse(s: String) ?bool {
    return switch (s.len) {
        1 => switch (s[0]) {
            'n', 'N', 'f', 'F' => false,
            'y', 'Y', 't', 'T' => true,
            else => null,
        },
        2 => if (std.ascii.eqlIgnoreCase(s, "no")) false else null,
        3 => if (std.ascii.eqlIgnoreCase(s, "yes")) true else null,
        4 => if (std.ascii.eqlIgnoreCase(s, "true")) true else null,
        5 => if (std.ascii.eqlIgnoreCase(s, "false")) false else null,
        else => null,
    };
}

const testing = std.testing;

test parse {
    try testing.expectEqual(true, parse("y"));
    try testing.expectEqual(true, parse("Y"));
    try testing.expectEqual(true, parse("t"));
    try testing.expectEqual(true, parse("T"));
    try testing.expectEqual(false, parse("n"));
    try testing.expectEqual(false, parse("N"));
    try testing.expectEqual(false, parse("f"));
    try testing.expectEqual(false, parse("F"));
    try testing.expectEqual(true, parse("yEs"));
    try testing.expectEqual(true, parse("TRue"));
    try testing.expectEqual(false, parse("nO"));
    try testing.expectEqual(false, parse("False"));
    try testing.expectEqual(null, parse("xxx"));
}
