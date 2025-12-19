import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { resolve } from "path";
import { rmSync, writeFileSync, readFileSync } from "fs";
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

describe("zagi diff", () => {
  test("produces smaller output than git diff", () => {
    const zagi = runCommand(ZAGI_BIN, ["diff"]);
    const git = runCommand("git", ["diff"]);

    expect(zagi.length).toBeLessThan(git.length);
  });

  test("shows file path with line number", () => {
    const result = runCommand(ZAGI_BIN, ["diff"]);
    // Format: path/to/file.ts:123
    expect(result).toMatch(/^[\w/.-]+:\d+/m);
  });

  test("shows additions with + prefix", () => {
    const result = runCommand(ZAGI_BIN, ["diff"]);
    expect(result).toMatch(/^\+ /m);
  });

  test("shows deletions with - prefix", () => {
    // Remove a line to create a deletion
    const filePath = resolve(REPO_DIR, "src/main.ts");
    const content = readFileSync(filePath, "utf-8");
    const lines = content.split("\n");
    lines.splice(5, 1); // Remove line 6
    writeFileSync(filePath, lines.join("\n"));

    const result = runCommand(ZAGI_BIN, ["diff"]);
    expect(result).toMatch(/^- /m);
  });

  test("--staged shows staged changes", () => {
    // Stage the existing modified file
    execFileSync("git", ["add", "src/main.ts"], { cwd: REPO_DIR });

    const result = runCommand(ZAGI_BIN, ["diff", "--staged"]);
    expect(result).toContain("src/main.ts");
  });

  test("no changes shows 'no changes'", () => {
    // Reset all changes
    execFileSync("git", ["checkout", "--", "."], { cwd: REPO_DIR });
    execFileSync("git", ["clean", "-fd"], { cwd: REPO_DIR });

    const result = runCommand(ZAGI_BIN, ["diff"]);
    expect(result).toBe("no changes\n");
  });
});
