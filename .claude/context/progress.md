---
created: 2026-08-23T19:18:21Z
last_updated: 2026-08-23T19:18:21Z
version: 1.0
author: Claude Code PM System
---

# Progress

## Current status

Branch `main` at `12a6250`. Merged this cycle: **#2** (the `run-ccpm` skill),
**#4** (eight review fixes to it). **#5** was closed deliberately — it carried
a bespoke `HANDOVER.md` that this context directory replaces.

**#3 "merge upstream" is open and is the one live item.** It is an incoming
merge, head `automazeio/ccpm:main`, base `skogai/ccpm:main`. Its base sha
`75f3839` predates current `main`, so it is stale. It touches `ccpm/`, which
the harness lints, so merging it can invalidate the known-bad allowlists.
**Run `bash .claude/skills/run-ccpm/driver.sh all` immediately after merging
it** and reconcile `KNOWN_BAD_BLOCKS` / `KNOWN_BAD_SHEBANGS` against what
upstream actually ships.

## Completed

- `.claude/skills/run-ccpm/` — installs the bundle into a throwaway project,
  seeds fixture PRD/epic/task data, runs the script-backed commands and
  asserts their output. 140 assertions, exit 0 clean / 1 on regression.
- This context directory — the repo's first `/context:create` run.

## Open findings (surfaced, not fixed)

Verified by execution; none had a mandate to change behavior.

1. **Neither install layout works alone.** The installer puts `ccpm/` at the
   project root, where Claude Code never sees the slash commands; copying the
   bundle into `.claude/` makes them visible but breaks every `!bash` target.
   A working install needs both.
2. **`prd-list.sh` silently drops PRDs marked `complete`.** Docs say
   `backlog|in-progress|complete`; the script buckets on
   `implemented|completed|done`. Counted in the total, listed nowhere.
   `prd-status.sh` disagrees again, counting it as backlog.
3. **`check-path-standards.sh` cannot exit 0 in any layout**, contrary to
   `CLAUDE.md`. Check 4's glob dies under `set -Eeuo pipefail` with no epics;
   Check 5 wants a file shipped elsewhere, and staging it trips Check 1,
   whose `-g '!rules/**'` is anchored to cwd rather than the search path.
4. **`init.sh` leaves `.claude/scripts/pm/` empty** — its copy step guards on
   a path that never exists in an installed project.
5. **`epic-merge.md` block 3** — an unterminated `"` swallows 24 lines into a
   commit message; the feature-list loop never runs.
6. **`epic-sync.md` block 12** — an indented `EOF` never closes its heredoc.
7. **`prd-list.sh` ships `# !/bin/bash`** — a commented-out shebang.
8. **5 of 11 rules are never referenced** — `path-standards`,
   `standard-patterns`, `strip-frontmatter`, `test-execution`, `use-ast-grep`.

Items 5–7 are allowlisted in `driver.sh` so a clean checkout stays green;
fixing one means removing its entry. Fixing item 2 means updating the `smoke`
assertion that currently pins the buggy output.

## Next steps

1. Settle the install layout — most other decisions are downstream of it.
2. Fix the two broken Workflow commands (`epic-merge`, `epic-sync`).
3. Settle the PRD status vocabulary: move the script or move the docs.
4. Decide whether the prompt-driven commands can be tested at all. That is
   the real coverage gap; the harness stops at the shell boundary today.
