const std = @import("std");
const git = @import("git.zig");
const c = git.c;

pub const help =
    \\usage: git tasks <command> [options]
    \\
    \\Task management for git repositories.
    \\
    \\Commands:
    \\  add <content>           Add a new task
    \\  list                    List all tasks
    \\  show <id>               Show task details
    \\  done <id>               Mark task as complete
    \\  ready                   List tasks ready to work on (no blockers)
    \\  pr                      Export tasks as markdown for PR description
    \\
    \\Options:
    \\  --after <id>           Add task dependency (use with 'add')
    \\  --json                 Output in JSON format
    \\  -h, --help             Show this help message
    \\
    \\Examples:
    \\  git tasks add "Fix authentication bug"
    \\  git tasks add "Add tests" --after task-001
    \\  git tasks list
    \\  git tasks show task-001
    \\  git tasks done task-001
    \\  git tasks ready
    \\  git tasks pr
    \\
;

pub const Error = git.Error || error{
    InvalidCommand,
    MissingTaskContent,
    InvalidTaskId,
    TaskNotFound,
    RefReadFailed,
    RefWriteFailed,
    RefNotFound,
    BranchNameTooLong,
    AllocationError,
};

/// Get current branch name
fn getCurrentBranch(repo: ?*c.git_repository, allocator: std.mem.Allocator) Error![]u8 {
    var head_ref: ?*c.git_reference = null;
    if (c.git_repository_head(&head_ref, repo) < 0) {
        return Error.RefReadFailed;
    }
    defer c.git_reference_free(head_ref);

    const ref_name = c.git_reference_name(head_ref);
    if (ref_name == null) {
        return Error.RefReadFailed;
    }

    const full_name = std.mem.sliceTo(ref_name, 0);
    const prefix = "refs/heads/";
    if (!std.mem.startsWith(u8, full_name, prefix)) {
        return Error.RefReadFailed;
    }

    const branch_name = full_name[prefix.len..];
    return allocator.dupe(u8, branch_name);
}

/// Build a ref name like "refs/tasks/main" from a branch name
fn buildTaskRefName(branch: []const u8, allocator: std.mem.Allocator) Error![]u8 {
    const prefix = "refs/tasks/";
    const total_len = prefix.len + branch.len;

    if (total_len > 256) { // reasonable limit
        return Error.BranchNameTooLong;
    }

    var ref_name = allocator.alloc(u8, total_len) catch return Error.AllocationError;
    @memcpy(ref_name[0..prefix.len], prefix);
    @memcpy(ref_name[prefix.len..], branch);

    return ref_name;
}

/// Read task data from refs/tasks/<branch>
fn readRef(repo: ?*c.git_repository, allocator: std.mem.Allocator) Error!?[]u8 {
    // Get current branch name
    const branch = getCurrentBranch(repo, allocator) catch return Error.RefReadFailed;
    defer allocator.free(branch);

    // Build ref name like "refs/tasks/main"
    const ref_name = buildTaskRefName(branch, allocator) catch return Error.RefReadFailed;
    defer allocator.free(ref_name);

    // Create null-terminated string for libgit2
    const ref_name_z = allocator.allocSentinel(u8, ref_name.len, 0) catch return Error.AllocationError;
    defer allocator.free(ref_name_z);
    @memcpy(ref_name_z, ref_name);

    // Look up the reference
    var tasks_ref: ?*c.git_reference = null;
    const lookup_result = c.git_reference_lookup(&tasks_ref, repo, ref_name_z.ptr);
    if (lookup_result < 0) {
        if (lookup_result == c.GIT_ENOTFOUND) {
            return null; // Ref doesn't exist yet, not an error
        }
        return Error.RefReadFailed;
    }
    defer c.git_reference_free(tasks_ref);

    // Get the target OID
    const target_oid = c.git_reference_target(tasks_ref);
    if (target_oid == null) {
        return Error.RefReadFailed;
    }

    // Look up the blob object
    var blob: ?*c.git_blob = null;
    if (c.git_blob_lookup(&blob, repo, target_oid) < 0) {
        return Error.RefReadFailed;
    }
    defer c.git_blob_free(blob);

    // Get blob content
    const content_ptr = c.git_blob_rawcontent(blob);
    const content_size = c.git_blob_rawsize(blob);

    if (content_ptr == null or content_size == 0) {
        return allocator.dupe(u8, ""); // Empty content
    }

    const content_slice = @as([*]const u8, @ptrCast(content_ptr))[0..content_size];
    return allocator.dupe(u8, content_slice);
}

