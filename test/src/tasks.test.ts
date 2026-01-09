import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { rmSync } from "fs";
import { createFixtureRepo } from "../fixtures/setup";
import { zagi, git } from "./shared";

let REPO_DIR: string;

beforeEach(() => {
  REPO_DIR = createFixtureRepo();
});

afterEach(() => {
  if (REPO_DIR) {
    rmSync(REPO_DIR, { recursive: true, force: true });
  }
});

describe("zagi tasks help", () => {
  test("shows help message", () => {
    const result = zagi(["tasks"], { cwd: REPO_DIR });

    expect(result).toContain("usage: git tasks <command>");
    expect(result).toContain("Commands:");
    expect(result).toContain("add <content>");
    expect(result).toContain("list");
    expect(result).toContain("show <id>");
    expect(result).toContain("done <id>");
  });

  test("help flag shows help", () => {
    const result = zagi(["tasks", "--help"], { cwd: REPO_DIR });

    expect(result).toContain("usage: git tasks <command>");
  });
});

describe("zagi tasks add", () => {
  test("creates new task with generated ID", () => {
    const result = zagi(["tasks", "add", "Fix authentication bug"], { cwd: REPO_DIR });

    expect(result).toMatch(/created: task-\d{3}/);
    expect(result).toContain("Fix authentication bug");
  });

  test("handles multi-word content", () => {
    const result = zagi(["tasks", "add", "Add", "user", "authentication", "system"], { cwd: REPO_DIR });

    expect(result).toContain("Add user authentication system");
  });

  test("creates task with dependency using --after", () => {
    // First create a task to depend on
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });

    expect(result).toMatch(/created: task-\d{3}/);
    expect(result).toContain("Dependent task");
  });

  test("outputs JSON when --json flag is used", () => {
    const result = zagi(["tasks", "add", "Test task", "--json"], { cwd: REPO_DIR });

    const parsed = JSON.parse(result.trim());
    expect(parsed).toHaveProperty("id");
    expect(parsed).toHaveProperty("content", "Test task");
    expect(parsed).toHaveProperty("status", "pending");
    expect(parsed).toHaveProperty("created");
    expect(parsed).toHaveProperty("completed", null);
  });

  test("creates task with dependency in JSON format", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "add", "Dependent task", "--after", "task-001", "--json"], { cwd: REPO_DIR });

    const parsed = JSON.parse(result.trim());
    expect(parsed).toHaveProperty("after", "task-001");
  });

  test("error for missing content", () => {
    const result = zagi(["tasks", "add"], { cwd: REPO_DIR });

    expect(result).toContain("error: missing task content");
  });

  test("error for empty content", () => {
    const result = zagi(["tasks", "add", ""], { cwd: REPO_DIR });

    expect(result).toContain("error: task content cannot be empty");
  });

  test("error for --after without task ID", () => {
    const result = zagi(["tasks", "add", "Test task", "--after"], { cwd: REPO_DIR });

    expect(result).toContain("error: --after requires a task ID");
  });
});

describe("zagi tasks list", () => {
  test("shows no tasks message when empty", () => {
    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("no tasks found");
  });

  test("lists single task", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("tasks: 1 total (1 pending, 0 completed)");
    expect(result).toContain("[ ] task-001");
    expect(result).toContain("Test task");
  });

  test("lists multiple tasks with counts", () => {
    zagi(["tasks", "add", "First task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Second task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("tasks: 2 total (1 pending, 1 completed)");
    expect(result).toContain("[✓] task-001");
    expect(result).toContain("[ ] task-002");
  });

  test("shows task dependencies", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("[ ] task-002 (after task-001)");
  });

  test("outputs JSON when --json flag is used", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list", "--json"], { cwd: REPO_DIR });

    const parsed = JSON.parse(result.trim());
    expect(parsed).toHaveProperty("tasks");
    expect(Array.isArray(parsed.tasks)).toBe(true);
    expect(parsed.tasks).toHaveLength(1);
    expect(parsed.tasks[0]).toHaveProperty("id", "task-001");
    expect(parsed.tasks[0]).toHaveProperty("content", "Test task");
  });

  test("JSON output includes all task fields", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list", "--json"], { cwd: REPO_DIR });

    const parsed = JSON.parse(result.trim());
    const baseTask = parsed.tasks.find((t: any) => t.id === "task-001");
    const depTask = parsed.tasks.find((t: any) => t.id === "task-002");

    expect(baseTask).toHaveProperty("status", "completed");
    expect(baseTask).toHaveProperty("completed");
    expect(baseTask.completed).not.toBeNull();

    expect(depTask).toHaveProperty("after", "task-001");
    expect(depTask).toHaveProperty("status", "pending");
  });
});

