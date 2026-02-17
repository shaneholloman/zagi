# Next-Gen VCS: Design Spec

> git clone = ssh into a running app

## The Problem

Git solves source tracking. GitHub solves collaboration around source. Neither solves the actual problem for agents (or increasingly, humans): **I cloned the repo, now what?**

The gap between `git clone` and `the thing runs` is enormous. Every repo has different languages, package managers, system deps, database requirements, env vars, secrets. An agent can read code instantly but can't run it without a working environment. Sparkles, Codespaces, Gitpod -- they all attack this gap. But they're bolted on top of GitHub. The platform itself doesn't understand environments.

Mitchell Hashimoto's insight: **GitHub is the issue, not git.** Git and jj can be stressed further -- using worktrees, refs, notes, content-addressed storage, all the primitives that already exist. The hosting/collaboration layer is what's broken.

## Core Thesis

Build a platform where:

1. **Every repo is runnable from checkout.** Not "follow the README" -- actually runnable. The environment is part of the repo, resolved and cached on the server.
2. **Opening a repo starts a session.** You don't clone and stare at files. You get a running environment with an agent ready to help. `git clone` = `ssh into a running app`.
3. **Code review is agent-native.** Not "here's a diff, leave a comment." Agents review continuously, in small bites, as code is written.
4. **Migration is trivial.** Mirror any GitHub repo. Everything works immediately. No lock-in on the VCS layer -- git underneath, jj optional.

## Architecture

```
+--------------------------------------------------+
|                   Platform                        |
|                                                   |
|  +---------------------------------------------+ |
|  |              Environment Layer               | |
|  |  Nix-based, content-addressed, cached        | |
|  |  Every repo has a resolved env on the server | |
|  +---------------------------------------------+ |
|  |              Session Layer                   | |
|  |  Ephemeral containers, agent-first UX        | |
|  |  "Open repo" = running env + agent           | |
|  +---------------------------------------------+ |
|  |              Review Layer                    | |
|  |  Continuous, bitesized, agent-assisted       | |
|  |  Not PR-shaped -- change-shaped              | |
|  +---------------------------------------------+ |
|  |              VCS Layer                       | |
|  |  git/jj underneath, use all features         | |
|  |  Worktrees, refs, notes, content-addressing  | |
|  +---------------------------------------------+ |
+--------------------------------------------------+
```

### Layer 1: VCS (git/jj)

Don't replace git. Stress it further.

**Use jj semantics on top of git storage:**
- Working copy is always a commit (no staging area, simpler for agents)
- First-class conflicts (rebases never fail, conflicts are data)
- Stable change IDs (track a unit of work across rewrites)
- Operation log (every mutation is recorded, everything is undoable)

**Use git's underused primitives:**
- `refs/envs/*` -- environment snapshots stored as git objects
- `refs/notes/*` -- agent metadata, prompts, session logs (zagi already does this)
- Worktrees for parallel agent work (zagi forks)
- Content-addressed blob storage for dependency caching

**Why not replace git:** Migration cost is the killer. If you need people to learn a new VCS, you've already lost. jj-on-git is the right wedge -- same storage, better UX, zero migration cost.

### Layer 2: Environment

Every repo gets a resolved, cached, runnable environment. This is the hard part and the moat.

**The env spec lives in the repo:**
```
.zagi/
  env.nix          # declarative environment (nix flake)
  env.lock         # pinned, resolved, reproducible
  secrets.enc      # encrypted secrets manifest
  agents.toml      # agent permissions and capabilities
```

**How environments work:**

1. **Declare.** `env.nix` describes what the project needs: language runtimes, system packages, services (postgres, redis), tools. Nix because it's the only system that actually delivers reproducibility.

2. **Resolve.** `env.lock` pins every transitive dependency to a content hash. This is generated, not hand-written. Think `flake.lock` but also covering services and infra.

3. **Cache.** The platform pre-builds and caches environment closures. When you "clone" a repo, the environment is already built. Nothing to install. Nix's content-addressed store means deduplication is automatic -- most repos share 90% of their env (glibc, coreutils, common runtimes).

