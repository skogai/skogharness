---
name: run-ccpm
description: Build, run, and drive CCPM — lint the plugin marketplace, seed a throwaway project with fixture PRD/epic/task data, and run every script-backed /pm:* command against it. Use when asked to run CCPM, test a command or script change, verify the /pm:* commands still work, lint the command markdown, validate the plugin manifests, or reproduce a PM command's output.
---

CCPM ships no application — it is a Codex **plugin marketplace**: four
plugins of slash commands, subagent definitions, skills, and bash scripts that
get installed into *someone else's* project. So "running it" means linting the
plugins, seeding a throwaway project with fixture PRD/epic/task data, and
executing the commands against it. Do that with
**`.Codex/skills/run-ccpm/driver.sh`**.

All paths below are relative to the repo root.

```bash
bash .Codex/skills/run-ccpm/driver.sh all
```

That is the whole loop: static-lint the plugins, build a sandbox at
`/tmp/ccpm-sandbox`, run all 14 script-backed commands, assert their output.
It prints `passed: 157  failed: 0` and exits 0 on a clean checkout.

## Prerequisites

Everything the driver needs is already present on a stock Ubuntu container
(`bash`, `git`, `find`, `sed`, `rg`, `python3`). Only `gh` is missing, and only
`init.sh` and the GitHub-syncing commands need it:

```bash
sudo apt-get update && sudo apt-get install -y gh   # installs gh 2.45.0
```

`gh` is optional: the 13 reporting commands never touch the network. Only
`init.sh` needs it, and `smoke` skips that one check when `gh` is absent.

## Run (agent path)

```bash
bash .Codex/skills/run-ccpm/driver.sh lint      # static checks on plugins/, no sandbox
bash .Codex/skills/run-ccpm/driver.sh sandbox   # build /tmp/ccpm-sandbox + fixtures
bash .Codex/skills/run-ccpm/driver.sh smoke     # run the commands, assert output
bash .Codex/skills/run-ccpm/driver.sh all       # all three
```

Override the sandbox location with `CCPM_SANDBOX=/path bash ... driver.sh all`.

**`lint`** (135 assertions) is the one that catches the breakage this repo
actually ships. It validates `marketplace.json` and every `plugin.json` /
`hooks.json` as JSON (and checks each declared plugin `name` matches its
directory, and each marketplace `source` exists), runs `bash -n` over every
shipped `.sh`, checks every shebang, resolves every `!bash` and
`allowed-tools: Bash(bash …)` target through `${CLAUDE_PLUGIN_ROOT}`, validates
command frontmatter, checks every `SKILL.md` has a `name` matching its
directory plus a `description` (without one a skill can never auto-activate),
extracts and syntax-checks all 110 fenced ```bash blocks inside
command/skill/agent markdown, and runs the substantive path-standards scans.
**Editing a command `.md` and not running `lint` is how `3c8e0e7` and
`1cb9483` happened.**

**`sandbox`** builds a user project the way the plugin model expects — runtime
data only, no copied assets (see *No install step* below) — and seeds: 3 PRDs
(one per status), 3 epics (one per status), 5 tasks (3 open / 2 closed, one
with a `depends_on` so `blocked`/`next` diverge), and one
`updates/002/progress.md` at 35% so `in-progress` and `standup` have something
to report.

**`smoke`** (22 assertions) runs each of the 13 reporting commands and greps
for exact expected strings — counts, percentages, task names — asserting the
exit code too. It also checks the four argument-less error paths exit 1,
runs `init.sh` (the 14th script) separately since it needs `gh` and mutates
the sandbox, confirms every script-backed command resolves against its own
plugin root, and verifies `validate.sh` actually flags an injected broken
dependency reference.

The assertions are not vacuous. Flipping one fixture task from `closed` to
`open` trips 5 of them across `/pm:status`, `/pm:epic-show`,
`/pm:epic-status`, `/pm:next` and `/pm:standup`:

```
  FAIL /pm:status (exit 0) missing:
         want: Open: 3
         want: Closed: 2
```

### Running one command by hand

The sandbox persists. To iterate on a single script, export the variable
Codex would set for the installed plugin and run the repo copy directly:

```bash
cd /tmp/ccpm-sandbox && CLAUDE_PLUGIN_ROOT=$OLDPWD/plugins/pm-core \
  bash "$OLDPWD/plugins/pm-core/scripts/pm/epic-status.sh" user-auth
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

Unlike the old bundle-copy install, `smoke` runs the scripts **in the repo**,
not a copy. Editing a script takes effect immediately — no re-`sandbox` needed
unless you changed the fixture data.

## Run (human path)

There isn't one. The prompt-driven commands (`prd-new`, `epic-decompose`,
`issue-start`, `epic-sync`, …) are prose that a Codex instance executes;
they can't be invoked from a shell. `lint` is the only automated check that
covers them, which is why its bash-block extraction matters.

## Gotchas

**No install step — that whole class of bug is gone.** The retired model
copied `ccpm/` into the project and needed symlinks to satisfy two
incompatible layouts at once (scripts reachable from the project root,
commands visible under `.Codex/commands/`). Plugins resolve their own paths
via `${CLAUDE_PLUGIN_ROOT}`, so the user's project holds runtime data only:

```bash
mkdir -p .Codex/prds .Codex/epics    # exactly what init.sh creates
```

