#!/usr/bin/env bash
# CCPM harness: static-lints the asset bundle, then installs it into a
# throwaway project, seeds fixture PRD/epic/task data, and runs every
# script-backed /pm:* command against it asserting real output.
#
#   driver.sh lint      static checks on ccpm/ (no sandbox needed)
#   driver.sh sandbox   build scratch project + fixtures
#   driver.sh smoke     run all 14 script-backed commands, assert output
#   driver.sh all       lint + sandbox + smoke
#
# Run from the repo root. Sandbox dir: $CCPM_SANDBOX (default /tmp/ccpm-sandbox).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SANDBOX="${CCPM_SANDBOX:-/tmp/ccpm-sandbox}"
case "$SANDBOX" in /*) ;; *) SANDBOX="$PWD/$SANDBOX" ;; esac   # cmd_smoke needs it absolute
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
head_() { echo; echo "=== $* ==="; }

# Fenced bash blocks that are already broken on main. New entries here are
# regressions and fail the lint. See SKILL.md "Known-broken command blocks".
KNOWN_BAD_BLOCKS="ccpm/commands/pm/epic-merge.md:3
ccpm/commands/pm/epic-sync.md:12"

# Scripts shipping a broken/absent shebang today. Same deal: known, not new.
KNOWN_BAD_SHEBANGS="prd-list.sh"

# ---------------------------------------------------------------- lint

lint_scripts() {
  head_ "bash -n: shipped scripts"
  while read -r f; do
    if err=$(bash -n "$f" 2>&1); then ok "$f"; else bad "$f: $err"; fi
  done < <(find "$REPO/ccpm" -name '*.sh' | sed "s|$REPO/||" | sort | sed "s|^|$REPO/|")
}

lint_shebangs() {
  head_ "shebangs"
  while read -r f; do
    first=$(head -1 "$f")
    case "$first" in
      '#!'*) ok "$(basename "$f"): $first" ;;
      *)
        if grep -qx "$(basename "$f")" <<<"$KNOWN_BAD_SHEBANGS"; then
          echo "  known-bad $(basename "$f"): shebang commented out -> '$first'"
        else
          bad "$(basename "$f"): shebang is commented out or missing -> '$first'"
        fi ;;
    esac
  done < <(find "$REPO/ccpm" -name '*.sh' | sort)
}

lint_command_paths() {
  head_ "command -> script path resolution"
  local n=0
  while read -r p; do
    n=$((n+1))
    if [ -f "$REPO/$p" ]; then ok "!bash $p"; else bad "!bash $p (no such script)"; fi
  done < <(grep -rhoE '^!bash [^ ]+\.sh' "$REPO/ccpm/commands" | sed 's/^!bash //' | sort -u)
  [ "$n" -eq 0 ] && bad "found no !bash invocation lines at all"

  while read -r p; do
    if [ -f "$REPO/$p" ]; then ok "allowed-tools $p"; else bad "allowed-tools $p (no such script)"; fi
  done < <(grep -rhoE 'Bash\(bash [^ )]+\.sh' "$REPO/ccpm/commands" | sed 's/^Bash(bash //' | sort -u)
}

lint_frontmatter() {
  head_ "command frontmatter"
  while read -r f; do
    rel="${f#$REPO/}"
    if [ "$(head -1 "$f")" != "---" ]; then bad "$rel: does not open with ---"; continue; fi
    close=$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")
    if [ -z "$close" ]; then bad "$rel: frontmatter never closes"; continue; fi
    if ! sed -n "2,$((close-1))p" "$f" | grep -q '^allowed-tools:'; then bad "$rel: no allowed-tools"; continue; fi
    ok "$rel"
  done < <(find "$REPO/ccpm/commands" -name '*.md' | sort)
}

lint_rule_refs() {
  head_ "rules/*.md references resolve"
  local n=0
  while read -r r; do
    n=$((n+1)); base="${r##*/}"
    if [ -f "$REPO/ccpm/rules/$base" ]; then ok "$r -> ccpm/rules/$base"
    else bad "$r references a rule that does not exist"; fi
  done < <(grep -rhoE '(\.claude|ccpm)?/rules/[A-Za-z0-9._-]+\.md' \
             "$REPO/ccpm/commands" "$REPO/ccpm/agents" \
           | grep -oE '/rules/[A-Za-z0-9._-]+\.md' | sort -u)
  [ "$n" -eq 0 ] && echo "  (no rule references found)"
}

