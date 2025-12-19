# Style Guide

## Naming

- zagi is always lowercase, even at the start of a sentence
- git is always lowercase

## Documentation

- No emojis
- Minimal formatting - use plain text where possible
- Code blocks for commands and output examples
- Tables only when comparing things side by side

## Code

- Zig standard library naming conventions
- snake_case for functions and variables
- PascalCase for types
- Return errors rather than calling exit() in command modules

## Output messages

- Lowercase, no trailing punctuation
- Concise - every word must earn its place
- Show what happened, not instructions on what to do next

Good:
```
staged: 3 files
committed: abc123f "message"
error: file not found
```

Bad:
```
Successfully staged 3 files!
Use git commit to commit your changes.
ERROR: The file was not found.
```

## Help text

- Use `git` not `zagi` in usage examples (users alias git to zagi)
- Exception: `zagi alias` since it must be run as zagi
