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

describe("zagi status", () => {
  test("produces smaller output than git status", () => {
    const zagi = runCommand(ZAGI_BIN, ["status"]);
    const git = runCommand("git", ["status"]);

    expect(zagi.length).toBeLessThan(git.length);
  });

  test("shows branch name", () => {
    const result = runCommand(ZAGI_BIN, ["status"]);
    expect(result).toMatch(/^branch: \w+/);
  });

  test("detects modified files", () => {
    const zagi = runCommand(ZAGI_BIN, ["status"]);
    const git = runCommand("git", ["status", "--porcelain"]);

    const gitHasModified = git.includes(" M ");
    const zagiHasModified = zagi.includes("modified:");

    expect(zagiHasModified).toBe(gitHasModified);
  });

  test("detects untracked files", () => {
    const zagi = runCommand(ZAGI_BIN, ["status"]);
    const git = runCommand("git", ["status", "--porcelain"]);

    const gitHasUntracked = git.includes("??");
    const zagiHasUntracked = zagi.includes("untracked:");

    expect(zagiHasUntracked).toBe(gitHasUntracked);
  });
});
