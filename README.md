# zagi

> a better git for agents

### Context Window
- Traditional `git log` outputs are verbose and consume significant token space
- Large repositories with extensive commit histories quickly exhaust agent context windows
- Agents need to process Git information frequently, making every byte count

### Reliability
- Agents lack robust retry mechanisms and can get stuck on recoverable failures
- Non-idempotent operations create inconsistent states when retried blindly

### Interactivity
- Zagi is not interactive, it is designed for agents. They can compose abitarily complex commands and zagi will execute them idempotently.

### Training Data
- Agents are pre-trained on standard Git command syntax
- Custom tools with different interfaces require additional prompting and reduce reliability
- Breaking from familiar patterns increases error rates and confusion

## Solution

**zagi** is an agent-optimized Git wrapper that addresses these challenges while maintaining full compatibility with standard Git interfaces:

### Truncated Output by Default
- Intelligent output truncation optimized for agent consumption
- Essential information prioritized, verbose details suppressed
- Configurable truncation levels for different use cases
- Preserves critical data while minimizing token usage

### Idempotent Operations
- All operations designed to be safely retried without side effects
- Automatic detection and handling of transient failures
- Built-in retry logic with exponential backoff
- State verification before and after operations

### Git-Compatible Interface
- Identical command syntax to standard Git (`zagi log` = `git log`)
- Drop-in replacement requiring no agent retraining
- Leverages existing agent knowledge of Git commands
- Familiar error messages and output formats

### Zig Implementation
- Compiled to small, standalone binaries (~1-2MB)
- Near-native performance for fast execution
- No runtime dependencies (vs Node.js, Python, etc.)
- Cross-platform support (Linux, macOS, Windows)
- Easy distribution via package managers

## Architecture

### Design Principles

2. **Progressive Enhancement**: Start with high-value commands (log), expand over time
3. **Zero Config**: Sensible defaults that work out of the box
4. **Fail Safe**: On errors, fall back to standard Git behavior
5. **Stateless**: No local state or caching that could become inconsistent

### Output Truncation Strategy

**Priority Levels:**
1. **Critical**: Commit hashes, branch names, current state
2. **High**: Author, date, first line of message
3. **Medium**: Full commit messages, file change stats
4. **Low**: Full diffs, detailed file listings
5. **Minimal**: Verbose metadata, decorative formatting

**Token Budget Algorithm:**
```
1. Estimate available context (user-configurable)
2. Reserve space for critical info (commits, hashes)
3. Allocate remaining budget by priority
4. Truncate from lowest priority first
5. Add continuation markers when truncating
```

## Implementation

### Phase 1: Core Foundation (v0.1.0)

**Objective**: Prove concept with `git log` optimization

#### Features
- Parse `git log` command-line arguments
- Execute native `git log` via subprocess
- Implement basic output truncation:
  - Limit to N most recent commits (default: 10)
  - One-line format by default (`--oneline` style)
  - Include commit hash, author, date, subject
- Error handling and retry logic
- Cross-platform binary builds

#### Success Criteria
- 70%+ reduction in output tokens vs standard `git log`
- <100ms overhead for typical operations
- 100% success rate on retry for transient failures
- Binaries under 2MB per platform

#### Deliverables
```bash
# Basic usage
zagi log                    # Last 10 commits, truncated
zagi log -n 20             # Last 20 commits
zagi log --full            # Disable truncation
zagi log --token-limit 500 # Custom token budget

# Output format
abc123f (2025-01-15) Alice: Add user authentication
def456a (2025-01-14) Bob: Fix database connection pool
...
[8 more commits truncated, use --full to see all]
```

### Phase 2: Enhanced Git Commands (v0.2.0)

**Expand coverage to high-frequency commands:**

- `zagi status`: Truncate long file lists, group by status
- `zagi diff`: Smart diff truncation (context lines, file limits)
- `zagi branch`: List branches with activity indicators
- `zagi show`: Truncate commit details and diffs

**Additional Features:**
- JSON output mode for structured agent consumption
- Configuration file support (`~/.zagirc`)
- Verbosity levels (--quiet, --normal, --verbose)

### Phase 3: Advanced Operations (v0.3.0)

- `zagi reflog`: Recent reflog entries only
- `zagi blame`: File blame with smart pagination
- `zagi stash`: Stash list with descriptions
- Semantic commit grouping (group related commits)
- Automatic change summarization

### Phase 4: Distribution & Polish (v1.0.0)

**Package Managers:**
- Homebrew (macOS/Linux): `brew install zagi`
- apt (Debian/Ubuntu): `apt install zagi`
- Scoop (Windows): `scoop install zagi`
- Cargo: `cargo install zagi`

**Distribution Channels:**
- GitHub Releases with attached binaries
- Docker images for containerized environments
- GitHub Actions integration examples

**Documentation:**
- Full command reference
- Agent integration guides (Claude, GPT, etc.)
- Performance benchmarks
- Migration guide from standard Git

### Technical Stack

**Language**: Zig 0.11+
**Key Libraries**:
- Standard library for subprocess management
- String manipulation and tokenization
- Cross-platform file system operations

**Build System**:
- Zig build system for cross-compilation
- GitHub Actions for CI/CD
- Automated release pipeline

**Testing Strategy**:
- Unit tests for truncation algorithms
- Integration tests with real Git repositories
- Performance benchmarks
- Cross-platform validation

## Examples

### Example 1: Commit History Review