describe("zagi tasks show", () => {
  test("shows task details", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "show", "task-001"], { cwd: REPO_DIR });

    expect(result).toContain("task: task-001");
    expect(result).toContain("content: Test task");
    expect(result).toContain("status: pending");
    expect(result).toContain("created:");
  });

  test("shows completed task details", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "show", "task-001"], { cwd: REPO_DIR });

    expect(result).toContain("status: completed");
    expect(result).toContain("completed:");
  });

  test("shows task dependency", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "show", "task-002"], { cwd: REPO_DIR });

    expect(result).toContain("depends on: task-001");
  });

  test("outputs JSON when --json flag is used", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "show", "task-001", "--json"], { cwd: REPO_DIR });

    const parsed = JSON.parse(result.trim());
    expect(parsed).toHaveProperty("id", "task-001");
    expect(parsed).toHaveProperty("content", "Test task");
    expect(parsed).toHaveProperty("status", "pending");
  });

  test("error for missing task ID", () => {
    const result = zagi(["tasks", "show"], { cwd: REPO_DIR });

    expect(result).toContain("error: missing task ID");
  });

  test("error for non-existent task", () => {
    const result = zagi(["tasks", "show", "task-999"], { cwd: REPO_DIR });

    expect(result).toContain("error: task 'task-999' not found");
  });
});

describe("zagi tasks done", () => {
  test("marks task as completed", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    expect(result).toContain("completed: task-001");
    expect(result).toContain("Test task");
  });

  test("task appears as completed in list", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("[✓] task-001");
    expect(result).toContain("(0 pending, 1 completed)");
  });

  test("already completed task message", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    expect(result).toContain("task 'task-001' already completed");
  });

  test("error for missing task ID", () => {
    const result = zagi(["tasks", "done"], { cwd: REPO_DIR });

    expect(result).toContain("error: missing task ID");
  });

  test("error for non-existent task", () => {
    const result = zagi(["tasks", "done", "task-999"], { cwd: REPO_DIR });

    expect(result).toContain("error: task 'task-999' not found");
  });
});

describe("zagi tasks ready", () => {
  test("shows no ready tasks when empty", () => {
    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("no tasks found");
  });

  test("shows single ready task", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("ready: 1 task");
    expect(result).toContain("[ ] task-001");
    expect(result).toContain("Test task");
  });

  test("excludes blocked tasks", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Independent task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("ready: 2 tasks");
    expect(result).toContain("[ ] task-001");
    expect(result).toContain("[ ] task-003");
    expect(result).not.toContain("task-002");
  });

  test("includes tasks with completed dependencies", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("ready: 1 task");
    expect(result).toContain("[ ] task-002");
    expect(result).toContain("Dependent task");
  });

  test("excludes completed tasks", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("no ready tasks");
  });

  test("handles plural form correctly", () => {
    zagi(["tasks", "add", "First task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Second task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "ready"], { cwd: REPO_DIR });

    expect(result).toContain("ready: 2 tasks");
  });
});

describe("zagi tasks pr", () => {
  test("shows empty state when no tasks", () => {
    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    expect(result).toContain("## Tasks");
    expect(result).toContain("No tasks found.");
  });

  test("shows completed tasks section", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    expect(result).toContain("## Tasks");
    expect(result).toContain("### Completed");
    expect(result).toContain("- [x] Test task");
  });

  test("shows ready tasks section", () => {
    zagi(["tasks", "add", "Ready task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    expect(result).toContain("### Ready");
    expect(result).toContain("- [ ] Ready task");
  });

  test("shows blocked tasks section", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Blocked task", "--after", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    expect(result).toContain("### Ready");
    expect(result).toContain("- [ ] Base task");
    expect(result).toContain("### Blocked");
    expect(result).toContain("- [ ] Blocked task (after task-001)");
  });

  test("shows dependencies in completed tasks", () => {
    zagi(["tasks", "add", "Base task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Dependent task", "--after", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "done", "task-002"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    expect(result).toContain("- [x] Base task");
    expect(result).toContain("- [x] Dependent task (after task-001)");
  });

  test("comprehensive mixed state", () => {
    // Create complex task hierarchy
    zagi(["tasks", "add", "Foundation"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Build on foundation", "--after", "task-001"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Independent work"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Final step", "--after", "task-002"], { cwd: REPO_DIR });

    // Complete foundation
    zagi(["tasks", "done", "task-001"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "pr"], { cwd: REPO_DIR });

    // Should have all sections
    expect(result).toContain("### Completed");
    expect(result).toContain("- [x] Foundation");

    expect(result).toContain("### Ready");
    expect(result).toContain("- [ ] Build on foundation");
    expect(result).toContain("- [ ] Independent work");

    expect(result).toContain("### Blocked");
    expect(result).toContain("- [ ] Final step (after task-002)");
  });
});

describe("zagi tasks edit", () => {
  test("blocked in agent mode", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "edit", "task-001", "Updated content"], {
      cwd: REPO_DIR,
      env: { ZAGI_AGENT: "claude-code" }
    });

    expect(result).toContain("error: edit command blocked");
    expect(result).toContain("ZAGI_AGENT is set");
  });

  test("works when not in agent mode", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "edit", "task-001", "Updated content"], { cwd: REPO_DIR });

    expect(result).toContain("updated: task-001");
    expect(result).toContain("Updated content");
  });
});

