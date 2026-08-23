---
created: 2026-08-23T19:19:37Z
last_updated: 2026-08-23T19:19:37Z
version: 1.0
author: Claude Code PM System
---

# Project Vision

⚠️ **This file is largely inferred.** No roadmap, milestones or vision
document exists in the repository. The direction below is read off the
architecture and `AGENTS.md`; treat it as a working hypothesis and correct it
rather than building on it.

## Direction the design implies

- **Durable context over longer conversations.** The consistent bet is that
  state belongs in files and issues, not in a context window. Every subsystem
  — context files, progress streams, GitHub as source of truth — restates it.
- **Parallelism as the payoff.** Worktrees, file-granularity stream
  assignment and the `parallel-worker` agent all exist so one epic can be
  worked by several agents at once.
- **Deliberate portability.** Markdown and POSIX shell with no build step
  means it drops into any project regardless of language.

## Open strategic questions

1. **The `ccpm/` vs `.claude/` migration is unfinished** (229 references
   against 28). Completing it is a precondition for the install story making
   sense.
2. **The prompt-driven surface is unverifiable today.** 32 of 46 commands,
   including the entire Workflow, have no runtime coverage. Whether that is
   testable at all is the biggest open question about the project's
   reliability.
3. **Fork relationship with `automazeio/ccpm`.** ⚠️ Unclear whether this fork
   intends to track upstream indefinitely or diverge; PR #3 suggests tracking.
