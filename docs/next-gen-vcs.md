# Next-Gen VCS: Design Spec

> version control that includes the environment

## One Problem

The gap between `git clone` and "the thing works" is the single biggest
friction in software. Humans spend hours on READMEs. Agents can't even
start. Codespaces and Gitpod attack this with cloud containers, but that's
someone else's machine -- slow, expensive, locked in.

Git tracks your source. npm/pip/cargo track your dependencies. Docker
tracks your system. Nix tracks your environment. Four systems, four mental
models, four places where things go wrong. And a lock file in the middle
holding it all together with string.

**The environment is part of the code. Track it all in one place.**

## One Idea

Version control where everything is tracked. Source, dependencies,
tools, services. No lock files. No install step. No separate package
manager. One system.

```
$ curl -sf zagi.sh | sh
$ zagi clone mattzcarey/zagi
$ cd zagi
$ zig build test    # works. no install. no README.
```

## No Manifests, No Lock Files

The old paradigm has three steps: declare (package.json), resolve
(package-lock.json), install (node_modules). Three places to get
wrong. Three files to keep in sync.

zagi has one step: **add.**

```
$ zagi add node@22

Fetching node 22.0.0 (linux-x64)...
Stored: 42 MB (6,241 chunks, 94% deduped from store)

$ zagi add express@4

Resolving express@4.21.0 + 62 deps...
Stored: 4.2 MB (1,847 chunks, 89% deduped from store)
```

The actual code -- source, binaries, everything -- goes into the
content-addressed store. It's tracked. That's it. No manifest file
declaring what you need. No lock file pinning versions. No install
command fetching things later. The tracked state IS the manifest.

Want to know what your project uses? Ask:

```
$ zagi deps
  node       22.0.0     (tool)
  express    4.21.0     (dep, 62 transitive)
  postgres   16.4       (service)

$ zagi deps express
  express    4.21.0     4.2 MB  1,847 chunks
    accepts@1.3.8, array-flatten@1.1.1, body-parser@1.20.3, ...
```

That's a view into the tracked state, not a file. There's no config
file to get out of sync because there is no config file.

`zagi log` shows deps as changes like any other:

```
$ zagi log
  @  kpqx  matt: wip auth routes
  o  vrnt  matt: add express@4.21.0 (62 deps)
  o  zspm  matt: add node@22
  o  root
```

Revert `vrnt` and express is gone. Checkout a branch that doesn't
have express and it's not there. The dependency history IS the source
history. One graph.

### Edit your dependencies

Want to patch a bug in a dependency? Just edit it.

```
$ zagi edit express         # opens node_modules/express in your editor
                            # or an agent just edits the files directly

$ zagi log
  @  mfpz  matt: fix express body-parser edge case
  o  vrnt  matt: add express@4.21.0 (62 deps)
```

When express releases 4.21.1, you upgrade and your change is
re-applied automatically (jj-style conflict resolution). If it
conflicts, the conflict is data -- you or an agent resolve it.
No patch files. No fork. Just tracked changes on tracked code.

Agents are great at this. "Update express and re-apply our body-parser
fix" is a one-shot prompt.

### Supply chain security

npm install runs arbitrary postinstall scripts from strangers. Every
`npm install` is a supply chain attack waiting to happen.

zagi doesn't run install scripts. It stores source and pre-built
binaries. The code is content-hashed. If someone publishes a
compromised version of a package, it has a different hash. Your
project still points to the original hash. Nothing changes unless
you explicitly upgrade.

No lock file to confuse. No registry to compromise at install time.
No postinstall scripts executing on your machine. The code you
reviewed is the code you run.

## User Experience

### Fresh machine to running project

```
$ curl -sf zagi.sh | sh
$ zagi clone mattzcarey/zagi
$ cd zagi
$ zig build test    # works
```

**Line 1: Install.** Downloads a single static binary. No runtime, no
dependencies, no Nix, no Docker, no FUSE, no sudo. One binary in
`~/.local/bin`. Adds one line to your shell rc:

```bash
eval "$(zagi hook)"
```

The hook activates the environment when you `cd` into a zagi project
(prepends `.zagi/env/bin` to PATH, sets library paths) and deactivates
when you leave.

**Line 2: Clone.** Fetches everything from the content-addressed store:
source, dependencies, tools, services -- all pre-built for your OS/arch.
No manifest to read. No dependencies to resolve. The tracked state tells
zagi exactly what chunks to download.

**Line 3: cd.** Shell hook fires. Environment is active.

**Line 4: Build.** `zig` resolves to `.zagi/env/bin/zig`. Everything
works.

### What agents see

An agent gets pointed at the directory. It sees a normal project where
every tool, every dependency, every service is available. It doesn't
know or care about zagi. It just runs commands and they work.

Need redis for integration tests? It's there. Need to modify a
dependency to debug an issue? Edit it, it's tracked. Need to run the
full test suite against a real database? Postgres is running.

The agent operates in prod-like state by default. No mocks unless you
choose them.

### Day-to-day

```
$ zagi add postgres@16      # adds postgres to the environment
$ zagi add lodash@4         # adds lodash source to deps
$ zagi checkout feature     # switches source AND env atomically

$ zagi log
  @  kpqx  matt: wip feature
  o  vrnt  matt: add lodash@4, postgres@16
  o  main
```

No `npm install`. No `docker-compose up`. No `brew install postgresql`.
Adding a dependency is a change. Switching branches switches everything.

## How Storage Works

Tracking all dependencies and tools means storing a lot of data.
A typical Node project has 200MB+ of node_modules. A Python ML
project can have GBs of packages. This is solvable.

### Content-defined chunking

Borrowed from Hugging Face's Xet storage (which handles 77 PB
across 6M+ repos).

Files are split into ~64KB chunks using a rolling hash (GearHash).
Chunk boundaries are determined by the content itself, so inserting
or modifying part of a file only affects nearby chunks. All other
chunks remain identical.

```
express@4.21.0:
  lib/router/index.js  -> chunks [a3f8, b7e2, c9d1]
  lib/router/route.js  -> chunks [d4e5, f6a7]
  ...

express@4.21.1:
  lib/router/index.js  -> chunks [a3f8, NEW1, c9d1]  # only middle changed
  lib/router/route.js  -> chunks [d4e5, f6a7]         # identical, deduped
```

Upgrading express from 4.21.0 to 4.21.1 stores only the changed
chunks. Everything else deduplicates.

### Cross-project deduplication

10,000 projects use express 4.21.0. The chunks are stored **once**.
Each project references them by hash. Node 22 is Node 22 whether
it's for project A or project B. One copy.

In practice, 70-90% of a clone is already in the store because the
same packages and tools are shared across projects. The first clone
is slow. Every subsequent clone is fast.

### Chunks are grouped into packs