4. **Materialize.** Checkout assembles an overlay: cached env layers (read-only) + source tree (read-write). This is sub-second. No `npm install`, no `pip install`, no `apt-get`. It's already there.

**For repos without env specs (i.e., all existing repos):**

This is the migration story. The platform **infers** the environment:
- Detect language from file extensions, lockfiles, config files
- Parse `package.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `Dockerfile`, `docker-compose.yml`
- Generate a candidate `env.nix` automatically
- Run it, see if tests pass, iterate

An agent does this. That's the bootstrap: "mirror this GitHub repo" triggers an agent that figures out how to make it run, commits the env spec, and now it's a runnable repo.

### Layer 3: Sessions

Opening a repo doesn't show you files. It drops you into a running environment.

**What a session looks like:**

```
$ zagi open mattzcarey/zagi

Resolving environment... cached (247ms)
Starting session...

zagi v0.3.0 | zig 0.15 | bun 1.2
Tests: 47 passing | Build: ok
Agent: ready

>
```

You're in. The project is built. Tests have run. An agent is available. You can start talking, start coding, or both.

**Session primitives:**
- **Ephemeral container** per session, built from the env spec
- **Agent attached** by default (Claude Code, configurable)
- **State is a commit** -- your working state is always a jj-style change, auto-snapshotted
- **Sessions are forkable** -- branch a session to try something different
- **Sessions are shareable** -- send someone a link, they get the exact same state

**Agent capabilities in sessions:**
- Full read/write to source tree
- Can run builds, tests, linters
- Can create/amend changes
- **Cannot** read secrets (separate mount, ACL-controlled)
- **Cannot** push to protected branches without human approval
- All actions logged in operation log

**Secret isolation:**

Secrets are the hard problem. They need to exist (the app needs them to run) but agents shouldn't exfiltrate them.

```
.zagi/secrets.enc
  DATABASE_URL=enc:xxx
  API_KEY=enc:xxx
  STRIPE_SECRET=enc:xxx
```

- Encrypted at rest, decrypted only inside the session container
- Mounted as env vars, not files (harder to accidentally `cat`)
- Agent process gets a filtered env: secrets are resolved for the app runtime but not exposed to the agent's stdin/stdout
- Audit log for every secret access
- Scoped: agents can be granted access to specific secrets (e.g., test API keys but not prod)

### Layer 4: Review

Code review is broken. PRs are too big, reviews come too late, and the feedback loop is days not minutes.

**Change-shaped, not PR-shaped:**

Adopt jj's model. A "change" is a small, logical unit of work. Changes stack naturally. Review happens per-change, not per-PR.

```
$ zagi log
  @  kpqx  (working) matt: wip auth flow
  o  vrnt  matt: add JWT verification middleware
  o  zspm  matt: add user model and migrations
  o  main  (trunk)
```

Each change can be reviewed independently. `zspm` (user model) doesn't need to wait for `kpqx` (auth flow) to be reviewed.

**Continuous review:**

Agents review as you work, not after you push:
- Type-checking, linting, test results -- immediate, in the session
- Semantic review: "this function doesn't handle the error case from line 34" -- surfaced as you write
- Security scanning: "this SQL query is injectable" -- blocked before commit

**Bitesized review for humans:**

When human review is needed:
- Changes are presented one at a time, smallest first
- Each change has context: the prompt that created it, the test results, the agent's confidence level
- Review actions: approve, request changes, "looks fine, ship it"
- No "LGTM" culture -- the agent already validated correctness. Human review is for intent and architecture.

**Review fast:**

The platform pre-computes everything a reviewer needs:
- Diff with syntax highlighting and semantic annotations
- Test results for this specific change (not the whole branch)
- Impact analysis: what other code is affected by this change
- Agent summary: "This change adds JWT middleware. It imports `jsonwebtoken`, validates tokens in the `Authorization` header, and returns 401 on failure."

## Viral Mechanics

The product needs a consumer-grade growth loop. Technical superiority alone doesn't win.

### Mirrors

The lowest-friction entry point: mirror your GitHub repos.

```
$ zagi mirror github.com/mattzcarey/zagi

