---
created: 2026-08-23T19:19:13Z
last_updated: 2026-08-23T19:19:13Z
version: 1.0
author: Claude Code PM System
---

# Product Context

## Users

⚠️ Inferred from `README.md` framing; no user research exists in-repo.

- **Primary:** a developer running Claude Code who wants specs tracked as
  real issues instead of held in a chat window.
- **Secondary:** teams wanting shared visibility, since GitHub Issues are
  readable by people who never touch the agent.

## Core needs it addresses

1. **Context loss between sessions** — solved by `.claude/context/` and
   progress streams rather than by longer conversations.
2. **Spec-to-work translation** — `prd-new` through `epic-decompose` turn
   prose into numbered task files with dependencies and parallel flags.
3. **Concurrency without collisions** — file-granularity parallelism, agents
   confined to assigned globs, no auto-resolution of conflicts, no `--force`.
4. **Progress visibility** — `standup`, `next`, `blocked`, `in-progress` read
   local state; `issue-sync` pushes it to GitHub.

## Constraints that shape the product

- Everything is Markdown and shell, so it installs anywhere without a runtime.
- GitHub Issues over the Projects API, deliberately.
- Commands must degrade gracefully: `init.sh` completes even with `gh`
  unauthenticated and the sub-issue extension missing.
