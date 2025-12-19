const std = @import("std");
const passthrough = @import("passthrough.zig");
const log = @import("cmds/log.zig");
const status = @import("cmds/status.zig");
const add = @import("cmds/add.zig");
const alias = @import("cmds/alias.zig");
const git = @import("cmds/git.zig");

pub fn main() void {
    run() catch |err| {
        handleError(err);
    };
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("usage: zagi <command> [args...]\n", .{}) catch {};
        std.process.exit(1);
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "log")) {
        try log.run(allocator, args);
    } else if (std.mem.eql(u8, cmd, "status")) {
        try status.run(allocator, args);
    } else if (std.mem.eql(u8, cmd, "add")) {
        try add.run(allocator, args);
    } else if (std.mem.eql(u8, cmd, "alias")) {
        try alias.run(allocator, args);
    } else {
        try passthrough.run(allocator, args);
    }
}

fn handleError(err: anyerror) void {
    const stderr = std.fs.File.stderr().deprecatedWriter();

    const exit_code: u8 = switch (err) {
        git.Error.NotARepository => blk: {
            stderr.print("fatal: not a git repository\n", .{}) catch {};
            break :blk 128;
        },
        git.Error.InitFailed => blk: {
            stderr.print("fatal: failed to initialize libgit2\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.IndexOpenFailed => blk: {
            stderr.print("fatal: failed to open index\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.IndexWriteFailed => blk: {
            stderr.print("fatal: failed to write index\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.StatusFailed => blk: {
            stderr.print("fatal: failed to get status\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.FileNotFound => blk: {
            stderr.print("error: file not found\n", .{}) catch {};
            break :blk 128;
        },
        git.Error.AddFailed => blk: {
            stderr.print("error: failed to add files\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.RevwalkFailed => blk: {
            stderr.print("fatal: failed to walk commits\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.UsageError => blk: {
            stderr.print("usage: zagi add <path>...\n", .{}) catch {};
            break :blk 1;
        },
        git.Error.WriteFailed => blk: {
            stderr.print("fatal: write failed\n", .{}) catch {};
            break :blk 1;
        },
        error.OutOfMemory => blk: {
            stderr.print("fatal: out of memory\n", .{}) catch {};
            break :blk 1;
        },
        else => blk: {
            stderr.print("error: {}\n", .{err}) catch {};
            break :blk 1;
        },
    };

    std.process.exit(exit_code);
}
