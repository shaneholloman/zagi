# Features

## Implemented commands

### git status

Shows repository state in compact form.

```
branch: main (+2/-1 origin/main)

staged: 2 files
  A  new-file.txt
  M  modified.txt

modified: 1 file
  M  unstaged.txt

untracked: 3 files
```

### git log

Shows commit history, default 10 commits.

```
abc123f (2025-01-15) Alice: Add authentication
def456a (2025-01-14) Bob: Fix connection pool

[8 more commits, use -n to see more]
```

Options:
- `-n <count>` - number of commits to show

### git diff

Shows changes in minimal format.

```
src/main.zig:42
+ const new_line = true;
- const old_line = false;

src/other.zig:10-15
+ added block
+ of code
```

Options:
- `--staged` - show staged changes
- `<commit>` - diff against commit
- `<commit>..<commit>` - diff between commits
- `<commit>...<commit>` - diff since branches diverged
- `-- <path>` - filter to specific paths

### git add

Stages files and confirms what was staged.

```
staged: 3 files
  A  new-file.txt
  M  changed-file.txt
  M  another.txt
```

### git commit

Creates commit and shows stats.

```
committed: abc123f "Add new feature"
  3 files, +45 -12
```

Options:
- `-m <message>` - commit message (required)
- `-a` - stage modified tracked files
- `--amend` - amend previous commit

## Passthrough

Any command not implemented passes through to git:

```bash
git push           # runs git push
git pull           # runs git pull
git rebase -i      # runs git rebase -i
```

Use `-g` to force passthrough for implemented commands:

```bash
git -g log         # runs git log (full output)
git -g status      # runs git status (full output)
```

## Shell alias

The `zagi alias` command sets up git as an alias:

```bash
zagi alias         # adds alias to shell config
zagi alias --print # prints alias without adding
```

Supported shells: bash, zsh, fish, powershell
