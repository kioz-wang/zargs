const std = @import("std");

const Command = @import("Command.zig");
const AFormatter = @import("AFormatter.zig");
const Config = @import("Config.zig");

const ztype = @import("ztype");
const String = ztype.String;

const any = @import("fmt").any;
const stringify = @import("fmt").stringify;

const Self = @This();

c: Command,
left_length: usize = undefined,

pub fn init(c: Command) Self {
    var self = Self{ .c = c };
    var counting = std.io.countingWriter(std.io.null_writer);
    try self.usage1(counting.writer());
    self.left_length = counting.bytes_written;
    return self;
}

pub fn usage(self: Self, w: anytype) !void {
    try w.writeAll(self.c.name[0]);
    if (self.c._builtin_help) |m| {
        try w.writeByte(' ');
        try AFormatter.init(m, self.c._config).usage(w);
    }
    inline for (self.c._args) |m| {
        if (m.class != .opt) continue;
        try w.writeByte(' ');
        try AFormatter.init(m, self.c._config).usage(w);
    }
    inline for (self.c._args) |m| {
        if (m.class != .optArg) continue;
        try w.writeByte(' ');
        try AFormatter.init(m, self.c._config).usage(w);
    }
    if (self.c._stat.posArg != 0 or self.c._stat.cmd != 0) {
        try w.print(" [{s}]", .{self.c._config.token.terminator});
    }
    inline for (self.c._args) |m| {
        if (m.class != .posArg) continue;
        if (m.meta.default == null) {
            try w.writeByte(' ');
            try AFormatter.init(m, self.c._config).usage(w);
        }
    }
    inline for (self.c._args) |m| {
        if (m.class != .posArg) continue;
        if (m.meta.default != null) {
            try w.writeByte(' ');
            try AFormatter.init(m, self.c._config).usage(w);
        }
    }
    if (self.c._stat.cmd != 0) {
        try w.writeAll(" {");
        inline for (self.c._cmds, 0..) |c, i| {
            if (i != 0) {
                try w.writeByte('|');
            }
            try w.writeAll(c.name[0]);
        }
        try w.writeAll("}");
    }
}

pub fn usage1(self: Self, w: anytype) !void {
    try w.print("{}", .{any(self.c.name, .{ .multiple = .dump(", ", 1) })});
}

pub fn help1(self: Self, w: anytype) !void {
    try w.writeAll(" " ** self.c._config.format.indent);
    try self.usage1(w);

    if (self.c.meta.about) |s| {
        if (self.left_length >= self.c._config.format.left_max) {
            try w.writeByte('\n');
            try w.writeAll(" " ** (self.c._config.format.left_max + self.c._config.format.indent));
        } else {
            try w.writeAll(" " ** (self.c._config.format.left_max - self.left_length));
        }
        try w.writeAll(s);
    }

    try w.writeByte('\n');
}

pub fn help(self: Self, w: anytype) !void {
    try w.writeAll("Usage: ");
    try self.usage(w);
    try w.writeByte('\n');

    if (self.c.meta.about) |s| {
        try w.print("\n{s}\n", .{s});
    }

    if (self.c.meta.version != null or self.c.meta.author != null or self.c.meta.homepage != null) {
        try w.writeByte('\n');
        var is_first = true;
        if (self.c.meta.version) |s| {
            try w.print("Version {s}", .{s});
            is_first = false;
        }
        if (self.c.meta.author) |s| {
            if (!is_first) try w.writeByte('\t');
            try w.print("Author <{s}>", .{s});
            is_first = false;
        }
        if (self.c.meta.homepage) |s| {
            if (!is_first) try w.writeByte('\t');
            try w.print("Homepage {s}", .{s});
        }
        try w.writeByte('\n');
    }

    if (self.c._stat.opt != 0 or self.c._builtin_help != null) {
        try w.writeAll("\nOption:\n");
        if (self.c._builtin_help) |m| {
            try AFormatter.init(m, self.c._config).help(w);
        }
        inline for (self.c._args) |m| {
            if (m.class != .opt) continue;
            try AFormatter.init(m, self.c._config).help(w);
        }
    }

    if (self.c._stat.optArg != 0) {
        try w.writeAll("\nOption with arguments:\n");
        inline for (self.c._args) |m| {
            if (m.class != .optArg) continue;
            try AFormatter.init(m, self.c._config).help(w);
        }
    }

    if (self.c._stat.posArg != 0) {
        try w.writeAll("\nPositional arguments:\n");
        inline for (self.c._args) |m| {
            if (m.class != .posArg) continue;
            try AFormatter.init(m, self.c._config).help(w);
        }
    }

    if (self.c._stat.cmd != 0) {
        try w.writeAll("\nCommands:\n");
        inline for (self.c._cmds) |c| {
            try Self.init(c).help1(w);
        }
    }
}

