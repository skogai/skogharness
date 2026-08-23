---
created: 2026-08-23T19:18:21Z
last_updated: 2026-08-23T19:18:21Z
version: 1.0
author: Claude Code PM System
---

# Project Structure

```
ccpm/commands/{pm,context,testing}/   46 slash commands
ccpm/agents/                          4 subagent definitions
ccpm/rules/                           11 shared behavioral specs
ccpm/scripts/pm/                      14 bash scripts behind the read-only commands
ccpm/scripts/                         check-path-standards.sh, fix-path-standards.sh, test-and-log.sh
ccpm/hooks/                           bash-worktree-fix.sh
ccpm/{prds,epics,context}/            runtime workspace placeholders
install/                              curl|bash installer (clones repo, strips .git)
zh-docs/, doc/                        Chinese translations (doc/ duplicates zh-docs/)
.claude/skills/run-ccpm/              the executable harness (this repo's own tooling)
.claude/context/                      this directory
```

## The `ccpm/` vs `.claude/` split

Commit `e0fc1a8` renamed the asset directory from `.claude/` to `ccpm/`, but
only command frontmatter and `!bash` lines were updated. Counted directly:
**229 `.claude/` references against 28 `ccpm/` ones** inside `ccpm/`.

Decide by role, not by spelling:

- **Shipped assets** (commands, rules, agents, scripts, hooks) live under
  `ccpm/` in this repo. A prose reference to `.claude/commands/...` is stale.
- **Runtime data** (`prds/`, `epics/`, `context/`) is created under `.claude/`
  in the *user's* project. Those references are correct — do not "fix" them.

## Data model

```
.claude/prds/{feature}.md
.claude/epics/{feature}/epic.md
.claude/epics/{feature}/001.md              renamed to {issue-id}.md after sync
.claude/epics/{feature}/{issue}-analysis.md
.claude/epics/{feature}/updates/{issue}/stream-{A,B,C}.md
```

The `001.md → 1234.md` rename on sync is why several commands search for both
naming schemes.
