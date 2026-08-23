---
name: run-ccpm
description: Build, run, and drive CCPM — install the asset bundle into a throwaway project, seed fixture PRD/epic/task data, and run every script-backed /pm:* command against it. Use when asked to run CCPM, test a command or script change, verify the /pm:* commands still work, lint the command markdown, or reproduce a PM command's output.
---

CCPM ships no application — it is a bundle of Claude Code slash commands,
subagent definitions, rules, and bash scripts that get installed into
*someone else's* project. So "running it" means installing the bundle into a
throwaway project, seeding fixture PRD/epic/task data, and executing the
commands against it. Do that with **`.claude/skills/run-ccpm/driver.sh`**.

All paths below are relative to the repo root.

```bash
bash .claude/skills/run-ccpm/driver.sh all
```

That is the whole loop: static-lint the bundle, build a sandbox at
`/tmp/ccpm-sandbox`, run all 14 script-backed commands, assert their output.
It prints `passed: N  failed: 0` and exits 0 on a clean checkout.

## Prerequisites

Everything the driver needs is already present on a stock Ubuntu container
(`bash`, `git`, `find`, `sed`, `rg`). Only `gh` is missing, and only
`init.sh` and the GitHub-syncing commands need it:

```bash
sudo apt-get update && sudo apt-get install -y gh   # installs gh 2.45.0
```

You do **not** need `gh` for the driver — none of the 14 script-backed
reporting commands touch the network.

## Run (agent path)

```bash
bash .claude/skills/run-ccpm/driver.sh lint      # static checks on ccpm/, no sandbox
bash .claude/skills/run-ccpm/driver.sh sandbox   # build /tmp/ccpm-sandbox + fixtures
bash .claude/skills/run-ccpm/driver.sh smoke     # run the commands, assert output
bash .claude/skills/run-ccpm/driver.sh all       # all three
```

Override the sandbox location with `CCPM_SANDBOX=/path bash ... driver.sh all`.

**`lint`** (114 assertions) is the one that catches the breakage this repo
actually ships. It runs `bash -n` over every shipped `.sh`, checks every
shebang, resolves every `!bash` and `allowed-tools: Bash(bash …)` target,
validates command frontmatter, resolves `rules/*.md` references, extracts
and syntax-checks all 110 fenced ```bash blocks inside command/rule/agent
markdown, and runs the substantive path-standards scans. **Editing a command
`.md` and not running `lint` is how `3c8e0e7` and `1cb9483` happened.**

**`sandbox`** builds a correct install (see *The install is a hybrid* below)
and seeds: 3 PRDs (one per status), 3 epics (one per status), 5 tasks
(3 open / 2 closed, one with a `depends_on` so `blocked`/`next` diverge),
and one `updates/002/progress.md` at 35% so `in-progress` and `standup`
have something to report.

**`smoke`** (19 assertions) runs each command and greps for exact expected
strings — counts, percentages, task names. It also asserts the four
argument-less error paths exit 1, that all 46 commands are discoverable with
their scripts resolving, and that `validate.sh` actually flags an injected
broken dependency reference.

The assertions are not vacuous. Flipping one fixture task from `closed` to
`open` trips 5 of them across `/pm:status`, `/pm:epic-show`,
`/pm:epic-status`, `/pm:next` and `/pm:standup`:

```
  FAIL /pm:status (exit 0) missing:
         want: Open: 3
         want: Closed: 2
```

### Running one command by hand

The sandbox persists. To iterate on a single script:

```bash
cd /tmp/ccpm-sandbox && bash ccpm/scripts/pm/epic-status.sh user-auth
```

```
📚 Epic Status: user-auth
================================

Progress: [██████░░░░░░░░░░░░░░] 33%

📊 Breakdown:
  Total tasks: 3
  ✅ Completed: 1
  🔄 Available: 1
  ⏸️ Blocked: 1