const testing = std.testing;

test "usageString" {
    const Arg = @import("Argument.zig");
    const subcmd0 = Command.new("subcmd0")
        .arg(Arg.optArg("optional_int", i32).long("oint").default(1).argName("OINT"))
        .arg(Arg.optArg("int", i32).long("int"))
        .arg(Arg.optArg("files", []const String).short('f').long("file"))
        .arg(Arg.posArg("optional_pos", u32).default(6))
        .arg(Arg.posArg("io", [2]String))
        .arg(Arg.posArg("message", String).default("hello"));
    const cmd = Command.new("cmd").requireSub("sub")
        .arg(Arg.opt("verbose", u8).short('v'))
        .sub(subcmd0)
        .sub(Command.new("subcmd1"));
    try testing.expectEqualStrings(
        "cmd [-h|--help] [-v]... [--] {subcmd0|subcmd1}",
        cmd.usageString(),
    );
    try testing.expectEqualStrings(
        "subcmd0 [-h|--help] [--oint {OINT}] --int {INT} -f|--file {[]FILES}... [--] {[2]IO} [OPTIONAL_POS] [MESSAGE]",
        subcmd0.usageString(),
    );
}

test "helpString" {
    const Arg = @import("Argument.zig");
    {
        const cmd = Command.new("cmd")
            .arg(Arg.opt("verbose", u8).short('v').help("Set log level"))
            .arg(Arg.optArg("optional_int", i32).long("oint").default(1).argName("OINT").help("Optional integer"))
            .arg(Arg.optArg("int", i32).long("int").help("Required integer"))
            .arg(Arg.optArg("files", []String).short('f').long("file").help("Multiple files"))
            .arg(Arg.posArg("optional_pos", u32).default(6).help("Optional position argument"))
            .arg(Arg.posArg("io", [2]String).help("Array position arguments"))
            .arg(Arg.posArg("message", ?String).help("Optional message"));
        try testing.expectEqualStrings(
            \\Usage: cmd [-h|--help] [-v]... [--oint {OINT}] --int {INT} -f|--file {[]FILES}... [--] {[2]IO} [OPTIONAL_POS] [MESSAGE]
            \\
            \\Option:
            \\  -h, --help              Show this help then exit (default is false)
            \\  -v                      Set log level (default is 0)
            \\
            \\Option with arguments:
            \\  --oint {OINT}           Optional integer (default is 1)
            \\  --int {INT}             Required integer
            \\  -f, --file {[]FILES}    Multiple files
            \\
            \\Positional arguments:
            \\  {OPTIONAL_POS}          Optional position argument (default is 6)
            \\  {[2]IO}                 Array position arguments
            \\  {MESSAGE}               Optional message (default is null)
            \\
        ,
            cmd.helpString(),
        );
    }
    {
        const cmd = Command.new("cmd").requireSub("sub")
            .arg(Arg.opt("verbose", u8).short('v'))
            .sub(Command.new("subcmd0").alias("alias0").alias("alias1"))
            .sub(Command.new("subcmd1").alias("alias3"));
        try testing.expectEqualStrings(
            \\Usage: cmd [-h|--help] [-v]... [--] {subcmd0|subcmd1}
            \\
            \\Option:
            \\  -h, --help              Show this help then exit (default is false)
            \\  -v                      (default is 0)
            \\
            \\Commands:
            \\  subcmd0, alias0, alias1
            \\  subcmd1, alias3
            \\
        ,
            cmd.helpString(),
        );
    }
}
