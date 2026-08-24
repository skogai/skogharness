---
name: context-prime
description: Prime a fresh agent session by loading this repo's own .Codex/context/*.md files (project-overview, project-brief, tech-context, progress, project-structure, system-patterns, product-context, project-style-guide, project-vision). Use at the start of a session, when asked to "prime context", "load context", "/context:prime", or when resuming work here without prior conversation history.
---

This repo already has a populated `.Codex/context/` (9 files, written by an
earlier `/context:create` pass — see `ccpm/commands/context/create.md` for
how they were generated). This skill just loads them, in a sensible order,
and reports what it learned. It is not the installer-facing
`ccpm/commands/context/prime.md` command — that one is prose shipped *inside*
the CCPM bundle for installation into someone else's project, written for a
context directory that might not exist yet. This skill runs directly against
this repo's own already-populated context, so it skips that command's
preflight ceremony (per-file readability/frontmatter checks, "no context
found" bailout) and keeps only the parts still worth doing: load order and
graceful degradation.

## When to use

- Start of a session working in this repo, before diving into code.
- Explicitly asked to prime, load, or refresh context.
- Resuming after a gap where prior conversation context is gone.

## What to do

### 1. Load in priority order

Read the files in three tiers. Within a tier, issue the `Read` calls
together so they load concurrently; move to the next tier once the current
one is done.

**Tier 1 — essential:**
1. `.Codex/context/project-overview.md`
2. `.Codex/context/project-brief.md`
3. `.Codex/context/tech-context.md`

**Tier 2 — current state:**
4. `.Codex/context/progress.md`
5. `.Codex/context/project-structure.md`

**Tier 3 — deep context:**
6. `.Codex/context/system-patterns.md`
7. `.Codex/context/product-context.md`
8. `.Codex/context/project-style-guide.md`
9. `.Codex/context/project-vision.md`

Each file carries YAML frontmatter (`created`, `last_updated`, `version`,
`author`) — worth a glance to gauge staleness, not worth validating line by
line.

### 2. Degrade gracefully

Files here rarely go missing or empty, but don't assume:

- A listed file that's absent or empty: skip it, note it in the summary,
  keep going.
- `.Codex/context/` missing or entirely empty: say so and stop — point at
  `ccpm/commands/context/create.md` (its instructions can be followed
  directly even though no `/context:create` slash command is registered in
  this repo) rather than telling the user to run a command that doesn't
  exist here.
- New `.md` files appear in `.Codex/context/` that aren't in the tiers
  above: read them too, in a fourth pass, and mention them in the summary.

### 3. Cheap supplementary signal

Optionally run `git status --short` and `git branch --show-current` to note
the current branch and whether the tree is clean — useful context, cheap to
get, no need to gate the summary on it.

### 4. Report a short summary

No need to reproduce the installer command's full metrics block. Cover:

- Files loaded (and any skipped/missing, or new ones found).
- One or two sentences on what the project is and its current state, drawn
  from `project-overview.md` / `project-brief.md` and `progress.md`.
- Current git branch and working-tree state, if checked.
- Anything that looked stale (e.g. `progress.md` clearly predates recent
  commits) worth a heads-up.

Keep it tight — this is meant to orient the next steps of the session, not
to be an artifact in its own right.