Storing millions of ~64KB chunks as individual objects in S3 would
be expensive. Chunks are grouped into ~64MB packs (like HF's xorbs).
Downloads use HTTP Range requests to fetch specific chunks within a
pack. Keeps object count manageable, enables CDN caching.

```
s3://zagi/
  packs/
    ab/cdef1234.pack    # ~1024 chunks, ~64MB
    cd/ef5678.pack
  manifests/
    mattzcarey/zagi/main.manifest    # maps paths to chunk hashes
```

### Clone size vs install time

| Today | With zagi |
|-------|-----------|
| Clone: 5MB (source only) | Clone: 50MB (source + deps + tools) |
| Then: npm install (200MB, 30s) | Then: nothing |
| Then: brew install postgres (100MB) | |
| Then: read README, configure env | |
| Total: 300MB, 5 minutes | Total: 50MB (deduped), 10 seconds |

The clone is bigger but the total is smaller because there's no
install step, and cross-project dedup means most chunks are already
local.

### Lazy fetching

Not everything needs to be downloaded on clone. The manifest lists
all files and their chunk hashes. zagi can fetch lazily:

- Tools and runtime: fetched immediately (you need these to build)
- Direct dependencies: fetched immediately (you need these to run)
- Transitive deps: fetched on first access
- Dev dependencies: fetched when you run tests
- Large assets: fetched on demand

This keeps initial clone fast while still having everything available.

## Architecture

### Dumb client, smart server

The client is a single static binary. It does:
1. Download chunks from the server/CDN
2. Assemble files from chunks
3. Set PATH when you cd into a project

No package manager, no solver, no build system on the client.

### The server

The server has Nix. When `zagi add node@22` or `zagi add express@4`
is run, the server:

1. Resolves the package and transitive deps
2. Builds or fetches pre-built binaries (Nix binary cache)
3. Chunks the result (content-defined chunking)
4. Deduplicates against the global store
5. Stores new chunks in packs, returns chunk hashes to client

For mirrored repos, the server reads existing lockfiles to figure
out what to resolve and add.

### Object storage

Everything lives in S3/R2/GCS:

```
s3://zagi/
  packs/                         # chunked content
    ab/cdef1234.pack
  manifests/                     # path -> chunk mappings
    mattzcarey/zagi/
      main.manifest
      feature-branch.manifest
  objects/                       # git objects (commits, trees)
    ab/cdef1234
  refs/
    mattzcarey/zagi/heads/main   # branch pointers
```

Content-addressed, CDN-cached, immutable packs. The server is thin.

### Local store

```
~/.zagi/store/
  packs/              # downloaded pack files
  cache/              # extracted files, hardlinked into projects
```

Multiple projects sharing express 4.21.0 share the same files
on disk via hardlinks. Disk usage is proportional to unique content,
not number of projects.

### One object model

From jj: working copy is a change, stable change IDs, first-class
conflicts (rebases always succeed, conflicts are data), operation log
(every mutation recorded, everything undoable).

From Nix: content-addressed storage, reproducible resolution.

From HF/Xet: content-defined chunking, pack-based storage, cross-repo
deduplication, lazy fetching.

Combined: **a change = source + deps + env.** One history, one graph,
one diff, one revert. No lock files. No install step.

## Secrets

Encrypted in the repo, isolated from agents:

```
.zagi/secrets.enc     # age-encrypted, keyed to your identity
```

- Decrypted into env vars when you run the app (`zagi run`)
- Agents cannot access them (process namespace isolation)
- Never in history, never in plaintext on disk

## Why Not X

**Why not npm/pip/cargo + lock files?**
Lock files are a workaround for external dependencies. If deps are
tracked in the VCS, lock files are unnecessary. And install scripts
are a supply chain attack surface.

**Why not vendoring (Go-style)?**
Go vendor copies deps into the repo as regular files. This bloats git
history (git stores full copies, no chunk-level dedup) and makes
updates painful. zagi's content-addressed chunking solves both: dedup
across versions and across projects.

**Why not Nix directly?**
Nix the technology is right. Nix the product failed. zagi uses Nix
on the server and hides it completely.

**Why not Docker?**
Docker is for deployment. Imperative, non-reproducible, isolated VM.

## Build In The Open

Everything is open source. The moat is the global content-addressed
store (every package, every tool, every version, chunked and deduped)
and the network effect.

## What To Build

```
$ zagi clone mattzcarey/zagi
$ cd zagi
$ <it runs>
```

1. **Content-addressed store.** Chunking, dedup, pack storage.
   This is the foundation everything else sits on.

2. **`zagi add`.** Resolve a package or tool, chunk it, store it,
   track it as a change. This replaces package.json, lock files,
   and install commands.

3. **`zagi clone`.** Fetch the tracked state from the server,
   download chunks (deduped against local store), assemble files,
   activate env. One command, everything works.

4. **Server-side builds.** Nix builds tools and runtimes, chunks
   the result, stores in object storage.

5. **Mirror.** `zagi mirror github.com/foo/bar` reads existing
   lockfiles, runs `zagi add` for everything, converts a GitHub
   repo into a fully tracked zagi project. Viral loop.
