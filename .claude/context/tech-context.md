---
created: 2026-08-23T19:18:48Z
last_updated: 2026-08-23T19:18:48Z
version: 1.0
author: Claude Code PM System
---

# Tech Context

## Stack

**There is no application, no build step, and no package manager.** No
`package.json`, `requirements.txt`, `Cargo.toml`, or `go.mod` exists at any
level. The repo is Markdown plus POSIX shell: 46 command files, 11 rules,
4 agent definitions, 18 shell scripts.

"The program" is the Markdown — command files are prompts another Claude
instance executes literally, and rule files are shared specs those prompts
include by reference.

## Runtime dependencies

| Tool | Needed for | Notes |
|---|---|---|
| `bash` | everything | 5.2.21 verified here; scripts use bashisms (`((n++))`, arrays) |
| `git` | most commands | |
| `gh` | GitHub sync only | **not preinstalled**; `apt-get install -y gh` works (2.45.0) |
| `gh-sub-issue` | parent/child issue links | extension; task-list fallback exists |
| `rg` | `check-path-standards.sh` | preinstalled |

The 13 script-backed reporting commands touch no network and need none of the
GitHub tooling.

## Verification

There is no test suite. The check that exists is the harness:

```bash
bash .claude/skills/run-ccpm/driver.sh all      # 140 assertions
```

`lint` (119) is static — `bash -n` over every shipped script, shebangs,
`!bash` and `allowed-tools` target resolution, frontmatter, rule-reference
resolution, and `bash -n` over all 110 fenced bash blocks in command markdown.
`smoke` (21) is runtime — installs the bundle into a throwaway project and
asserts real command output.

No CI is configured: there is no `.github/` directory and no workflow files.
The harness exits non-zero on regression, so it is CI-ready if wired up.

## Git topology

`origin` is `skogai/ccpm`. `SkogBackup/ccpm` is a **301 redirect to the same
repo** (the owner was renamed) — both paths serve identical refs. This repo is
a **fork of `automazeio/ccpm`**, which means GitHub offers upstream as the
default base for a new PR. Confirm `head.repo` and `base.repo` both read
`skogai/ccpm` before opening anything, and never open a PR, issue, or comment
against `automazeio/*`.
