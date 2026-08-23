---
created: 2026-08-23T19:19:13Z
last_updated: 2026-08-23T19:19:13Z
version: 1.0
author: Claude Code PM System
---

# Project Brief

## What it is

CCPM (Claude Code PM) is a **bundle of Claude Code assets** — slash commands,
subagent definitions, behavioral rules and shell helpers — that a user
installs into their own project. It is not an application. It turns a written
spec into tracked, parallelisable work: PRD → epic → tasks → GitHub Issues →
parallel agent execution.

## Why it exists

To stop context evaporating between agent sessions. Every mechanism here
serves that: GitHub Issues as the durable source of truth, `.claude/context/`
for project memory, progress streams for in-flight work, and agents whose job
is to read a lot and return a little.

## Scope

- **In scope:** the command bundle, the rules that keep it consistent, the
  installer, and the docs (English plus Chinese translations under `zh-docs/`
  and `doc/`).
- **Out of scope:** the GitHub Projects API, deliberately avoided in favour of
  Issues plus the `gh-sub-issue` extension.

## Success criteria

⚠️ Inferred from `README.md` and `AGENTS.md` rather than a stated goals
document — verify before relying on it.

- A spec becomes tracked issues without manual bookkeeping.
- Multiple agents work one epic concurrently without colliding (parallelism is
  at file granularity; agents stay inside assigned globs and never
  auto-resolve conflicts).
- A new session can resume work without re-deriving the project by hand.
