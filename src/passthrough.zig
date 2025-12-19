const std = @import("std");

/// Pass through a command to git CLI
pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var git_args = std.array_list.Managed([]const u8).init(allocator);
    defer git_args.deinit();

    try git_args.append("git");
    for (args[1..]) |arg| {
        try git_args.append(arg);
    }

    var child = std.process.Child.init(git_args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = child.spawnAndWait() catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Error executing git: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    switch (term) {
        .Exited => |code| std.process.exit(code),
        .Signal => |sig| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            stderr.print("Git terminated by signal {d}\n", .{sig}) catch {};
            std.process.exit(1);
        },
        .Stopped => |sig| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            stderr.print("Git stopped by signal {d}\n", .{sig}) catch {};
            std.process.exit(1);
        },
        .Unknown => |code| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            stderr.print("Git exited with unknown status {d}\n", .{code}) catch {};
            std.process.exit(1);
        },
    }
}
