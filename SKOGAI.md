# SKOGAI

Running notes for the human: what we've learned working on this repo, and
what's currently in motion. Newest at the top.

## What we learned

CCPM already has a handover system and it is good — `.claude/context/` driven
by `/context:create` → `/context:prime` → `/context:update`, with the
session-start and session-end rituals spelled out in `ccpm/context/README.md`.
Working without it, an agent burns most of a session re-deriving the project
by hand; every fact in that first `run-ccpm` skill was rediscovered with
`find` and `grep` because there was no context to prime from. The instinct to
write a handover was right, but inventing `HANDOVER.md` was wrong: the project
already had the vocabulary, and a bespoke filename is one nothing produces,
nothing consumes, and no command knows how to refresh. Worse, that file was
parked behind a pull request — and since the next session starts from a fresh
clone of `main`, a handover that isn't on `main` is invisible to the only
audience it has. The fix is boring: context commits land on `main`, and pull
requests are reserved for things a human actually decides.

The sharper finding is that **this repo has never run `/context:create` on
itself** — `.claude/context/` did not exist until now, so a project whose
whole thesis is durable context across agent sessions was not keeping any.
That is fixed as of this commit. Two process lessons came out of the same
stretch: verify claims against primary sources before reporting them (a
notification about "PR #1026" was dismissed as phantom after checking only
this repo, when it was real and sitting upstream in `automazeio/ccpm`), and
remember this repo is a **fork** — GitHub offers upstream as the default base
for new PRs, so `head.repo` and `base.repo` must both read `skogai/ccpm`
before anything is opened. Finally, tooling only counts if it runs: the
`run-ccpm` harness caught two live bugs in shipped command markdown, but only
because it actually executes the commands instead of describing them.

## Currently

- `.claude/context/` now exists — 9 files. Start sessions with
  `/context:prime`, end them with `/context:update`.
- `.claude/skills/run-ccpm/` is the executable harness:
  `bash .claude/skills/run-ccpm/driver.sh all` → 140 assertions, exit 0.
- Next up: the Workflow (`prd-new` → … → `epic-close`). All eleven of those
  commands are prompt-driven with no runtime coverage, and two ship broken
  bash. See `.claude/context/progress.md` for the open list.
