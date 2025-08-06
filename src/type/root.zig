//! Import this module with name `ztype` in `build.zig`, then add these in your source files:
//!
//! ```zig
//! const ztype = @import("ztype");
//! const String = ztype.String;
//! const LiteralString = ztype.LiteralString;
//! const checker = ztype.checker;
//! const ... = ztype.zzz;
//! ```

pub const String = []const u8;
pub const LiteralString = [:0]const u8;

pub const checker = @import("checker.zig");

const open = @import("open.zig");
pub const Open = open.Open;
pub const OpenLazy = open.OpenLazy;

test {
    @import("std").testing.refAllDecls(@This());
}
