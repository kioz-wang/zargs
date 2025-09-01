//! Import this module with name `ztype` in `build.zig`, then add these in your source files:
//!
//! ```zig
//! const ztype = @import("ztype");
//! const String = ztype.String;
//! const LiteralString = ztype.LiteralString;
//! const checker = ztype.checker;
//! const ... = ztype.zzz;
//! ```

const base = @import("base.zig");
pub const String = base.String;
pub const LiteralString = base.LiteralString;

pub const checker = @import("checker.zig");

const open = @import("open.zig");
pub const Open = open.Open;
pub const OpenLazy = open.OpenLazy;

const read = @import("read.zig");
pub const Read = read.Read;
pub const ReadLazy = read.ReadLazy;

test {
    @import("std").testing.refAllDecls(@This());
}
