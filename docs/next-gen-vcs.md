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
tools, services. No install step on clone. Use your existing package
manager, zagi tracks the result. One system.

```
$ curl -sf zagi.sh | sh
$ zagi clone mattzcarey/zagi
$ cd zagi
$ zig build test    # works. no install. no README.
```

## Use Your Tools, Track Everything

zagi doesn't replace your package manager. npm knows how to resolve
node packages. pip knows Python. cargo knows Rust. Let them do their
job. zagi's job is to **track the result**.

```
$ zagi add node@22             # env: zagi handles tools and services
$ npm i express                # deps: npm does what npm does
$ zagi commit -m "add express" # zagi chunks and tracks node_modules
```

That's it. npm writes to `node_modules`. zagi sees the change, chunks
it, content-addresses it, deduplicates it against the global store.
The dependency is now tracked the same way source is tracked. No lock
file needed on the consumer side -- the actual code is in the store.

`zagi add` is for **environment stuff** -- tools and services that
don't have their own package manager:

```
$ zagi add node@22        # runtime/tool
$ zagi add postgres@16    # service
$ zagi add zig@0.15       # compiler
```

For everything else, use the native package manager. It already
knows what it's doing.

```
$ npm i express           # node packages
$ pip install flask       # python packages
$ cargo add serde         # rust crates
$ zagi commit -m "add deps"
```

zagi tracks the result. The log shows everything:

```
$ zagi log
  @  kpqx  matt: wip auth routes
  o  vrnt  matt: add express (npm i)
  o  zspm  matt: add node@22, postgres@16
  o  root
```

Revert `vrnt` and express is gone. Checkout a branch that doesn't
have express and it's not there. The dependency history IS the source
history. One graph.

### Edit your dependencies

Want to patch a bug in a dependency? Just edit it. It's tracked.

```
$ vim node_modules/express/lib/router/index.js   # just edit it
$ zagi commit -m "fix express body-parser edge case"

$ zagi log
  @  mfpz  matt: fix express body-parser edge case
  o  vrnt  matt: add express (npm i)
```

When express releases a new version, you `npm update express` and
commit. Your patch is re-applied automatically (jj-style conflict
resolution). If it conflicts, the conflict is data -- you or an
agent resolve it. No patch files. No fork. Just tracked changes on
tracked code.

Agents are great at this. "Update express and re-apply our body-parser
fix" is a one-shot prompt.

### Supply chain security

Today, every `npm install` on every machine runs postinstall scripts
from strangers. Every CI run, every new developer, every `git clone`
triggers arbitrary code execution from the registry.

With zagi, `npm install` runs **once** -- on the developer's machine
who adds the dependency. The result is chunked, hashed, and tracked.
Everyone else gets the pre-built, content-addressed result. No
postinstall scripts. No registry fetch. The code you reviewed is the
code everyone runs.

If someone publishes a compromised version of a package, it has a
different hash. Your project still points to the original hash.
Nothing changes unless someone explicitly upgrades and commits.

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
$ zagi add postgres@16      # env: tool/service
$ npm i lodash              # deps: use npm
$ zagi commit -m "add lodash, postgres"
$ zagi checkout feature     # switches source AND env atomically

$ zagi log
  @  kpqx  matt: wip feature
  o  vrnt  matt: add lodash, postgres@16
  o  main
```

No `docker-compose up`. No `brew install postgresql`. No second
`npm install` on another machine. Switching branches switches
everything -- source, deps, tools, services.

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

The server has Nix. It handles two things:

**Environment builds** (`zagi add node@22`):
1. Resolves the tool/service via Nix
2. Builds or fetches pre-built binaries (Nix binary cache)
3. Chunks the result, deduplicates, stores in packs

**Dependency tracking** (`zagi commit` after `npm i`):
1. Client chunks node_modules (or venv, target, etc.)
2. Client sends new chunks to server
3. Server deduplicates against global store, stores in packs

The server never runs npm/pip/cargo. It just stores chunks.

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

**Why not just npm/pip/cargo?**
You DO use npm/pip/cargo. zagi doesn't replace them. But today,
every machine that clones the repo has to re-run `npm install`,
re-fetch from the registry, re-run postinstall scripts. zagi
tracks the result so nobody has to do that twice.

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

2. **`zagi add` (env).** Add tools (`node@22`) and services
   (`postgres@16`) to the environment. Server resolves and builds
   via Nix, chunks the result.

3. **`zagi commit` (deps).** Use npm/pip/cargo as normal. Commit
   the result. zagi chunks and tracks node_modules/venv/target
   the same way it tracks source. No lock file needed on clone.

4. **`zagi clone`.** Fetch the tracked state from the server,
   download chunks (deduped against local store), assemble files,
   activate env. One command, everything works.

5. **Server-side builds.** Nix builds tools and runtimes for
   `zagi add`. Chunks the result, stores in object storage.

6. **Mirror.** `zagi mirror github.com/foo/bar` reads existing
   lockfiles, runs the native package manager + `zagi add` for
   env, converts a GitHub repo into a fully tracked zagi project.
   Viral loop.
