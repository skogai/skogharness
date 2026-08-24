# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

CCPM (Claude Code PM) is a **Claude Code plugin marketplace**. It is not an application — there is no source code, no build step, no package manager, and no test suite. Everything here is Markdown, JSON manifests, or POSIX shell, packaged as four plugins under `plugins/`.

The "program" is the Markdown: command files in each plugin's `commands/` are prompts that Claude executes, and shared conventions live in the `ccpm-rules` plugin's `skills/`, which auto-activate by description instead of being manually included by path. Editing a command means editing prose that another Claude instance will follow literally, so precision matters more than style.

## Layout

```
.claude-plugin/marketplace.json       # marketplace manifest, lists all 4 plugins
plugins/
  pm-core/                            # PRD -> epic -> task workflow over GitHub Issues
    .claude-plugin/plugin.json
    commands/{pm/*.md,*.md}           # /pm:* commands + misc root commands (prompt, re-init, code-rabbit)
    agents/                           # code-analyzer, file-analyzer, parallel-worker
    scripts/pm/                       # bash backing the read-only reporting commands
    scripts/{check,fix}-path-standards.sh, ccpm.config
    hooks/hooks.json, hooks/scripts/bash-worktree-fix.sh
  context-tools/                      # /context:* commands (create, prime, update)
    commands/*.md
  testing-tools/                      # /testing:* commands + test-runner agent
    commands/*.md
    agents/test-runner.md
    scripts/test-and-log.sh
  ccpm-rules/                         # shared conventions, shipped as auto-activating skills
    skills/{datetime,github-operations,...}/SKILL.md
ccpm/{context,settings.local.json}    # leftover local/dev scratch, not shipped plugin content
install/                              # legacy curl|bash installer — predates the marketplace, see caveat below
zh-docs/, doc/                        # Chinese translations of README/AGENTS/COMMANDS
```

Top-level docs: `README.md` (workflow + `/pm:*` reference), `COMMANDS.md` (non-PM commands), `AGENTS.md` (agent philosophy), `LOCAL_MODE.md` (GitHub-free workflow), `CONTEXT_ACCURACY.md` (anti-hallucination safeguards added to `/context:*`). **These still describe the pre-marketplace `ccpm/` layout and need a follow-up pass** — treat their path references (`ccpm/commands/...`) as historical until updated.

## History: the `ccpm/` vs `.claude/` split (now retired)

This repo used to ship as a single `ccpm/` asset bundle that users copied into `.claude/` via `install/ccpm.sh`. That model is retired — assets now live in `plugins/<name>/` and install as real Claude Code plugins (`claude plugin marketplace add`, `claude plugin install`), which resolve their own paths via `${CLAUDE_PLUGIN_ROOT}` instead of a copy step.

The distinction that still matters:

- **Shipped assets** (commands, skills, agents, scripts, hooks) live under `plugins/<name>/` and are addressed with `${CLAUDE_PLUGIN_ROOT}` inside JSON (hook commands, MCP config) or plain relative mentions in prose.
- **Runtime data** (`prds/`, `epics/`) is created under `.claude/` in the *user's* project — `plugins/pm-core/scripts/pm/init.sh` does `mkdir -p .claude/prds .claude/epics`, and every reporting script reads from `.claude/epics`. Those references are correct; do not "fix" them to a plugin path.

When adding a new command, follow this convention: `${CLAUDE_PLUGIN_ROOT}/scripts/...` for script paths in frontmatter/`!bash`, `.claude/` for PRD/epic/task data paths in the prose.

`install/ccpm.sh` and `install/ccpm.bat` still implement the old copy-into-`.claude/` flow and have **not** been updated for the marketplace model — they're legacy/unverified until someone rewrites them around `claude plugin marketplace add`.

## Two kinds of commands

1. **Script-backed** (`status`, `next`, `blocked`, `standup`, `epic-list`, `validate`, …) — the `.md` file is four lines: frontmatter declaring the exact `Bash(...)` invocation, then `!bash ${CLAUDE_PLUGIN_ROOT}/scripts/pm/<name>.sh $ARGUMENTS`. All logic lives in the `.sh`. Use this for deterministic, read-only reporting.
2. **Prompt-driven** (`prd-new`, `prd-parse`, `epic-decompose`, `issue-start`, `epic-sync`, …) — the `.md` file is a numbered instruction sequence with preflight checks and an explicit output format. Where these used to list `## Required Rules` file paths to read first, they now just name the relevant `ccpm-rules` skill (e.g. "the `datetime` skill") — the skill auto-activates by description, no manual include needed.

Both declare `allowed-tools` in frontmatter. Keep the declaration as narrow as the command actually needs.

## Conventions that apply when editing commands (ccpm-rules skills)