**Standard Git:**
```bash
$ git log
commit abc123f4567890def1234567890abcdef12345
Author: Alice Smith <alice@example.com>
Date:   Mon Jan 15 14:32:21 2025 -0800

    Add user authentication system
    
    Implemented JWT-based authentication with refresh tokens.
    Added middleware for protected routes. Updated user model
    with password hashing using bcrypt. Includes comprehensive
    test coverage for auth flows.
    
    - Added AuthService class
    - Created login/logout endpoints
    - Implemented token refresh mechanism
    - Updated security documentation

commit def456a7890123bce4567890def123456789ab
Author: Bob Jones <bob@example.com>
Date:   Sun Jan 14 09:15:43 2025 -0800

    Fix database connection pool exhaustion
    
    Resolved issue where connections weren't being properly
    released back to the pool under high load conditions...

[Output continues for many screens]
```

**Tokens**: ~2,500 (for 10 commits with full messages)

**With zagi:**
```bash
$ zagi log
abc123f (2025-01-15) Alice: Add user authentication system
def456a (2025-01-14) Bob: Fix database connection pool exhaustion
789beef (2025-01-13) Carol: Update API documentation
456cafe (2025-01-12) Dave: Refactor payment processing
123dead (2025-01-11) Alice: Add rate limiting middleware
890face (2025-01-10) Bob: Optimize database queries
567fade (2025-01-09) Carol: Fix CORS configuration
234bead (2025-01-08) Dave: Update dependencies
901cede (2025-01-07) Alice: Add logging middleware
678deed (2025-01-06) Bob: Fix memory leak in websocket handler

[Showing 10 most recent commits. Use -n to see more or --full for details]
```

**Tokens**: ~350 (86% reduction)

### Example 2: Repository Status Check

**Standard Git:**
```bash
$ git status
On branch feature/user-profiles
Your branch is up to date with 'origin/feature/user-profiles'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        modified:   src/components/UserProfile.tsx
        modified:   src/components/UserSettings.tsx
        new file:   src/components/AvatarUpload.tsx
        modified:   src/styles/profile.css
        
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   src/utils/imageProcessing.ts
        modified:   src/api/userApi.ts
        
Untracked files:
  (use "git add <file>..." to include in what will be committed)
        src/components/ProfileCard.tsx
        src/components/UserBadge.tsx
        tests/user-profile.test.ts
        tests/avatar-upload.test.ts
```

**With zagi:**
```bash
$ zagi status
branch: feature/user-profiles (up to date)

staged: 4 files
  M src/components/UserProfile.tsx
  M src/components/UserSettings.tsx
  A src/components/AvatarUpload.tsx
  M src/styles/profile.css

modified: 2 files
  M src/utils/imageProcessing.ts
  M src/api/userApi.ts

untracked: 4 files
  ?? src/components/ProfileCard.tsx
  ?? src/components/UserBadge.tsx
  + 2 more (use --full to list all)
```

### Example 3: Agent Workflow Integration

**Typical Agent Task**: "Check recent commits and create a summary"

```python
# With standard git - needs careful output handling
result = subprocess.run(['git', 'log', '-10'], capture_output=True)
commits = result.stdout.decode()  # May exceed context window
# Complex parsing needed...

# With zagi - optimized for agent consumption
result = subprocess.run(['zagi', 'log'], capture_output=True)
commits = result.stdout.decode()  # Always within token budget
# Clean, parseable format ready to use
```

**JSON Mode for Structured Data:**
```bash
$ zagi log --json
{
  "commits": [
    {
      "hash": "abc123f",
      "date": "2025-01-15",
      "author": "Alice",
      "subject": "Add user authentication system"
    },
    ...
  ],
  "truncated": false,
  "total_commits": 10
}
```

### Example 4: Retry Behavior

**Scenario**: Network interruption during fetch operation

**Standard Git:**
```bash
$ git log origin/main
fatal: couldn't find remote ref origin/main
# Agent stuck, needs manual intervention
```

**With zagi:**
```bash
$ zagi log origin/main
[Retry 1/3] Connection failed, retrying in 1s...
[Retry 2/3] Connection failed, retrying in 2s...
abc123f (2025-01-15) Alice: Add user authentication system
...
# Automatic recovery, agent continues workflow
```

### Example 5: Configuration

**~/.zagirc:**
```toml
[output]
default_commit_limit = 15
token_limit = 1000
format = "compact"  # compact, oneline, json

[retry]
max_attempts = 3
backoff_factor = 2
timeout_seconds = 30

[truncation]
show_continuation_marker = true
priority_mode = "agent"  # agent, human, full
```

## Getting Started

### Installation

```bash
# macOS/Linux (Homebrew)
brew install zagi

# From source
git clone https://github.com/mattzcarey/zagi.git
cd zagi
zig build -Drelease-safe
```

### Quick Start

```bash
# Drop-in replacement for git commands
zagi log           # Optimized log output
zagi status        # Truncated status
zagi diff          # Smart diff truncation

# Keep using git for write operations
git add .
git commit -m "Update feature"
git push
```

### Integration with AI Agents

Simply replace `git` with `zagi` in agent tool definitions:

```json
{
  "name": "git_log",
  "description": "View commit history",
  "command": "zagi log"
}
```

No retraining or prompt modifications needed!

---

## Roadmap

- [x] Project conception and PRD
- [ ] Phase 1: Core implementation (v0.1.0)
- [ ] Phase 2: Enhanced commands (v0.2.0)
- [ ] Phase 3: Advanced operations (v0.3.0)
- [ ] Phase 4: Distribution & v1.0 release

## License

MIT License

---

**zagi**: Making Git operations agent-friendly, one command at a time.