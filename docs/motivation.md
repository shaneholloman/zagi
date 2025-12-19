# Motivation

## The problem

AI agents interact with git constantly. Every git command consumes tokens from the context window. Standard git output is designed for humans reading terminals, not agents parsing text.

### Context window pressure

A single `git log` can output thousands of tokens. In a typical coding session, an agent might check status, view logs, diff changes, and commit dozens of times. The cumulative token cost is significant.

### Verbose output

git's output includes decorative elements useful for humans but wasteful for agents:

- Full commit hashes (40 chars) when short hashes (7 chars) suffice
- Author email addresses
- Timezone-specific date formats
- Instructional hints ("use git add to stage")

### Parsing complexity

Standard git output varies by command and flag combinations. Agents must handle many formats, increasing error potential.

## The solution

zagi wraps git with agent-optimized output:

| git output                             | zagi output            |
| -------------------------------------- | ---------------------- |
| `commit abc123...` (40 chars)          | `abc123f` (7 chars)    |
| `Author: Alice <alice@x.com>`          | `Alice:`               |
| `Date: Mon Jan 15 14:32:21 2025 -0800` | `(2025-01-15)`         |
| Multi-line with blank separators       | Single line per commit |

### Design principles

1. Concise by default - every byte counts
2. Git-compatible - same commands, different output
3. Passthrough fallback - `-g` flag for full git output
4. No config files - works out of the box
5. No state - stateless operations that can be retried
6. Every command is the begining and the end, there is no interactivity