Each of these is now a `plugins/ccpm-rules/skills/<name>/SKILL.md` — read the relevant one before touching a command that does the corresponding thing. They auto-activate for Claude sessions using this plugin, but when *editing the plugin itself* read the file directly.

- `standard-patterns` — the house style: fail fast, minimal preflight, trust `gh`/git, `❌ {what failed}: {exact fix}` errors, concise output, no permission-asking for non-destructive work. Deliberately biased against over-validation.
- `datetime` — never write a placeholder timestamp; shell out to `date -u +"%Y-%m-%dT%H:%M:%SZ"` and use the real value.
- `frontmatter-operations` — status vocabularies differ per file type: PRDs `backlog|in-progress|complete`, epics `backlog|in-progress|completed`, tasks `open|in-progress|closed`. Never mutate `created`; always bump `updated`.
- `github-operations` — every write to GitHub must first bail out if `origin` points at `automazeio/ccpm` (the template repo), and must pass `--repo` explicitly rather than relying on `gh`'s default.
- `strip-frontmatter` — `sed '1,/^---$/d; 1,/^---$/d'` before any file content goes to a GitHub issue or comment.
- `path-standards` — no absolute paths (`/Users/...`, `/home/...`, `C:\...`) anywhere in docs, generated content, or synced comments; relative paths only.
- `worktree-operations` / `branch-operations` — two parallel-execution strategies; worktrees are the documented default (`../epic-{name}` sibling dirs, branch `epic/{name}`).
- `agent-coordination` — parallelism is at file granularity; agents stay inside their assigned file globs, never auto-resolve conflicts, never `--force`.
- `test-execution`, `use-ast-grep` — testing and structural-search conventions for `testing-tools` and any command doing code search.

## Data model

`PRD → epic → tasks`, all Markdown with YAML frontmatter, created in the *user's* project (not this repo):

```
.claude/prds/{feature}.md
.claude/epics/{feature}/epic.md
.claude/epics/{feature}/001.md            # renamed to {issue-id}.md after GitHub sync
.claude/epics/{feature}/{issue}-analysis.md
.claude/epics/{feature}/updates/{issue}/stream-{A,B,C}.md
```

The `001.md → 1234.md` rename on sync is why several commands search for both naming schemes. GitHub Issues are the source of truth once synced; parent/child linkage uses the `gh-sub-issue` extension with a task-list fallback. The GitHub Projects API is intentionally avoided.

## Agents

Agents split across two plugins by purpose, not expertise — same model, different job:

- `plugins/pm-core/agents/`: `code-analyzer`, `file-analyzer` (bulk reading, return a summary), `parallel-worker` (coordinates multiple streams inside an epic worktree).
- `plugins/testing-tools/agents/test-runner.md`.

Target ~10–20% of processed content in the return value. Do not add "specialist" agents (`database-expert`, `api-expert`) — `AGENTS.md` lists that as an explicit anti-pattern.

`test-runner` must invoke tests through `${CLAUDE_PLUGIN_ROOT}/scripts/test-and-log.sh` (shipped in `testing-tools`), which redirects everything to `tests/logs/*.log` so verbose output never reaches the main thread. That script auto-detects the framework from the test file extension (pytest, jest/npm, Maven/Gradle, dotnet, rspec, phpunit, go, cargo, swift, flutter).

## The `pm-core` worktree hook — known caveat

`plugins/pm-core/hooks/hooks.json` wires `bash-worktree-fix.sh` to `PreToolUse` on `Bash`, which is structurally correct plugin config. But the script itself reads the command from `argv` and prints a plain string to stdout — it predates Claude Code's actual `PreToolUse` JSON stdin/stdout hook protocol. Verify against your Claude Code version before relying on it; it likely needs a small JSON-in/JSON-out adapter. See `plugins/pm-core/hooks/README.md`.

## Verifying changes

There is nothing to build and no tests. Before committing:

```bash
bash -n plugins/<plugin>/scripts/**/*.sh                    # syntax check every touched script
python3 -m json.tool plugins/<plugin>/.claude-plugin/plugin.json   # validate manifest JSON
python3 -m json.tool .claude-plugin/marketplace.json               # validate marketplace JSON
bash plugins/pm-core/scripts/check-path-standards.sh         # absolute-path / privacy scan of .claude/ runtime data, must exit 0
bash plugins/pm-core/scripts/fix-path-standards.sh           # auto-fixes violations (writes .backup files)
```

Recent history (`3c8e0e7`, `1cb9483`) is bash syntax breakage in command files, so shell fragments embedded in Markdown deserve the same scrutiny as real scripts.

Changes to `README.md`, `AGENTS.md`, or `COMMANDS.md` should be mirrored into `zh-docs/` (and `doc/`, which duplicates it) or the translations silently drift. Those top-level docs are also the biggest remaining piece of unfinished migration work — see "Layout" above.