/// Write task data to refs/tasks/<branch>
fn writeRef(repo: ?*c.git_repository, content: []const u8, allocator: std.mem.Allocator) Error!void {
    // Get current branch name
    const branch = getCurrentBranch(repo, allocator) catch return Error.RefWriteFailed;
    defer allocator.free(branch);

    // Build ref name like "refs/tasks/main"
    const ref_name = buildTaskRefName(branch, allocator) catch return Error.RefWriteFailed;
    defer allocator.free(ref_name);

    // Create null-terminated string for libgit2
    const ref_name_z = allocator.allocSentinel(u8, ref_name.len, 0) catch return Error.AllocationError;
    defer allocator.free(ref_name_z);
    @memcpy(ref_name_z, ref_name);

    // Create blob from content
    var blob_oid: c.git_oid = undefined;
    if (c.git_blob_create_from_buffer(&blob_oid, repo, content.ptr, content.len) < 0) {
        return Error.RefWriteFailed;
    }

    // Create or update the reference to point to the blob
    var tasks_ref: ?*c.git_reference = null;
    if (c.git_reference_create(&tasks_ref, repo, ref_name_z.ptr, &blob_oid, 1, null) < 0) {
        return Error.RefWriteFailed;
    }
    defer c.git_reference_free(tasks_ref);
}

pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) Error!void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    if (args.len < 3) {
        stdout.print("{s}", .{help}) catch {};
        return;
    }

    const subcommand = std.mem.sliceTo(args[2], 0);

    // Handle help flags
    if (std.mem.eql(u8, subcommand, "-h") or std.mem.eql(u8, subcommand, "--help")) {
        stdout.print("{s}", .{help}) catch {};
        return;
    }

    // Initialize libgit2
    if (c.git_libgit2_init() < 0) {
        return git.Error.InitFailed;
    }
    defer _ = c.git_libgit2_shutdown();

    // Open repository
    var repo: ?*c.git_repository = null;
    if (c.git_repository_open_ext(&repo, ".", 0, null) < 0) {
        return git.Error.NotARepository;
    }
    defer c.git_repository_free(repo);

    // Route to subcommands
    if (std.mem.eql(u8, subcommand, "add")) {
        try runAdd(allocator, args, repo);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try runList(allocator, args, repo);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        try runShow(allocator, args, repo);
    } else if (std.mem.eql(u8, subcommand, "done")) {
        try runDone(allocator, args, repo);
    } else if (std.mem.eql(u8, subcommand, "ready")) {
        try runReady(allocator, args, repo);
    } else if (std.mem.eql(u8, subcommand, "pr")) {
        try runPr(allocator, args, repo);
    } else {
        stdout.print("error: unknown command '{s}'\n\n{s}", .{ subcommand, help }) catch {};
        return Error.InvalidCommand;
    }
}

fn runAdd(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks add: not implemented yet\n", .{}) catch {};
}

fn runList(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks list: not implemented yet\n", .{}) catch {};
}

fn runShow(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks show: not implemented yet\n", .{}) catch {};
}

fn runDone(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks done: not implemented yet\n", .{}) catch {};
}

fn runReady(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks ready: not implemented yet\n", .{}) catch {};
}

fn runPr(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = allocator;
    _ = args;
    _ = repo;

    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print("tasks pr: not implemented yet\n", .{}) catch {};
}

// Tests
const testing = std.testing;

test "buildTaskRefName - basic branch name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ref_name = try buildTaskRefName("main", allocator);
    try testing.expectEqualStrings("refs/tasks/main", ref_name);
}

test "buildTaskRefName - feature branch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ref_name = try buildTaskRefName("feature/auth", allocator);
    try testing.expectEqualStrings("refs/tasks/feature/auth", ref_name);
}

test "buildTaskRefName - long branch name fails" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a branch name that makes the total ref name > 256 chars
    var long_name: [300]u8 = undefined;
    @memset(&long_name, 'x');

    const result = buildTaskRefName(&long_name, allocator);
    try testing.expectError(Error.BranchNameTooLong, result);
}