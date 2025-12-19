import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { resolve } from "path";
import { writeFileSync, rmSync } from "fs";
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

function stageTestFile() {
  const testFile = resolve(REPO_DIR, "commit-test.txt");
  writeFileSync(testFile, `test content ${Date.now()}\n`);
  execFileSync("git", ["add", "commit-test.txt"], { cwd: REPO_DIR });
}

beforeEach(() => {
  REPO_DIR = createFixtureRepo();
});

afterEach(() => {
  if (REPO_DIR) {
    rmSync(REPO_DIR, { recursive: true, force: true });
  }
});

describe("zagi commit", () => {
  test("commits staged changes with message", () => {
    stageTestFile();
    const result = runCommand(ZAGI_BIN, ["commit", "-m", "Test commit"]);

    expect(result.output).toContain("committed:");
    expect(result.output).toContain("Test commit");
    expect(result.output).toMatch(/[0-9a-f]{7}/); // hash
    expect(result.exitCode).toBe(0);
  });

  test("shows file count and stats", () => {
    stageTestFile();
    const result = runCommand(ZAGI_BIN, ["commit", "-m", "Test with stats"]);

    expect(result.output).toMatch(/\d+ file/);
    expect(result.output).toMatch(/\+\d+/); // insertions
    expect(result.output).toMatch(/-\d+/); // deletions
  });

  test("error when nothing staged", () => {
    const result = runCommand(ZAGI_BIN, ["commit", "-m", "Empty commit"], true);

    expect(result.output).toBe("error: nothing to commit\n");
    expect(result.exitCode).toBe(1);
  });

  test("shows usage when no message provided", () => {
    stageTestFile();
    const result = runCommand(ZAGI_BIN, ["commit"], true);

    expect(result.output).toContain("usage:");
    expect(result.output).toContain("-m");
    expect(result.exitCode).toBe(1);
  });

  test("supports -m flag with equals sign", () => {
    stageTestFile();
    const result = runCommand(ZAGI_BIN, ["commit", "--message=Equals format"]);

    expect(result.output).toContain("Equals format");
    expect(result.exitCode).toBe(0);
  });

  test("zagi commit output is more concise than git", () => {
    // Stage and commit with zagi first
    stageTestFile();
    const zagiResult = runCommand(ZAGI_BIN, ["commit", "-m", "Zagi commit"]);

    // Stage another file and commit with git
    const testFile2 = resolve(REPO_DIR, "commit-test-2.txt");
    writeFileSync(testFile2, `test content 2 ${Date.now()}\n`);
    execFileSync("git", ["add", "commit-test-2.txt"], { cwd: REPO_DIR });
    const gitResult = runCommand("git", ["commit", "-m", "Git commit"]);

    // zagi should have shorter output
    expect(zagiResult.output.length).toBeLessThan(gitResult.output.length);

    console.log("\nOutput comparison:");
    console.log(`  zagi: ${zagiResult.output.length} bytes`);
    console.log(`  git:  ${gitResult.output.length} bytes`);
    console.log(
      `  reduction: ${(
        ((gitResult.output.length - zagiResult.output.length) /
          gitResult.output.length) *
        100
      ).toFixed(0)}%`
    );
  });
});

describe("performance", () => {
  test("zagi commit is reasonably fast", () => {
    const iterations = 5;
    const times: number[] = [];

    for (let i = 0; i < iterations; i++) {
      // Stage a unique file for each iteration
      const testFile = resolve(REPO_DIR, `perf-test-${i}.txt`);
      writeFileSync(testFile, `perf test ${i} ${Date.now()}\n`);
      execFileSync("git", ["add", `perf-test-${i}.txt`], { cwd: REPO_DIR });

      const start = performance.now();
      execFileSync(ZAGI_BIN, ["commit", "-m", `Perf test ${i}`], {
        cwd: REPO_DIR,
      });
      times.push(performance.now() - start);
    }

    const avg = times.reduce((a, b) => a + b, 0) / times.length;
    const min = Math.min(...times);
    const max = Math.max(...times);

    console.log(`\nPerformance (${iterations} iterations):`);
    console.log(`  Average: ${avg.toFixed(2)}ms`);
    console.log(`  Min: ${min.toFixed(2)}ms`);
    console.log(`  Max: ${max.toFixed(2)}ms`);

    // Should complete in under 200ms on average
    expect(avg).toBeLessThan(200);
  });
});
