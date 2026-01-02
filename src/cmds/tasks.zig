const std = @import("std");
const git = @import("git.zig");
const c = git.c;
const json = std.json;

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
    JsonParseError,
    JsonWriteError,
    OutOfMemory,
};

/// Represents a single task
const Task = struct {
    id: []const u8,
    content: []const u8,
    status: []const u8 = "pending",
    created: i64,
    completed: ?i64 = null,
    after: ?[]const u8 = null, // ID of task this depends on

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.content);
        allocator.free(self.status);
        if (self.after) |after_id| {
            allocator.free(after_id);
        }
    }
};

/// Container for all tasks in a branch
const TaskList = struct {
    tasks: std.ArrayList(Task),
    next_id: u32 = 1,

    const Self = @This();

    pub fn init(_: std.mem.Allocator) Self {
        return Self{
            .tasks = std.ArrayList(Task){},
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.tasks.items) |*task| {
            task.deinit(allocator);
        }
        self.tasks.deinit(allocator);
    }

    pub fn generateId(self: *Self, allocator: std.mem.Allocator) Error![]u8 {
        const id = std.fmt.allocPrint(allocator, "task-{:03}", .{self.next_id}) catch return Error.OutOfMemory;
        self.next_id += 1;
        return id;
    }

    /// Serialize TaskList to simple text format
    pub fn toJson(self: Self, allocator: std.mem.Allocator) Error![]u8 {
        // Use a simple line-based format for now to avoid JSON complexity
        var lines = std.ArrayList([]const u8){};
        defer {
            for (lines.items) |line| {
                allocator.free(line);
            }
            lines.deinit(allocator);
        }

        // First line: next_id
        const next_id_line = std.fmt.allocPrint(allocator, "next_id:{}", .{self.next_id}) catch return Error.OutOfMemory;
        lines.append(allocator, next_id_line) catch return Error.OutOfMemory;

        // Task lines: id|content|status|created|completed|after
        for (self.tasks.items) |task| {
            const completed_str = if (task.completed) |comp_time| std.fmt.allocPrint(allocator, "{}", .{comp_time}) catch return Error.OutOfMemory else allocator.dupe(u8, "") catch return Error.OutOfMemory;
            const after_str = if (task.after) |a| a else "";

            const task_line = std.fmt.allocPrint(allocator, "task:{s}|{s}|{s}|{}|{s}|{s}",
                .{ task.id, task.content, task.status, task.created, completed_str, after_str }
            ) catch return Error.OutOfMemory;
            lines.append(allocator, task_line) catch return Error.OutOfMemory;

            if (task.completed != null) {
                allocator.free(completed_str);
            }
        }

        // Join lines with newlines
        var total_len: usize = 0;
        for (lines.items) |line| {
            total_len += line.len + 1; // +1 for newline
        }

        if (total_len == 0) return allocator.dupe(u8, "") catch return Error.OutOfMemory;

        var result = allocator.alloc(u8, total_len - 1) catch return Error.OutOfMemory; // -1 to avoid trailing newline
        var pos: usize = 0;
        for (lines.items, 0..) |line, i| {
            @memcpy(result[pos..pos + line.len], line);
            pos += line.len;
            if (i < lines.items.len - 1) {
                result[pos] = '\n';
                pos += 1;
            }
        }

        return result;
    }

    /// Deserialize TaskList from simple text format
    pub fn fromJson(allocator: std.mem.Allocator, data_str: []const u8) Error!Self {
        var task_list = TaskList.init(allocator);

        var lines = std.mem.splitSequence(u8, data_str, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "next_id:")) {
                const id_str = line[8..];
                task_list.next_id = std.fmt.parseInt(u32, id_str, 10) catch 1;
            } else if (std.mem.startsWith(u8, line, "task:")) {
                const task_data = line[5..];
                var parts = std.mem.splitSequence(u8, task_data, "|");

                var task = Task{
                    .id = "",
                    .content = "",
                    .status = "pending",
                    .created = 0,
                };

                if (parts.next()) |id| {
                    task.id = allocator.dupe(u8, id) catch return Error.AllocationError;
                }
                if (parts.next()) |content| {
                    task.content = allocator.dupe(u8, content) catch return Error.AllocationError;
                }
                if (parts.next()) |status| {
                    task.status = allocator.dupe(u8, status) catch return Error.AllocationError;
                }
                if (parts.next()) |created| {
                    task.created = std.fmt.parseInt(i64, created, 10) catch 0;
                }
                if (parts.next()) |completed| {
                    if (completed.len > 0) {
                        task.completed = std.fmt.parseInt(i64, completed, 10) catch null;
                    }
                }
                if (parts.next()) |after| {
                    if (after.len > 0) {
                        task.after = allocator.dupe(u8, after) catch return Error.AllocationError;
                    }
                }

                task_list.tasks.append(allocator, task) catch return Error.AllocationError;
            }
        }

        return task_list;
    }
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
    return allocator.dupe(u8, branch_name) catch return Error.OutOfMemory;
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
        const empty = allocator.dupe(u8, "") catch return Error.OutOfMemory; // Empty content
        return empty;
    }

    const content_slice = @as([*]const u8, @ptrCast(content_ptr))[0..content_size];
    const result = allocator.dupe(u8, content_slice) catch return Error.OutOfMemory;
    return result;
}