describe("zagi tasks delete", () => {
  test("blocked in agent mode", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "delete", "task-001"], {
      cwd: REPO_DIR,
      env: { ZAGI_AGENT: "claude-code" }
    });

    expect(result).toContain("error: delete command blocked");
    expect(result).toContain("ZAGI_AGENT is set");
    expect(result).toContain("permanent data loss");
  });

  test("works when not in agent mode", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "delete", "task-001"], { cwd: REPO_DIR });

    expect(result).toContain("deleted: task-001");
  });
});

describe("error handling", () => {
  test("invalid subcommand shows error and help", () => {
    const result = zagi(["tasks", "invalid"], { cwd: REPO_DIR });

    expect(result).toContain("error: unknown command 'invalid'");
    expect(result).toContain("usage: git tasks <command>");
  });

  test("task IDs are sequential", () => {
    zagi(["tasks", "add", "First task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Second task"], { cwd: REPO_DIR });
    zagi(["tasks", "add", "Third task"], { cwd: REPO_DIR });

    const result = zagi(["tasks", "list"], { cwd: REPO_DIR });

    expect(result).toContain("task-001");
    expect(result).toContain("task-002");
    expect(result).toContain("task-003");
  });

  test("works in non-git directory", () => {
    const result = zagi(["tasks", "add", "Test task"], { cwd: "/tmp" });

    // libgit2 outputs "fatal:" for non-repo errors
    expect(result.toLowerCase()).toMatch(/error|fatal/);
  });
});

describe("performance", () => {
  test("zagi tasks operations are reasonably fast", () => {
    // Create several tasks
    const start = Date.now();

    for (let i = 1; i <= 10; i++) {
      zagi(["tasks", "add", `Task ${i}`], { cwd: REPO_DIR });
    }

    zagi(["tasks", "list"], { cwd: REPO_DIR });

    const elapsed = Date.now() - start;

    // Should complete 10 add operations + 1 list in under 5 seconds
    // This is quite generous, but we want to catch major performance regressions
    expect(elapsed).toBeLessThan(5000);
  });

  test("task storage persists across commands", () => {
    zagi(["tasks", "add", "Persistent task"], { cwd: REPO_DIR });

    const firstList = zagi(["tasks", "list"], { cwd: REPO_DIR });
    expect(firstList).toContain("Persistent task");

    zagi(["tasks", "add", "Another task"], { cwd: REPO_DIR });

    const secondList = zagi(["tasks", "list"], { cwd: REPO_DIR });
    expect(secondList).toContain("Persistent task");
    expect(secondList).toContain("Another task");
    expect(secondList).toContain("tasks: 2 total");
  });
});

describe("integration with git", () => {
  test("tasks are stored in git refs", () => {
    zagi(["tasks", "add", "Test task"], { cwd: REPO_DIR });

    // Check that git refs/tasks/main exists
    const result = git(["show-ref"], { cwd: REPO_DIR });
    expect(result).toContain("refs/tasks/main");
  });

  test("tasks persist across branch switches", () => {
    // Add task on main
    zagi(["tasks", "add", "Main branch task"], { cwd: REPO_DIR });

    // Create and switch to new branch
    git(["checkout", "-b", "feature"], { cwd: REPO_DIR });

    // Add task on feature branch
    zagi(["tasks", "add", "Feature branch task"], { cwd: REPO_DIR });

    // Switch back to main
    git(["checkout", "main"], { cwd: REPO_DIR });

    // Should only see main branch task
    const mainTasks = zagi(["tasks", "list"], { cwd: REPO_DIR });
    expect(mainTasks).toContain("Main branch task");
    expect(mainTasks).not.toContain("Feature branch task");

    // Switch to feature branch
    git(["checkout", "feature"], { cwd: REPO_DIR });

    // Should only see feature branch task
    const featureTasks = zagi(["tasks", "list"], { cwd: REPO_DIR });
    expect(featureTasks).toContain("Feature branch task");
    expect(featureTasks).not.toContain("Main branch task");
  });
});