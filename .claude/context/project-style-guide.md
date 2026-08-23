---
created: 2026-08-23T19:19:37Z
last_updated: 2026-08-23T19:19:37Z
version: 1.0
author: Claude Code PM System
---

# Project Style Guide

Distilled from `ccpm/rules/standard-patterns.md` and the surrounding rules.
When editing a command, read the relevant rule file first — consistency across
46 command files is the whole point.

## House style for commands

- **Fail fast, validate little.** The rules are deliberately biased against
  over-validation. Trust `gh` and `git` to report their own errors.
- **Errors read `❌ {what failed}: {exact fix}`** — name the fix, not just the
  failure.
- **Do not narrate preflight checks.** Run them and move on; never tell the
  user "I'm not going to…".
- **Do not ask permission for non-destructive work.**
- **Output is concise.** Reporting commands print a short block and exit 0.

## Hard rules

- **Timestamps:** shell out to `date -u +"%Y-%m-%dT%H:%M:%SZ"`. Never write a
  placeholder.
- **Frontmatter:** status vocabularies differ per file type — PRDs
  `backlog|in-progress|complete`, epics `backlog|in-progress|completed`, tasks
  `open|in-progress|closed`. Never mutate `created`; always bump `updated`.
- **GitHub writes:** bail if `origin` is the template repo; pass `--repo`
  explicitly rather than relying on `gh`'s default.
- **Strip frontmatter** with `sed '1,/^---$/d; 1,/^---$/d'` before any file
  content goes into an issue or comment.
- **No absolute paths** anywhere in docs, generated content or synced
  comments — relative only. This is enforced by
  `ccpm/scripts/check-path-standards.sh`, which scans all of `.claude/`,
  including this directory.
- **Context accuracy:** evidence-based claims only, `⚠️` flags on assumptions,
  qualifying language for anything inferred. See `CONTEXT_ACCURACY.md`.

## Editing checklist

```bash
bash -n ccpm/scripts/pm/<changed>.sh          # syntax-check touched scripts
bash .claude/skills/run-ccpm/driver.sh all    # 140 assertions
```

Shell fragments embedded in Markdown deserve the same scrutiny as real
scripts — recent history (`3c8e0e7`, `1cb9483`) is bash breakage inside
command files. Changes to `README.md`, `AGENTS.md` or `COMMANDS.md` should be
mirrored into `zh-docs/` (and `doc/`, which duplicates it) or the translations
silently drift.