/// Load TaskList from refs/tasks/<branch>
fn loadTaskList(repo: ?*c.git_repository, allocator: std.mem.Allocator) Error!TaskList {
    const content = readRef(repo, allocator) catch |err| switch (err) {
        Error.RefNotFound => return TaskList.init(allocator),
        else => return err,
    };

    if (content == null) {
        return TaskList.init(allocator);
    }

    defer if (content) |json_content| allocator.free(json_content);

    if (content.?.len == 0) {
        return TaskList.init(allocator);
    }

    return TaskList.fromJson(allocator, content.?);
}

/// Save TaskList to refs/tasks/<branch>
fn saveTaskList(repo: ?*c.git_repository, task_list: TaskList, allocator: std.mem.Allocator) Error!void {
    const json_content = try task_list.toJson(allocator);
    defer allocator.free(json_content);

    try writeRef(repo, json_content, allocator);
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
    const stdout = std.fs.File.stdout().deprecatedWriter();

    // Need at least: tasks add <content>
    if (args.len < 4) {
        stdout.print("error: missing task content\n\nusage: git tasks add <content>\n", .{}) catch {};
        return Error.MissingTaskContent;
    }

    // Parse arguments for content and optional --after flag
    var content: ?[]const u8 = null;
    var after_id: ?[]const u8 = null;
    var i: usize = 3; // Start after "git tasks add"

    while (i < args.len) {
        const arg = std.mem.sliceTo(args[i], 0);

        if (std.mem.eql(u8, arg, "--after")) {
            // Next argument should be the task ID
            i += 1;
            if (i >= args.len) {
                stdout.print("error: --after requires a task ID\n", .{}) catch {};
                return Error.InvalidTaskId;
            }
            after_id = std.mem.sliceTo(args[i], 0);
        } else if (content == null) {
            // First non-flag argument is the content
            content = arg;
        } else {
            // Multiple content arguments - concatenate with spaces
            const existing = content.?;
            const combined = std.fmt.allocPrint(allocator, "{s} {s}", .{ existing, arg }) catch return Error.AllocationError;
            // Note: we're not tracking these allocations, but they're short-lived
            content = combined;
        }
        i += 1;
    }

    if (content == null or content.?.len == 0) {
        stdout.print("error: task content cannot be empty\n", .{}) catch {};
        return Error.MissingTaskContent;
    }

    // Load existing tasks
    var task_list = loadTaskList(repo, allocator) catch |err| {
        stdout.print("error: failed to load tasks: {}\n", .{err}) catch {};
        return err;
    };
    defer task_list.deinit(allocator);

    // Generate new task ID
    const task_id = task_list.generateId(allocator) catch return Error.AllocationError;

    // Get current timestamp (Unix seconds)
    const now = std.time.timestamp();

    // Create the new task
    const new_task = Task{
        .id = task_id,
        .content = allocator.dupe(u8, content.?) catch return Error.AllocationError,
        .status = allocator.dupe(u8, "pending") catch return Error.AllocationError,
        .created = now,
        .after = if (after_id) |aid| allocator.dupe(u8, aid) catch return Error.AllocationError else null,
    };

    // Add task to list
    task_list.tasks.append(allocator, new_task) catch return Error.AllocationError;

    // Save updated task list
    saveTaskList(repo, task_list, allocator) catch |err| {
        stdout.print("error: failed to save tasks: {}\n", .{err}) catch {};
        return err;
    };

    // Output confirmation
    stdout.print("created: {s}\n  {s}\n", .{ task_id, content.? }) catch {};
}

fn runList(allocator: std.mem.Allocator, args: [][:0]u8, repo: ?*c.git_repository) Error!void {
    _ = args; // No additional args needed for list
    const stdout = std.fs.File.stdout().deprecatedWriter();

    // Load task list from git ref
    var task_list = loadTaskList(repo, allocator) catch |err| {
        stdout.print("error: failed to load tasks: {}\n", .{err}) catch {};
        return err;
    };
    defer task_list.deinit(allocator);

    // If no tasks, show empty state
    if (task_list.tasks.items.len == 0) {
        stdout.print("no tasks found\n", .{}) catch {};
        return;
    }

    // Display task count summary
    var pending_count: usize = 0;
    var completed_count: usize = 0;
    for (task_list.tasks.items) |task| {
        if (std.mem.eql(u8, task.status, "completed")) {
            completed_count += 1;
        } else {
            pending_count += 1;
        }
    }

    stdout.print("tasks: {} total ({} pending, {} completed)\n\n",
        .{ task_list.tasks.items.len, pending_count, completed_count }) catch {};

    // List all tasks with compact format
    for (task_list.tasks.items) |task| {
        const status_mark = if (std.mem.eql(u8, task.status, "completed")) "✓" else " ";

        // Show dependency if present
        if (task.after) |after_id| {
            stdout.print("[{s}] {s} (after {s})\n  {s}\n",
                .{ status_mark, task.id, after_id, task.content }) catch {};
        } else {
            stdout.print("[{s}] {s}\n  {s}\n",
                .{ status_mark, task.id, task.content }) catch {};
        }
    }
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