If you find a command hardcoding `ccpm/scripts/…` or a doc describing the
copy-and-symlink install, it is stale — `lint` fails any command whose script
path doesn't go through `${CLAUDE_PLUGIN_ROOT}`.

**`check-path-standards.sh` cannot exit 0.** CLAUDE.md says it "must exit 0";
that is not achievable on a clean checkout, so don't chase it. *Check 4* runs
`find .Codex/epics/*/updates/ -name "*.md"`. In a repo with no epics the glob
doesn't expand, `find` exits non-zero, and under the script's
`set -Eeuo pipefail` that kills the whole run at Check 4 — the summary block is
unreachable. `driver.sh` sidesteps this by asserting Checks 1–3 report success
rather than trusting the exit code.

**This skill lives inside Check 1's scan scope.** `check-path-standards.sh`
greps all of `.Codex/`, and that includes `SKILL.md` and `driver.sh`. Writing
a literal absolute-path example into either file turns the lint red (it caught
exactly that while this skill was being written). Check 3's heuristic is
cruder still: it trips on any of five bare source-directory substrings (the
short one for sources, plus the ones for libraries, internal, commands and
configs) appearing anywhere alongside a `./`, so even a shell variable named
after the first of them failed it — hence `driver.sh` names that variable
`entry`. Don't spell those directory names literally in here either.
Describe such paths instead of spelling them out, and re-run `driver.sh lint`
after editing the skill itself.

**`init.sh` calls `gh auth login` unguarded.** With no TTY it fails through
harmlessly and the script still exits 0 (it degrades past a failed
`gh-sub-issue` install and an unauthenticated `gh` too). Attached to a
terminal it will sit at an interactive prompt.

**Skills replaced the old `rules/*.md` bundle, and they activate by
description, not by citation.** The eleven files under
`plugins/ccpm-rules/skills/` used to be `ccpm/rules/*.md`, cited by a
`## Required Rules` block naming a file path. Commands no longer name paths —
Codex matches a skill's `description` against the task. That makes the
old "five rules are never referenced by anything" finding moot, but it moves
the failure mode: a skill with a vague `description` silently never fires.
`lint` asserts every `SKILL.md` *has* a description; whether it is specific
enough to match real tasks is a judgment call, so read it when adding one.

**`((count++))` returns exit 1 when count is 0.** The PM scripts rely on not
running under `set -e`. If you add `set -e` to one of them it will exit
silently at the first increment. All of them end with an explicit `exit 0`.

## Known-broken command blocks

`lint` allowlists two pre-existing bugs so a clean checkout is green and any
*new* breakage is loud. Both are real and worth fixing:

- **`plugins/pm-core/commands/pm/epic-merge.md` block 3** — `git merge … -m
  "Merge epic: $ARGUMENTS` opens a double quote that isn't closed until `fi"`
  24 lines later. Everything between is swallowed into the commit message
  instead of executing, so the feature-list loop never runs.
- **`plugins/pm-core/commands/pm/epic-sync.md` block 12** — the heredoc opened
  with `<< 'EOF'` is terminated by an indented `  EOF`, which doesn't close it.
  (`<<-` wouldn't help either; it strips tabs, not spaces.)

**`prd-list.sh` silently drops PRDs whose status is `complete`.** `CLAUDE.md`
documents the PRD vocabulary as `backlog|in-progress|complete`, but
`prd-list.sh` buckets on `implemented|completed|done`. A PRD marked with the
documented `complete` matches no bucket, so it is counted in the total and
listed nowhere — `Total PRDs: 3` above `1 + 1 + 0`. `prd-status.sh` disagrees
differently, falling through to `*)` and counting it as backlog. The fixture
uses the documented vocabulary, so `smoke` asserts the current buggy output;
fixing the script means updating that assertion.

Also allowlisted: **`plugins/pm-core/scripts/pm/prd-list.sh` starts with
`# !/bin/bash`** — a commented-out shebang. Harmless while it's invoked as
`bash prd-list.sh` (which is how the command frontmatter does it), broken if
executed directly.

Fixing any of these means removing its entry from `KNOWN_BAD_BLOCKS` /
`KNOWN_BAD_SHEBANGS` at the top of `driver.sh`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `smoke` says `no sandbox; run: driver.sh sandbox` | `/tmp/ccpm-sandbox` was reaped. Re-run `driver.sh sandbox`. |
| `lint` reports a new bash-block failure | Real regression in a fenced ```bash block. `bash -n` the block; usually an unbalanced quote or heredoc. |
| `lint` says a command "does not use `${CLAUDE_PLUGIN_ROOT}`" | A script path was written relative to the repo instead of the plugin root. It will 404 once installed. |
| `lint` says `plugin.json declares name '…'` | The manifest `name` and the directory under `plugins/` drifted apart. |
| `gh: command not found` from `init.sh` | `apt-get install -y gh` works here (2.45.0). Not needed for the driver. |
| `could not check for binary extension: HTTP 403` | `gh extension install yahsan2/gh-sub-issue` reaching an unauthorized repo. `init.sh` continues past it; the task-list fallback covers it. |
| `check-path-standards.sh` exits 1 | Expected — see the gotcha above. Read its Check 1–3 lines instead. |
| A GitHub-writing command refuses to run | By design: the `github-operations` skill bails when `origin` is `automazeio/ccpm`. The sandbox sets `origin` to `acme/demo-app` to avoid this. |
