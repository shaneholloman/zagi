import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { resolve } from "path";
import { rmSync } from "fs";
import { createFixtureRepo } from "../fixtures/setup";

const ZAGI_BIN = resolve(__dirname, "../../zig-out/bin/zagi");
let REPO_DIR: string;

function runCommand(cmd: string, args: string[]): string {
  return execFileSync(cmd, args, {
    cwd: REPO_DIR,
    encoding: "utf-8",
  });
}

beforeEach(() => {
  REPO_DIR = createFixtureRepo();
});

afterEach(() => {
  if (REPO_DIR) {
    rmSync(REPO_DIR, { recursive: true, force: true });
  }
});

describe("zagi log", () => {
  test("produces smaller output than git log", () => {
    const zagi = runCommand(ZAGI_BIN, ["log"]);
    const git = runCommand("git", ["log", "-n", "10"]);

    expect(zagi.length).toBeLessThan(git.length);
  });

  test("defaults to 10 commits", () => {
    const result = runCommand(ZAGI_BIN, ["log"]);
    const commitLines = result.split("\n").filter((l) => /^[a-f0-9]{7} /.test(l));
    expect(commitLines.length).toBeLessThanOrEqual(10);
  });

  test("respects -n flag", () => {
    const result = runCommand(ZAGI_BIN, ["log", "-n", "3"]);
    const commitLines = result.split("\n").filter((l) => /^[a-f0-9]{7} /.test(l));
    expect(commitLines.length).toBeLessThanOrEqual(3);
  });

  test("--full produces verbose output", () => {
    const concise = runCommand(ZAGI_BIN, ["log", "-n", "1"]);
    const full = runCommand(ZAGI_BIN, ["log", "--full", "-n", "1"]);

    expect(full.length).toBeGreaterThan(concise.length);
    expect(full).toContain("Author:");
    expect(full).toContain("Date:");
  });

  test("output format matches spec", () => {
    const result = runCommand(ZAGI_BIN, ["log", "-n", "1"]);
    // Format: abc123f (2025-01-15) Alice: Subject line
    const line = result.split("\n")[0];
    expect(line).toMatch(/^[a-f0-9]{7} \(\d{4}-\d{2}-\d{2}\) \w+: .+$/);
  });
});
