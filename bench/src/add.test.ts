import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { resolve } from "path";
import { rmSync } from "fs";
import { createFixtureRepo } from "../fixtures/setup";

const ZAGI_BIN = resolve(__dirname, "../../zig-out/bin/zagi");
let REPO_DIR: string;

interface CommandResult {
  output: string;
  duration: number;
  exitCode: number;
}

function runCommand(
  cmd: string,
  args: string[],
  expectFail = false
): CommandResult {
  const start = performance.now();
  try {
    const output = execFileSync(cmd, args, {
      cwd: REPO_DIR,
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024,
    });
    return {
      output,
      duration: performance.now() - start,
      exitCode: 0,
    };
  } catch (e: any) {
    if (!expectFail) throw e;
    return {
      output: e.stderr || e.stdout || "",
      duration: performance.now() - start,
      exitCode: e.status || 1,
    };
  }
}

function reset() {
  try {
    execFileSync("git", ["reset", "HEAD", "."], { cwd: REPO_DIR });
  } catch {}
}

beforeEach(() => {
  REPO_DIR = createFixtureRepo();
});

afterEach(() => {
  reset();
  if (REPO_DIR) {
    rmSync(REPO_DIR, { recursive: true, force: true });
  }
});

describe("zagi add", () => {
  test("shows confirmation after adding file", () => {
    const result = runCommand(ZAGI_BIN, ["add", "src/new-file.ts"]);

    expect(result.output).toContain("staged:");
    expect(result.output).toContain("A ");
    expect(result.output).toContain("new-file.ts");
  });

  test("shows count of staged files", () => {
    const result = runCommand(ZAGI_BIN, ["add", "src/new-file.ts"]);

    expect(result.output).toMatch(/staged: \d+ file/);
  });

  test("error message is concise for missing file", () => {
    const zagi = runCommand(ZAGI_BIN, ["add", "nonexistent.txt"], true);

    expect(zagi.output).toBe("error: file not found\n");
    expect(zagi.exitCode).toBe(128);
  });

  test("git add is silent on success", () => {
    const git = runCommand("git", ["add", "src/new-file.ts"]);

    // git add produces no output on success
    expect(git.output).toBe("");
  });

  test("zagi add provides feedback while git add is silent", () => {
    const zagi = runCommand(ZAGI_BIN, ["add", "src/new-file.ts"]);
    reset();
    const git = runCommand("git", ["add", "src/new-file.ts"]);

    expect(zagi.output.length).toBeGreaterThan(0);
    expect(git.output.length).toBe(0);
  });
});

describe("performance", () => {
  test("zagi add is reasonably fast", () => {
    const iterations = 10;
    const times: number[] = [];

    for (let i = 0; i < iterations; i++) {
      reset();
      const start = performance.now();
      execFileSync(ZAGI_BIN, ["add", "src/new-file.ts"], { cwd: REPO_DIR });
      times.push(performance.now() - start);
    }

    const avg = times.reduce((a, b) => a + b, 0) / times.length;
    const min = Math.min(...times);
    const max = Math.max(...times);

    console.log(`\nPerformance (${iterations} iterations):`);
    console.log(`  Average: ${avg.toFixed(2)}ms`);
    console.log(`  Min: ${min.toFixed(2)}ms`);
    console.log(`  Max: ${max.toFixed(2)}ms`);

    // Should complete in under 100ms on average
    expect(avg).toBeLessThan(100);
  });
});
