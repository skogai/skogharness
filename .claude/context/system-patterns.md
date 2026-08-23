---
created: 2026-08-23T19:18:48Z
last_updated: 2026-08-23T19:18:48Z
version: 1.0
author: Claude Code PM System
---

# System Patterns

## Two kinds of commands

1. **Script-backed** (14) — the `.md` is four lines: frontmatter declaring the
   exact `Bash(...)` invocation, then `!bash ccpm/scripts/pm/<name>.sh
   $ARGUMENTS`. All logic lives in the `.sh`. Used for deterministic,
   read-only reporting.
2. **Prompt-driven** (32) — a numbered instruction sequence with preflight
   checks, a `## Required Rules` section, and an explicit output format. Used
   for anything generative or stateful.

Both declare `allowed-tools`. Keep the declaration as narrow as the command
needs.

## Agents are context firewalls, not specialists

`ccpm/agents/*.md` define subagents whose purpose is **context reduction** —
same model, different job. `code-analyzer`, `file-analyzer` and `test-runner`
each do bulk reading and return a summary targeting ~10–20% of processed
content. `parallel-worker` coordinates streams inside an epic worktree.
`AGENTS.md` names "specialist" agents (`database-expert`, `api-expert`) as an
explicit anti-pattern.

## Rules by reference

Commands cite shared specs rather than restating them, which is what keeps ~46
command files consistent. Citations appear in **three spellings** —
`.claude/rules/x.md`, `ccpm/rules/x.md`, and a bare `/rules/x.md` (the most
common, 21 of 27). A reference check matching only the prefixed forms sees
almost nothing.

## Session continuity

Two channels, and they are the project's answer to agent memory:

- **Project level** — `.claude/context/` via `/context:create` →
  `/context:prime` (session start) → `/context:update` (session end).
- **Task level** — `.claude/epics/{epic}/updates/{issue}/progress.md` carrying
  `completion: N%` and `last_sync`, which `/pm:in-progress` and `/pm:standup`
  read. In-flight state lands where the tooling already looks.

`CONTEXT_ACCURACY.md` governs both: evidence-based claims only, self-check
"can I point to specific files that demonstrate this?", `⚠️` flags for
assumptions, qualifying language for anything inferred.

## Shell conventions

Scripts do **not** run under `set -e` and rely on that — `((count++))` returns
exit 1 when count is 0, so adding `set -e` makes them exit silently at the
first increment. Every reporting script ends with an explicit `exit 0`.
GitHub-writing commands must bail if `origin` points at the template repo and
must pass `--repo` explicitly. Timestamps always come from
`date -u +"%Y-%m-%dT%H:%M:%SZ"`, never a placeholder.