Mirroring mattzcarey/zagi...
Detecting environment... node 20, zig 0.15, bun 1.2
Generating env spec... done
Running tests... 47/47 passing
Mirror ready: zagi.sh/mattzcarey/zagi
```

Your repo now has a runnable environment on the platform. Anyone can open it and immediately have a working session. GitHub stays the source of truth if you want -- the mirror syncs both ways.

**Why mirrors are viral:**
- Zero commitment to try ("just mirror it, nothing changes")
- Immediately useful ("wait, anyone can run my project now?")
- Shareable ("here's a link, click it, you're in a running env")
- Progressive adoption (start with mirror, maybe start pushing here instead)

### "Run this repo" button

A badge for READMEs:

```markdown
[![Run on zagi](https://zagi.sh/badge.svg)](https://zagi.sh/run/mattzcarey/zagi)
```

Click it, get a running environment. Like "Open in Codespaces" but it actually works for any repo because the platform figured out the environment.

### Shareable sessions

Every session has a URL. Share it and someone gets a fork of your exact state -- same code, same environment, same point in time. Like sharing a Google Doc, but for a running codebase.

## What This Is Not

- **Not a new VCS.** Git underneath, jj semantics on top. No new storage format.
- **Not just another cloud IDE.** The IDE is secondary. The primary interface is an agent. The environment is the product.
- **Not Docker.** Docker is imperative (Dockerfile), mutable (layers change), and doesn't version-control environments. This is declarative (Nix), immutable (content-addressed), and every env change is a tracked commit.
- **Not Nix.** Nix is the implementation detail, not the product. Users never write Nix. The platform infers and generates it.

## Technical Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| VCS storage | git | Migration cost, ecosystem, tooling |
| VCS UX | jj semantics | Working-copy-as-commit, first-class conflicts, op log |
| Environment | Nix | Only system that delivers actual reproducibility |
| Containers | OCI-compatible | Layer sharing, content-addressing, existing tooling |
| Secret storage | age encryption | Simple, auditable, no key server dependency |
| Agent interface | LSP-like protocol | Structured, language-agnostic, extensible |
| Review model | Per-change, continuous | Small units, fast feedback, agent-assisted |

## Open Questions

1. **Cost model.** Running ephemeral containers isn't free. Who pays? Per-session? Per-minute? Free tier with limits?
2. **Offline story.** If the env is on the server, what happens without internet? Can you cache env closures locally (Nix already supports this)?
3. **Large repos.** Monorepos with 10GB+ histories. Partial clone? Sparse checkout? Virtual filesystem?
4. **Multi-service.** Apps that need postgres + redis + kafka. How far does the env spec go? Full docker-compose equivalent?
5. **Trust model.** If an agent generates the env spec for a mirrored repo, how do you trust it didn't add malicious packages?
6. **Private repos.** Mirroring private repos requires auth delegation. How does this work without storing GitHub tokens?

## Priorities

What to build first, in order:

1. **Mirror + auto-env detection.** Mirror a public GitHub repo, infer its environment, make it runnable. This is the proof of concept and the viral hook.
2. **Sessions.** Click a link, get a running environment with an agent. This is the "wow" moment.
3. **jj integration.** Working-copy-as-commit, operation log, change IDs. Better local experience for agents and humans.
4. **Continuous review.** Agent reviews as you code. Small changes, fast feedback.
5. **Secret isolation.** Scoped secrets, audit logs, agent sandboxing.
6. **Shareable sessions.** Fork someone's exact state from a URL.

## Relationship to zagi

zagi is the CLI layer. It already does agent-friendly git output, guardrails, prompt tracking, worktrees (forks), and task management. The next-gen platform is the hosting layer that makes zagi's vision work at scale:

- `zagi` = better git CLI for agents (local)
- `zagi platform` = runnable repos, sessions, review (remote)
- Together = `git clone` feels like `ssh into a running app`