lint_bash_blocks() {
  head_ "bash -n: fenced blocks inside command/rule/agent markdown"
  local tmp total=0 newbad=0 knownhit=0
  tmp=$(mktemp -d)
  while read -r f; do
    rel="${f#$REPO/}"
    awk '/^```bash$/{n++;inb=1;next} /^```/{inb=0} inb{print > (d "/b" n)}' d="$tmp" "$f"
    for blk in "$tmp"/b*; do
      [ -f "$blk" ] || continue
      idx="${blk##*/b}"; total=$((total+1))
      if ! err=$(bash -n "$blk" 2>&1); then
        if grep -qx "$rel:$idx" <<<"$KNOWN_BAD_BLOCKS"; then
          knownhit=$((knownhit+1)); echo "  known-bad $rel [block $idx]"
        else
          newbad=$((newbad+1)); bad "$rel [block $idx]: $(head -1 <<<"$err")"
        fi
      fi
      rm -f "$blk"
    done
  done < <(find "$REPO/ccpm/commands" "$REPO/ccpm/rules" "$REPO/ccpm/agents" -name '*.md' | sort)
  rm -rf "$tmp"
  echo "  checked $total blocks: $newbad new failures, $knownhit known-bad"
  [ "$newbad" -eq 0 ] && ok "no new bash-block regressions"
}

lint_path_standards() {
  # NOTE: this script can never exit 0 (see SKILL.md "check-path-standards.sh
  # cannot pass"). Assert the substantive scans -- Checks 1-3 -- instead.
  head_ "check-path-standards.sh (Checks 1-3)"
  local out
  out=$(cd "$REPO" && bash ccpm/scripts/check-path-standards.sh 2>&1)
  for c in "No absolute path violations found" \
           "No user-specific paths found" \
           "Path formats are consistent"; do
    if grep -qF "$c" <<<"$out"; then ok "$c"; else bad "check-path-standards: '$c' did not pass"; fi
  done
  if grep -qF "Found absolute path violations" <<<"$out" \
  || grep -qF "Found user-specific paths"    <<<"$out"; then
    bad "real path violations introduced:"; grep -E '^\.claude|^ccpm' <<<"$out" | head -10 | sed 's/^/       /'
  fi
}

cmd_lint() {
  lint_scripts; lint_shebangs; lint_command_paths; lint_frontmatter
  lint_rule_refs; lint_bash_blocks; lint_path_standards
}

# ------------------------------------------------------------- sandbox

cmd_sandbox() {
  head_ "building sandbox at $SANDBOX"
  rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  ( cd "$SANDBOX" || exit 1
  git init -q .
  git remote add origin https://github.com/acme/demo-app.git   # NOT automazeio/ccpm
  cp -r "$REPO/ccpm" .                                         # what install/ccpm.sh yields
  mkdir -p .claude/prds .claude/epics                          # what init.sh yields
  # Neither layout alone works (see SKILL.md "The install is a hybrid"):
  # scripts must sit at ccpm/ for the !bash lines, commands must sit at
  # .claude/ for Claude Code to register the slash commands.
  ln -s ../ccpm/commands .claude/commands
  ln -s ../ccpm/agents   .claude/agents
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  prd() { # prd <name> <status> <desc>
    cat > ".claude/prds/$1.md" <<EOF
---
name: $1
description: $3
status: $2
created: $now
updated: $now
---

# $1

## Problem
Users need $3.

## Requirements
- Authentication and authorization for the $1 surface.
EOF
  }
  prd user-auth backlog     "Authentication for the demo app"
  prd payments  in-progress "Card payments and refunds"
  prd search-v2 complete    "Rewritten search backend"   # documented vocabulary

  epic() { # epic <name> <status> <progress> [github]
    mkdir -p ".claude/epics/$1"
    { echo "---"; echo "name: $1"; echo "status: $2"; echo "progress: $3"
      echo "prd: .claude/prds/$1.md"; echo "created: $now"; echo "updated: $now"
      [ -n "${4:-}" ] && echo "github: $4"
      echo "---"; echo; echo "# Epic: $1"; echo; echo "## Approach"
      echo "Implement $1 incrementally."
    } > ".claude/epics/$1/epic.md"
  }
  task() { # task <epic> <num> <name> <status> <deps> <parallel>
    cat > ".claude/epics/$1/$2.md" <<EOF
---
name: $3
status: $4
depends_on: [$5]
parallel: $6
created: $now
updated: $now
---

# Task $2: $3

Implement $3 for the $1 epic.
EOF
  }

  epic user-auth in-progress 40% https://github.com/acme/demo-app/issues/10
  task user-auth 001 "Session token model"   open   ""    true
  task user-auth 002 "Login endpoint"        open   "001" false
  task user-auth 003 "Password hashing"      closed ""    true
  mkdir -p .claude/epics/user-auth/updates/002
  cat > .claude/epics/user-auth/updates/002/progress.md <<EOF
---
issue: 002
completion: 35%
last_sync: $now
---

Wired the handler, still need tests.
EOF

  epic payments backlog 0%
  task payments 001 "Stripe client wrapper" open "" true

  epic search-v2 completed 100%
  task search-v2 001 "Swap in new indexer" closed "" false

  )
  echo "  sandbox ready: 3 PRDs, 3 epics, 5 tasks (3 open / 2 closed), 1 in-progress update"
}

