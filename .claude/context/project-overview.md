---
created: 2026-08-23T19:19:13Z
last_updated: 2026-08-23T19:19:13Z
version: 1.0
author: Claude Code PM System
---

# Project Overview

## Command surface

46 commands. 14 script-backed, 32 prompt-driven.

**The Workflow** — the pipeline the project exists for:

```
/pm:prd-new → /pm:prd-parse → /pm:epic-decompose → /pm:epic-sync
            → /pm:epic-start → /pm:issue-start → /pm:issue-sync
            → /pm:issue-close → /pm:epic-merge → /pm:epic-close
```

**All eleven are prompt-driven**, so the pipeline has no runtime coverage —
only `bash -n` on their embedded blocks. Two of them (`epic-merge`,
`epic-sync`) currently ship broken bash.

**Reporting** (script-backed, exercised by the harness): `status`, `next`,
`blocked`, `standup`, `in-progress`, `search`, `validate`, `help`,
`prd-list`, `prd-status`, `epic-list`, `epic-show`, `epic-status`, `init`.

**Context**: `/context:create`, `/context:prime`, `/context:update`.

## Coverage

| | count | covered by |
|---|---|---|
| script-backed | 14 | `smoke` runs them, asserts output and exit codes |
| prompt-driven | 32 | nothing at runtime |

## Integration points

GitHub Issues are the source of truth once synced; parent/child linkage uses
`gh-sub-issue` with a task-list fallback. Parallel execution has two
strategies — git worktrees (`../epic-{name}` siblings on branch
`epic/{name}`, the documented default) and plain branches. `LOCAL_MODE.md`
documents a GitHub-free workflow.
