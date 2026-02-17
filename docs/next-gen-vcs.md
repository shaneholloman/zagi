# Next-Gen VCS: Design Spec

> version control that includes the environment

## One Problem

The gap between `git clone` and "the thing works" is the single biggest
friction in software. Humans spend hours on READMEs. Agents can't even
start. Codespaces and Gitpod attack this with cloud containers, but that's
someone else's machine -- slow, expensive, locked in.

Git tracks source. Nix tracks environments. They're separate systems with
separate concepts, separate histories, separate mental models. When you
change a dependency, that's a different workflow than changing a source
file. It shouldn't be. **The environment is part of the code.**

## One Idea

Version control where the environment is a first-class part of every
change. Not "VCS + env manager." One system.

```
$ zagi clone github.com/mattzcarey/zagi

Cloning... done
Resolving env... cached (280ms)

$ cd zagi
$ zig build test    # just works. no install step. no README.
```

The clone gives you source AND a resolved environment -- compilers,
runtimes, system libraries, all present, correct versions. It mounts to
your local filesystem. You use your own editor, your own agent, your own
terminal. Everything just works.

**How this differs from today:**
- `git clone` gives you source. You figure out the rest.
- `zagi clone` gives you a runnable project. There is no rest.

## Design

### One object model

Take the best ideas from jj and Nix. Combine them into one thing that
zagi exposes through a CLI.

**From jj:**
- Working copy is always a change (no staging area)
- Changes have stable IDs across rewrites
- First-class conflicts (rebases never fail, conflicts are data)
- Operation log (every mutation is recorded, everything is undoable)

**From Nix:**
- Content-addressed storage (identity = contents)
- Declarative environments (TOML, not Nix expressions)
- Reproducible resolution (same spec = same result, always)
- Deduplication (most projects share 90% of their env)

**Combined: a change = source + env.**

When you change a source file, that's a change. When you add a dependency,
that's also a change. Same history, same diff, same revert. The env isn't
a sidecar config file that you hope stays in sync -- it IS the versioned
state.

```
$ zagi log
  @  kpqx  (working) matt: wip auth flow
  o  vrnt  matt: add jwt middleware + jsonwebtoken@9.0
  o  zspm  matt: add user model + postgres@16
  o  main
```

`zspm` added source files AND postgres 16 to the environment. Checking
out `zspm` gives you the code at that point AND a running postgres 16.
Checking out `main` doesn't have postgres. The environment travels with
the change.

### The env spec

Lives in the repo, versioned like any other file:

```toml
# .zagi/env.toml

[project]
name = "zagi"

[tools]
zig = "0.15"
bun = "1.2"

[system]
packages = ["libgit2"]

[services]
# postgres = "16"
```

`env.lock` is generated. Every transitive dep has a content hash.
Same lock = same environment on any machine, every time.

**Users don't write this from scratch.** `zagi init` detects your
project and generates it:

- `package.json` -> node + npm/bun/pnpm
- `Cargo.toml` -> rust + cargo
- `go.mod` -> go
- `pyproject.toml` -> python + uv
- `Dockerfile` -> parse and extract
- `flake.nix` -> use directly

If inference is wrong, you fix the TOML. It's right forever after.

Nix resolves the spec under the hood. Users never see Nix. You write
`zig = "0.15"`, not a Nix expression.

### The mount

`zagi clone` mounts the resolved environment alongside your source:

```
~/zagi/                         # your working directory
  src/                          # source (read-write)
  build.zig
  ...
  .zagi/env/                    # resolved env (read-only, cached)
    bin/zig
    bin/bun
    lib/libgit2.so
```

When you `cd` in, the env activates (PATH, lib paths, etc). When you
leave, it deactivates. No global pollution. Not a container -- your
actual filesystem, your actual shell.

FUSE on Linux, macFUSE or symlink forest on macOS. Fallback:
hardlinks from the content-addressed store.

### The store

Content-addressed, file-level dedup, local:

```
~/.zagi/store/
  a3f8c9d1.../    # zig 0.15 closure
  b7e2a4f0.../    # node 20 + pnpm
```

Most environments overlap. Node 20 is Node 20 whether it's for
project A or project B. Mounting a second Node project when you
already have Node cached = instant.

### Secrets

Secrets in the repo but isolated from agents:

```
.zagi/secrets.enc     # encrypted with age, keyed to your identity
```

- Decrypted at mount time for app processes
- Not accessible to agent processes (mount namespace isolation)
- Never in git history, never in plaintext on disk

An agent can build, test, and modify source. It cannot read your
Stripe key. Kernel-level isolation, not honor system.

## The Server

The zagi server lives on object storage natively. Not a filesystem
pretending to be a server. S3/R2/GCS as the source of truth.

Git already works in objects (blobs, trees, commits). The server maps
these directly to object storage keys. Content-addressed objects in a
bucket.

```
s3://zagi-store/
  objects/
    ab/cdef1234...    # git objects (blobs, trees, commits)
  envs/
    a3/f8c9d1...      # resolved environment closures
  refs/
    heads/main        # branch pointers
```

**Why object storage:**
- Infinitely scalable, zero ops
- Content-addressed objects map 1:1 to bucket keys
- CDN-friendly (immutable objects, cache forever)
- Cheap (pennies per GB)
- Env closures and git objects share the same storage model
- No filesystem server to maintain, scale, or fail

The public cache for pre-built environments is the same bucket.
Push an env closure, anyone can pull it. First-time clone of a
popular project fetches pre-built binaries instead of building.

## Why Not X

**Why not git + Nix separately?**
Two systems, two mental models, two histories. When you revert a
commit, your env doesn't revert. When you switch branches, you
have to remember to re-run `nix develop`. The whole point is:
they should be one thing.

**Why not Nix directly?**
Nix the technology is right. Nix the product failed. The learning
curve, the documentation, the "experimental" flakes. zagi uses Nix
as a backend and hides it behind TOML.

**Why not Docker?**
Docker is for deployment. It's imperative, non-reproducible, and
gives you an isolated VM instead of a local directory. You can't
point Cursor at a running container and have it feel native.

**Why not devcontainers?**
Container. Tied to VS Code. Requires Docker. Manual setup.
Doesn't version-control the env with the code.

## Build In The Open

Everything is open source:
- `zagi` CLI (Zig + libgit2, already open)
- Environment resolution (TOML -> Nix compilation)
- Mount implementation
- Object storage protocol
- Auto-detection heuristics

The value is in the public cache (pre-built envs for popular repos)
and the network effect (more repos with env specs = more useful for
everyone).

Service opportunities: hosted cache, mirrors, team secrets.

## What To Build

One command that works end to end:

```
$ zagi clone github.com/some/repo
$ cd repo
$ <it runs>
```

In order:

1. **Auto-detection.** Given a repo, infer env.toml from lockfiles
   and config. JS/TS, Python, Rust, Go, Zig first.

2. **Env resolution.** Compile env.toml to Nix. Build. Cache in
   local content-addressed store.

3. **Mount.** Overlay source + env. Shell hook for activation.
   Start simple (symlinks + direnv), upgrade to FUSE.

4. **Object storage server.** Git objects + env closures in S3.
   Content-addressed, CDN-cached.

5. **Public cache.** Pre-built envs for popular projects. First
   clone is a download, not a build.

6. **Mirror.** `zagi mirror github.com/foo/bar` auto-detects env,
   builds, caches. Viral loop: "I made your repo runnable."
