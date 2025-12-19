const std = @import("std");
const c = @cImport(@cInclude("git2.h"));
const git = @import("git.zig");

pub const help =
    \\usage: zagi diff [--staged]
    \\
    \\Show changes in working tree or staging area.
    \\
    \\Options:
    \\  --staged    Show staged changes (what will be committed)
    \\
;

const DiffError = git.Error || error{OutOfMemory};

pub fn run(_: std.mem.Allocator, args: [][:0]u8) DiffError!void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    // Parse args
    var staged = false;

    for (args[2..]) |arg| {
        const a = std.mem.sliceTo(arg, 0);
        if (std.mem.eql(u8, a, "--staged") or std.mem.eql(u8, a, "--cached")) {
            staged = true;
        } else if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            stdout.print("{s}", .{help}) catch {};
            return;
        }
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

    // Set up diff options
    var diff_opts: c.git_diff_options = undefined;
    _ = c.git_diff_options_init(&diff_opts, c.GIT_DIFF_OPTIONS_VERSION);
    diff_opts.context_lines = 0; // No context lines - agent knows the file

    var diff: ?*c.git_diff = null;

    if (staged) {
        // Diff HEAD to index (staged changes)
        var head_commit: ?*c.git_commit = null;
        var head_tree: ?*c.git_tree = null;

        var head_ref: ?*c.git_reference = null;
        if (c.git_repository_head(&head_ref, repo) == 0 and head_ref != null) {
            defer c.git_reference_free(head_ref);
            const head_oid = c.git_reference_target(head_ref);
            if (head_oid != null) {
                if (c.git_commit_lookup(&head_commit, repo, head_oid) == 0) {
                    defer c.git_commit_free(head_commit);
                    _ = c.git_commit_tree(&head_tree, head_commit);
                }
            }
        }
        defer if (head_tree != null) c.git_tree_free(head_tree);

        if (c.git_diff_tree_to_index(&diff, repo, head_tree, null, &diff_opts) < 0) {
            return git.Error.StatusFailed;
        }
    } else {
        // Diff index to workdir (unstaged changes)
        if (c.git_diff_index_to_workdir(&diff, repo, null, &diff_opts) < 0) {
            return git.Error.StatusFailed;
        }
    }
    defer c.git_diff_free(diff);

    // Track state for printing
    var print_state = PrintState{
        .stdout = stdout,
        .current_file = null,
        .current_hunk_start = 0,
        .current_hunk_end = 0,
        .had_output = false,
    };

    // Print the diff
    _ = c.git_diff_print(diff, c.GIT_DIFF_FORMAT_PATCH, printCallback, &print_state);

    if (!print_state.had_output) {
        stdout.print("no changes\n", .{}) catch {};
    }
}

const PrintState = struct {
    stdout: std.fs.File.DeprecatedWriter,
    current_file: ?[]const u8,
    current_hunk_start: u32,
    current_hunk_end: u32,
    had_output: bool,
};

fn printCallback(
    delta: ?*const c.git_diff_delta,
    hunk: ?*const c.git_diff_hunk,
    line: ?*const c.git_diff_line,
    payload: ?*anyopaque,
) callconv(.c) c_int {
    const state: *PrintState = @ptrCast(@alignCast(payload));
    const stdout = state.stdout;

    if (line) |l| {
        const origin = l.origin;

        // File header
        if (origin == c.GIT_DIFF_LINE_FILE_HDR) {
            // New file starting
            if (delta) |d| {
                const new_path = if (d.new_file.path) |p| std.mem.sliceTo(p, 0) else null;
                if (new_path) |path| {
                    if (state.current_file == null or !std.mem.eql(u8, state.current_file.?, path)) {
                        if (state.had_output) {
                            stdout.print("\n", .{}) catch {};
                        }
                        state.current_file = path;
                        state.current_hunk_start = 0;
                        state.current_hunk_end = 0;
                    }
                }
            }
            return 0;
        }

        // Hunk header - track line numbers
        if (origin == c.GIT_DIFF_LINE_HUNK_HDR) {
            if (hunk) |h| {
                // Print file:line header
                if (state.current_file) |file| {
                    const start = if (h.old_start > 0) h.old_start else h.new_start;
                    const lines = @max(h.old_lines, h.new_lines);
                    if (lines > 1) {
                        stdout.print("{s}:{d}-{d}\n", .{ file, start, start + lines - 1 }) catch {};
                    } else {
                        stdout.print("{s}:{d}\n", .{ file, start }) catch {};
                    }
                    state.had_output = true;
                }
            }
            return 0;
        }

        // Actual diff lines
        if (origin == c.GIT_DIFF_LINE_ADDITION or origin == c.GIT_DIFF_LINE_DELETION) {
            const prefix: u8 = if (origin == c.GIT_DIFF_LINE_ADDITION) '+' else '-';
            const content = if (l.content) |cont| cont[0..@intCast(l.content_len)] else "";

            // Trim trailing newline if present
            const trimmed = std.mem.trimRight(u8, content, "\n\r");
            stdout.print("{c} {s}\n", .{ prefix, trimmed }) catch {};
            state.had_output = true;
        }
    }

    return 0;
}
