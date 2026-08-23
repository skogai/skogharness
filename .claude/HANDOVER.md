# Handover

Written at the end of the session that added the `run-ccpm` skill. Next up:
going over **the Workflow** (the PRD → epic → task → sync → execute pipeline).

## Where things stand

`main` is at `12a6250`. Two PRs merged into it: **#2** (the skill) and **#4**
(eight review fixes to it). Nothing of ours is in flight.

**One PR is open and it matters: #3, "merge upstream".** It is an *incoming*
merge — head `automazeio/ccpm:main`, base `skogai/ccpm:main` — which is the
legitimate direction for a fork. Two things to know before merging it:

- Its base sha is `75f3839`, which predates current `main` (`12a6250`), so
  it is stale and will need updating.
- It brings upstream changes to `ccpm/`, which is exactly what the harness
  lints. Merging it can invalidate the allowlists (for instance if upstream
  already fixed `epic-merge.md` or `epic-sync.md`). **Run
  `driver.sh all` immediately after merging #3** and reconcile
  `KNOWN_BAD_BLOCKS` / `KNOWN_BAD_SHEBANGS` with what upstream actually
  ships.

The deliverable is `.claude/skills/run-ccpm/` — a `SKILL.md` and a
`driver.sh` that installs the bundle into a throwaway project, seeds fixture
PRD/epic/task data, and runs the script-backed `/pm:*` commands against it.

```bash
bash .claude/skills/run-ccpm/driver.sh all     # 140 assertions, exit 0 clean / 1 on regression
```

`SKILL.md` is the reference — it carries the gotchas, the known-broken list,
and troubleshooting. Read it before touching anything under `ccpm/`.

## Git and GitHub facts — read before opening any PR

- **`origin` is `skogai/ccpm`.** That is the only repo we work in.
- `SkogBackup/ccpm` is a **301 redirect to the same repo** (the owner was
  renamed). Both paths serve identical refs. If a tool echoes back a
  `skogai/...` URL after you passed `SkogBackup/...`, that is the rename,
  not a different repo.
- **`skogai/ccpm` is a fork of `automazeio/ccpm`** (upstream's `main` is the
  same SHA that arrived here as PR #3, "merge upstream").
- **The trap:** pushing a branch to a fork makes GitHub offer *upstream* as
  the default base for a new PR. During this session, `automazeio/ccpm#1026`
  ended up carrying our commit `5d79d72`. It has since been closed.
- **Guard:** after opening a PR, confirm `head.repo.full_name` and
  `base.repo.full_name` are *both* `skogai/ccpm`. A fork-crossing PR shows
  two different repos there — that is the check that catches this.
- Never open a PR, issue, or comment against `automazeio/*`.
- A notification naming a PR number in the thousands is upstream, not ours:
  our numbering is single digits. Do not conclude "phantom PR" from a 404
  against our repo alone — check upstream too.

## Coverage: what is actually verified

| | count | covered by |
|---|---|---|
| script-backed commands | 14 | `smoke` runs them, asserts output + exit codes |
| prompt-driven commands | 32 | nothing at runtime — only `bash -n` on their fenced blocks |
| total | 46 | |

**Every command in the Workflow chain is prompt-driven**, so the pipeline
this project exists for has no runtime coverage at all:

```
/pm:prd-new → /pm:prd-parse → /pm:epic-decompose → /pm:epic-sync
            → /pm:epic-start → /pm:issue-start → /pm:issue-sync
            → /pm:issue-close → /pm:epic-merge → /pm:epic-close
```

All eleven are prose an agent executes. The harness verifies their
frontmatter, their `rules/*.md` references and the syntax of their embedded
bash — nothing about whether the pipeline works end to end. Two of them
(`epic-merge`, `epic-sync`) already ship with broken bash blocks.

## Open findings — surfaced, deliberately not fixed

Each is documented in `SKILL.md`; none had a mandate to change behavior.

| Finding | Why it matters |
|---|---|
| Neither install layout works alone | Installer puts `ccpm/` at project root → slash commands invisible. Copying into `.claude/` → every `!bash` target breaks. A working install needs both. |
| `prd-list.sh` drops PRDs marked `complete` | Docs say `backlog\|in-progress\|complete`; script buckets on `implemented\|completed\|done`. Counted in total, listed nowhere. `prd-status.sh` disagrees again, calling it backlog. |
| `check-path-standards.sh` cannot exit 0 | Check 4's glob dies under `set -Eeuo pipefail` with no epics; Check 5 wants a file shipped elsewhere, and staging it trips Check 1 (whose `-g '!rules/**'` is anchored to cwd, not the search path). `CLAUDE.md` claims it must exit 0. |
| `init.sh` leaves `.claude/scripts/pm/` empty | Copy step guards on a path that never exists in an installed project. |
| `epic-merge.md` block 3 | Unterminated `"` swallows 24 lines into a commit message; the feature-list loop never runs. |
| `epic-sync.md` block 12 | Indented `EOF` never closes its heredoc. |
| `prd-list.sh` shebang | Ships as `# !/bin/bash` — commented out. |
| 5 of 11 rules never referenced | `path-standards`, `standard-patterns`, `strip-frontmatter`, `test-execution`, `use-ast-grep`. Commands that ought to cite them have no `## Required Rules` line. |

The last three plus the two bash blocks are allowlisted in `driver.sh`
(`KNOWN_BAD_BLOCKS`, `KNOWN_BAD_SHEBANGS`) so a clean checkout stays green.
Fixing one means removing its entry. Fixing `prd-list.sh` means updating the
`smoke` assertion that currently pins the buggy output.

## Suggested agenda for the Workflow session

1. **Decide the install layout.** Everything else is downstream of it — it
   determines whether `.claude/` or `ccpm/` is correct in ~229 prose
   references, and the repo is currently half-migrated between them.
2. **Fix the two broken Workflow commands** (`epic-merge`, `epic-sync`).
   They are live bugs in the pipeline, not cosmetic.
3. **Settle the PRD status vocabulary** — move the script or move the docs.
4. **Decide whether the prompt-driven commands can be tested at all**, and
   if so how. That is the real coverage gap; the harness deliberately stops
   at the shell boundary today.

## Working notes

- No CI in this repo — no `.github/`, no workflows. The only check is a WIP
  marketplace bot that goes red while a PR is a draft. The harness exits
  non-zero on regression, so it is CI-ready if you want it wired up.
- `gh` is not preinstalled here; `apt-get install -y gh` works (2.45.0). The
  harness does not need it except for the one `init.sh` check.
- Anything under `.claude/` is inside `check-path-standards.sh`'s scan
  scope, including this file — do not write literal absolute-path examples
  into it or the lint goes red.