🔗 GitHub: https://github.com/acme/demo-app/issues/10
```

After editing a script in `ccpm/`, re-run `driver.sh sandbox` to re-copy it
into the sandbox — `smoke` runs the sandbox's copy, not the repo's.

## Run (human path)

There isn't one. The prompt-driven commands (`prd-new`, `epic-decompose`,
`issue-start`, `epic-sync`, …) are prose that a Claude instance executes;
they can't be invoked from a shell. `lint` is the only automated check that
covers them, which is why its bash-block extraction matters.

## Gotchas

**The install is a hybrid, and neither documented layout works alone.**
`install/ccpm.sh` clones the repo into the project, yielding `ccpm/` at the
project root. The README instead talks about a `.claude` directory. Both are
half right, and I verified each fails on its own:

| Layout | Slash commands discovered? | `!bash ccpm/scripts/…` resolves? |
|---|---|---|
| `ccpm/` at project root (what the installer does) | ❌ Claude Code only scans `.claude/commands/` | ✅ |
| bundle copied into `.claude/` (what the README implies) | ✅ | ❌ every command's `!bash` line 404s |

A working install needs both — scripts reachable at `ccpm/scripts/…` from
the project root, commands visible under `.claude/commands/`. `driver.sh
sandbox` does it with symlinks:

```bash
cp -r ccpm /path/to/project/
cd /path/to/project && mkdir -p .claude
ln -s ../ccpm/commands .claude/commands
ln -s ../ccpm/agents   .claude/agents
```

Note `find` will not descend into those symlinks without `-L`.

**`check-path-standards.sh` cannot exit 0 — in any layout.** CLAUDE.md says
it "must exit 0"; that is not achievable on a clean checkout, so don't chase
it. Two independent reasons:

- *Check 4* runs `find .claude/epics/*/updates/ -name "*.md"`. In a repo with
  no epics the glob doesn't expand, `find` exits non-zero, and under the
  script's `set -Eeuo pipefail` that kills the whole run at Check 4. The
  summary block is unreachable.
- *Check 5* requires `.claude/rules/path-standards.md`, but the repo ships
  that file at `ccpm/rules/path-standards.md`. Stage a copy at the `.claude`
  path and *Check 1* then flags it — because `-g '!rules/**'` is anchored to
  the **cwd**, not to the `.claude/` search path, so it only ever excludes
  `./rules/**`. It would need `-g '!**/rules/**'`. (Proof: the same rg
  invocation run from inside `.claude/` excludes correctly.)

So the file's own absolute-path documentation examples (the very ones it
exists to warn against) get reported as violations. `driver.sh` sidesteps this by asserting Checks 1–3 report
success rather than trusting the exit code.

**This skill lives inside Check 1's scan scope.** `check-path-standards.sh`
greps all of `.claude/`, and that now includes `SKILL.md` and `driver.sh`.
Writing a literal absolute-path example into either file turns the lint red
(it caught exactly that while this skill was being written). Describe such
paths instead of spelling them out, and re-run `driver.sh lint` after editing
the skill itself.

**`init.sh` creates `.claude/scripts/pm/` and leaves it empty.** Its copy
step is guarded by `[ -d "scripts/pm" ]`, but in an installed project the
scripts live at `ccpm/scripts/pm`, so the branch never fires. Anything
expecting `.claude/scripts/pm/*.sh` to exist after `/pm:init` is wrong.

**`init.sh` calls `gh auth login` unguarded.** With no TTY it fails through
harmlessly and the script still exits 0 (it degrades past a failed
`gh-sub-issue` install and an unauthenticated `gh` too). Attached to a
terminal it will sit at an interactive prompt.

**Agents reference `.claude/scripts/test-and-log.sh`, which ships at
`ccpm/scripts/test-and-log.sh`.** `ccpm/agents/test-runner.md` names the
stale path three times. The file does exist — just not where the agent looks.

**Five rules are never referenced by anything.** `path-standards.md`,
`standard-patterns.md`, `strip-frontmatter.md`, `test-execution.md`,
`use-ast-grep.md`. Only `datetime.md` is actually cited (6 times), so a
command that should follow `strip-frontmatter.md` or `github-operations.md`
has no `## Required Rules` line pointing at it. `lint` reports what resolves,
not what *should* be cited — check by hand when adding a command.

**`((count++))` returns exit 1 when count is 0.** The PM scripts rely on not
running under `set -e`. If you add `set -e` to one of them it will exit
silently at the first increment. All of them end with an explicit `exit 0`.

## Known-broken command blocks

`lint` allowlists two pre-existing bugs so a clean checkout is green and any
*new* breakage is loud. Both are real and worth fixing:

- **`ccpm/commands/pm/epic-merge.md` block 3** — `git merge … -m "Merge epic:
  $ARGUMENTS` opens a double quote that isn't closed until `fi"` 24 lines
  later. Everything between is swallowed into the commit message instead of
  executing, so the feature-list loop never runs.
- **`ccpm/commands/pm/epic-sync.md` block 12** — the heredoc opened with
  `<< 'EOF'` is terminated by an indented `  EOF`, which doesn't close it.
  (`<<-` wouldn't help either; it strips tabs, not spaces.)

Also allowlisted: **`ccpm/scripts/pm/prd-list.sh` starts with `# !/bin/bash`**
— a commented-out shebang. Harmless while it's invoked as `bash prd-list.sh`
(which is how the command frontmatter does it), broken if executed directly.

Fixing any of these means removing its entry from `KNOWN_BAD_BLOCKS` /
`KNOWN_BAD_SHEBANGS` at the top of `driver.sh`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `smoke` says `no sandbox; run: driver.sh sandbox` | `/tmp/ccpm-sandbox` was reaped. Re-run `driver.sh sandbox`. |
| Edited a script but `smoke` shows old behavior | `smoke` runs the sandbox's copy. Re-run `driver.sh sandbox`. |
| `lint` reports a new bash-block failure | Real regression in a fenced ```bash block. `bash -n` the block; usually an unbalanced quote or heredoc. |
| `gh: command not found` from `init.sh` | `apt-get install -y gh` works here (2.45.0). Not needed for the driver. |
| `could not check for binary extension: HTTP 403` | `gh extension install yahsan2/gh-sub-issue` reaching an unauthorized repo. `init.sh` continues past it; the task-list fallback covers it. |
| `check-path-standards.sh` exits 1 | Expected — see the gotcha above. Read its Check 1–3 lines instead. |
| A GitHub-writing command refuses to run | By design: `rules/github-operations.md` bails when `origin` is `automazeio/ccpm`. The sandbox sets `origin` to `acme/demo-app` to avoid this. |
