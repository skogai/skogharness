# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

CCPM (Claude Code PM) is not an application — it is a **bundle of Claude Code assets** (slash commands, subagent definitions, behavioral rules, and bash helper scripts) that users install into *their* project. There is no source code, no build step, no package manager, and no test suite. Everything here is Markdown or POSIX shell.

The "program" is the Markdown: command files in `ccpm/commands/` are prompts that Claude executes, and rule files in `ccpm/rules/` are shared specs those prompts include by reference. Editing a command means editing prose that another Claude instance will follow literally, so precision matters more than style.

## Layout

```
ccpm/commands/{pm,context,testing}/  # slash commands (/pm:*, /context:*, /testing:*)
ccpm/agents/                         # subagent definitions (context firewalls)
ccpm/rules/                          # shared behavioral specs referenced by commands
ccpm/scripts/pm/                     # bash backing the read-only reporting commands
ccpm/hooks/                          # bash-worktree-fix.sh pre-tool-use hook
ccpm/{prds,epics}/                   # runtime workspace placeholders
install/                             # curl|bash installer (clones repo, strips .git)
zh-docs/, doc/                       # Chinese translations of README/AGENTS/COMMANDS
```

Top-level docs: `README.md` (workflow + `/pm:*` reference), `COMMANDS.md` (non-PM commands), `AGENTS.md` (agent philosophy), `LOCAL_MODE.md` (GitHub-free workflow), `CONTEXT_ACCURACY.md` (anti-hallucination safeguards added to `/context:*`).

## Critical: the `ccpm/` vs `.claude/` split

Commit `e0fc1a8` renamed the asset directory from `.claude/` to `ccpm/`, but **only the command frontmatter and `!bash` invocation lines were updated**. Everything else still says `.claude/`:

- **Updated to `ccpm/`** — the ~14 script-wrapper commands (`allowed-tools: Bash(bash ccpm/scripts/pm/status.sh)` and the matching `!bash ccpm/scripts/pm/status.sh`).
- **Still `.claude/`** — all script bodies, all instruction prose in command/rule/agent files, `settings.json.example`, `hooks/README.md`, and the installer docs. Roughly 229 `.claude/` references vs 28 `ccpm/` ones.

Some of this is intentional and some is stale, and the two cases look identical, so decide by role:

- **Shipped assets** (commands, rules, agents, scripts, hooks) live under `ccpm/` in this repo. A prose reference to `.claude/commands/...` or `.claude/rules/...` is stale.
- **Runtime data** (`prds/`, `epics/`, `context/`) is created under `.claude/` in the *user's* project — `scripts/pm/init.sh` does `mkdir -p .claude/prds .claude/epics` and every reporting script reads from `.claude/epics`. Those references are correct; do not "fix" them to `ccpm/`.

When adding a new command, follow the current convention: `ccpm/` for the script path in frontmatter/`!bash`, `.claude/` for PRD/epic/task data paths in the prose.

## Two kinds of commands

1. **Script-backed** (`status`, `next`, `blocked`, `standup`, `epic-list`, `validate`, …) — the `.md` file is four lines: frontmatter declaring the exact `Bash(...)` invocation, then `!bash ccpm/scripts/pm/<name>.sh $ARGUMENTS`. All logic lives in the `.sh`. Use this for deterministic, read-only reporting.
2. **Prompt-driven** (`prd-new`, `prd-parse`, `epic-decompose`, `issue-start`, `epic-sync`, …) — the `.md` file is a numbered instruction sequence with preflight checks, a `## Required Rules` section listing the `rules/*.md` files to read first, and an explicit output format. Use this for anything generative or stateful.

Both declare `allowed-tools` in frontmatter. Keep the declaration as narrow as the command actually needs.

## Rules that apply when editing commands

Read the relevant file in `ccpm/rules/` before touching a command that does the corresponding thing — the commands themselves point at them, and consistency across ~40 command files is the whole point.

- `standard-patterns.md` — the house style: fail fast, minimal preflight, trust `gh`/git, `❌ {what failed}: {exact fix}` errors, concise output, no permission-asking for non-destructive work. Deliberately biased against over-validation.
- `datetime.md` — never write a placeholder timestamp; shell out to `date -u +"%Y-%m-%dT%H:%M:%SZ"` and use the real value.
- `frontmatter-operations.md` — status vocabularies differ per file type: PRDs `backlog|in-progress|complete`, epics `backlog|in-progress|completed`, tasks `open|in-progress|closed`. Never mutate `created`; always bump `updated`.
- `github-operations.md` — every write to GitHub must first bail out if `origin` points at `automazeio/ccpm` (the template repo), and must pass `--repo` explicitly rather than relying on `gh`'s default.
- `strip-frontmatter.md` — `sed '1,/^---$/d; 1,/^---$/d'` before any file content goes to a GitHub issue or comment.
- `path-standards.md` — no absolute paths (`/Users/...`, `/home/...`, `C:\...`) anywhere in docs, generated content, or synced comments; relative paths only.
- `worktree-operations.md` / `branch-operations.md` — two parallel-execution strategies; worktrees are the documented default (`../epic-{name}` sibling dirs, branch `epic/{name}`).
- `agent-coordination.md` — parallelism is at file granularity; agents stay inside their assigned file globs, never auto-resolve conflicts, never `--force`.

## Data model

`PRD → epic → tasks`, all Markdown with YAML frontmatter:

```
.claude/prds/{feature}.md
.claude/epics/{feature}/epic.md
.claude/epics/{feature}/001.md            # renamed to {issue-id}.md after GitHub sync
.claude/epics/{feature}/{issue}-analysis.md
.claude/epics/{feature}/updates/{issue}/stream-{A,B,C}.md
```

The `001.md → 1234.md` rename on sync is why several commands search for both naming schemes. GitHub Issues are the source of truth once synced; parent/child linkage uses the `gh-sub-issue` extension with a task-list fallback. The GitHub Projects API is intentionally avoided.

## Agents

`ccpm/agents/*.md` define subagents whose purpose is **context reduction**, not expertise — same model, different job. `code-analyzer`, `file-analyzer`, and `test-runner` each do bulk reading and return a summary; `parallel-worker` coordinates multiple streams inside an epic worktree. Target ~10–20% of processed content in the return value. Do not add "specialist" agents (`database-expert`, `api-expert`) — `AGENTS.md` lists that as an explicit anti-pattern.

`test-runner` must invoke tests through `.claude/scripts/test-and-log.sh`, which redirects everything to `tests/logs/*.log` so verbose output never reaches the main thread. That script auto-detects the framework from the test file extension (pytest, jest/npm, Maven/Gradle, dotnet, rspec, phpunit, go, cargo, swift, flutter).

## Verifying changes

There is nothing to build and no tests. Before committing:

```bash
bash -n ccpm/scripts/pm/<changed>.sh        # syntax check every touched script
bash ccpm/scripts/check-path-standards.sh   # absolute-path / privacy scan, must exit 0
bash ccpm/scripts/fix-path-standards.sh     # auto-fixes violations (writes .backup files)
```

Recent history (`3c8e0e7`, `1cb9483`) is bash syntax breakage in command files, so shell fragments embedded in Markdown deserve the same scrutiny as real scripts.

Changes to `README.md`, `AGENTS.md`, or `COMMANDS.md` should be mirrored into `zh-docs/` (and `doc/`, which duplicates it) or the translations silently drift.