# --------------------------------------------------------------- smoke

# expect <label> <script> [args...] -- [rc=N] <substring>...
expect() {
  local label="$1" script="$2"; shift 2
  local args=() want=() want_rc=0
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do args+=("$1"); shift; done; shift || true
  while [ $# -gt 0 ]; do
    case "$1" in rc=*) want_rc="${1#rc=}" ;; *) want+=("$1") ;; esac; shift
  done

  local out rc
  # NB: "${args[@]:-}" would pass one empty string, not zero args.
  if [ ${#args[@]} -eq 0 ]; then
    out=$(cd "$SANDBOX" && bash "ccpm/scripts/pm/$script" 2>&1); rc=$?
  else
    out=$(cd "$SANDBOX" && bash "ccpm/scripts/pm/$script" "${args[@]}" 2>&1); rc=$?
  fi
  local missing=()
  [ "$rc" = "$want_rc" ] || missing+=("<exit $want_rc, got $rc>")
  for w in "${want[@]}"; do grep -qF -- "$w" <<<"$out" || missing+=("$w"); done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "$label (exit $rc)"
  else
    bad "$label (exit $rc) missing:"
    for m in "${missing[@]}"; do echo "         want: $m"; done
    echo "$out" | sed 's/^/         | /' | head -25
  fi
}

cmd_smoke() {
  [ -d "$SANDBOX/.claude/epics" ] || { echo "no sandbox; run: driver.sh sandbox"; exit 1; }
  head_ "script-backed /pm:* commands against the sandbox"

  expect "/pm:status"      status.sh      -- "📊 Project Status" "Total: 3" "Open: 3" "Closed: 2"
  # KNOWN BUG: a PRD with the documented status `complete` matches none of
  # prd-list.sh's three buckets, so it is counted in the total but listed
  # nowhere (1 + 1 + 0 != 3). See SKILL.md "Known-broken command blocks".
  expect "/pm:prd-list"    prd-list.sh    -- "Total PRDs: 3" "Backlog: 1" "In-Progress: 1" "Implemented: 0"
  expect "/pm:prd-status"  prd-status.sh  -- "PRD Status Report" "Total PRDs: 3"
  expect "/pm:epic-list"   epic-list.sh   -- "Total epics: 3" "Total tasks: 5" "user-auth" "search-v2"
  expect "/pm:epic-show"   epic-show.sh   user-auth -- "Epic: user-auth" "Total tasks: 3" "Open: 2" "Closed: 1" "Completion: 33%"
  expect "/pm:epic-status" epic-status.sh user-auth -- "Epic Status: user-auth" "Total tasks: 3" "✅ Completed: 1" "⏸️ Blocked: 1"
  expect "/pm:next"        next.sh        -- "Summary: 2 tasks ready" "#001 - Session token model" "Can run in parallel"
  expect "/pm:blocked"     blocked.sh     -- "Total blocked: 1 tasks" "#002 - Login endpoint" "Waiting for: #001"
  expect "/pm:in-progress" in-progress.sh -- "Issue #002" "35% complete"
  expect "/pm:standup"     standup.sh     -- "Daily Standup" "Issue #002" "3 open, 2 closed, 5 total"
  expect "/pm:search"      search.sh      authentication -- "Search results for: 'authentication'"
  expect "/pm:validate"    validate.sh    -- "System is healthy!" "Errors: 0" "Warnings: 0"
  expect "/pm:help"        help.sh        -- "Claude Code PM" "/pm:prd-new" "/pm:epic-sync"

  head_ "error paths"
  expect "epic-show w/o arg"   epic-show.sh   -- rc=1 "Please provide an epic name"
  expect "epic-status w/o arg" epic-status.sh -- rc=1 "Please specify an epic name"
  expect "search w/o arg"      search.sh      -- rc=1 "Please provide a search query"
  expect "epic-show bogus"     epic-show.sh   nope -- rc=1 "Epic not found: nope"

  head_ "init.sh (the 14th script; needs gh, mutates the sandbox)"
  if command -v gh >/dev/null 2>&1; then
    local out rc
    out=$(cd "$SANDBOX" && timeout 120 bash ccpm/scripts/pm/init.sh 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "Initialization Complete" <<<"$out"; then
      ok "init.sh completes (exit 0) despite unauthenticated gh"
    else
      bad "init.sh exit $rc"; tail -5 <<<"$out" | sed 's/^/         | /'
    fi
    # documents the empty-dir defect rather than asserting it is correct
    if [ -d "$SANDBOX/.claude/scripts/pm" ] && [ -z "$(ls -A "$SANDBOX/.claude/scripts/pm")" ]; then
      ok "known defect reproduced: init.sh leaves .claude/scripts/pm empty"
    else
      bad "init.sh: .claude/scripts/pm no longer matches the documented defect"
    fi
  else
    echo "  skipped: gh not installed (apt-get install -y gh)"
  fi

  head_ "install wiring: slash commands discoverable AND their scripts resolve"
  local n=0 broken=0
  while read -r f; do
    n=$((n+1)); rel="${f#$SANDBOX/}"
    scr=$(grep -oE '^!bash [^ ]+\.sh' "$f" | sed 's/^!bash //')
    [ -n "$scr" ] || continue
    if [ -f "$SANDBOX/$scr" ]; then :; else broken=$((broken+1)); bad "$rel -> $scr unresolved"; fi
  done < <(find -L "$SANDBOX/.claude/commands" -name '*.md' 2>/dev/null | sort)
  if [ "$n" -gt 0 ] && [ "$broken" -eq 0 ]; then
    ok "$n commands discoverable under .claude/commands, all !bash targets resolve"
  elif [ "$n" -eq 0 ]; then bad "no commands visible under .claude/commands"; fi

  head_ "validate.sh catches a broken dependency reference"
  local out
  sed -i 's/^depends_on: \[001\]/depends_on: [099]/' "$SANDBOX/.claude/epics/user-auth/002.md"
  out=$(cd "$SANDBOX" && bash ccpm/scripts/pm/validate.sh 2>&1)
  if grep -qF "references missing task: 099" <<<"$out"; then ok "broken ref detected"
  else bad "validate.sh did not flag the broken reference"; echo "$out" | sed 's/^/         | /'; fi
  sed -i 's/^depends_on: \[099\]/depends_on: [001]/' "$SANDBOX/.claude/epics/user-auth/002.md"
}

# ---------------------------------------------------------------- main

case "${1:-all}" in
  lint)    cmd_lint ;;
  sandbox) cmd_sandbox ;;
  smoke)   cmd_smoke ;;
  all)     cmd_lint; cmd_sandbox; cmd_smoke ;;
  *) echo "usage: driver.sh {lint|sandbox|smoke|all}"; exit 2 ;;
esac

echo
echo "================================"
echo "  passed: $PASS   failed: $FAIL"
echo "================================"
[ "$FAIL" -eq 0 ]
