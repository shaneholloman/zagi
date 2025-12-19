# Architecture

## Overview

zagi is a Zig binary that wraps git commands. It uses libgit2 for git operations rather than shelling out to git, which provides better control over output formatting.

## Components

```
src/
  main.zig           # entry point, command routing
  passthrough.zig    # delegates to git CLI
  cmds/
    git.zig          # shared utilities (status markers, etc)
    status.zig       # git status
    log.zig          # git log
    diff.zig         # git diff
    add.zig          # git add
    commit.zig       # git commit
    alias.zig        # zagi alias (shell setup)
```

## Command flow

1. Parse command line args
2. Check for `-g` flag - if present, pass through to git
3. Route to command handler based on first arg
4. If no handler exists, pass through to git
5. Command handler uses libgit2 to perform operation
6. Format output in concise style
7. Return appropriate exit code

## libgit2 integration

Zagi uses libgit2 via Zig's C interop:

```zig
const c = @cImport(@cInclude("git2.h"));
```

This provides:
- Direct repository access without subprocess overhead
- Fine-grained control over output formatting
- Consistent behavior across platforms

## Error handling

Commands return errors to main.zig rather than calling exit directly:

```zig
pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) git.Error!void {
    // return errors, don't exit
}
```

This enables unit testing and centralizes exit code handling.

## Testing

Two levels of tests:

1. Zig unit tests - test pure functions (formatters, parsers)
2. TypeScript integration tests - test end-to-end behavior via `bench/`

The integration tests create temporary git repos and verify output format and correctness.
