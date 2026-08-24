#!/usr/bin/env bash
# CCPM harness: static-lints the plugin marketplace, then seeds a throwaway
# project with fixture PRD/epic/task data and runs every script-backed
# /pm:* command against it asserting real output.
#
#   driver.sh lint      static checks on plugins/ (no sandbox needed)
#   driver.sh sandbox   build scratch project + fixtures
#   driver.sh smoke     run all 14 script-backed commands, assert output
#   driver.sh all       lint + sandbox + smoke
#
# Run from the repo root. Sandbox dir: $CCPM_SANDBOX (default /tmp/ccpm-sandbox).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SANDBOX="${CCPM_SANDBOX:-/tmp/ccpm-sandbox}"
case "$SANDBOX" in /*) ;; *) SANDBOX="$PWD/$SANDBOX" ;; esac   # cmd_smoke needs it absolute
PLUGINS="$REPO/plugins"
PM_SCRIPTS="$PLUGINS/pm-core/scripts/pm"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
head_() { echo; echo "=== $* ==="; }

# Fenced bash blocks that are already broken on main. New entries here are
# regressions and fail the lint. See SKILL.md "Known-broken command blocks".
KNOWN_BAD_BLOCKS="plugins/pm-core/commands/pm/epic-merge.md:3
plugins/pm-core/commands/pm/epic-sync.md:12"

# Scripts shipping a broken/absent shebang today. Same deal: known, not new.
KNOWN_BAD_SHEBANGS="prd-list.sh"

# Every plugin directory, one per line.
plugin_dirs() { find "$PLUGINS" -mindepth 1 -maxdepth 1 -type d | sort; }

# ---------------------------------------------------------------- lint

lint_manifests() {
  head_ "plugin + marketplace manifests"
  local mk="$REPO/.claude-plugin/marketplace.json"
  if [ ! -f "$mk" ]; then bad ".claude-plugin/marketplace.json missing"; return; fi
  if python3 -m json.tool "$mk" >/dev/null 2>&1; then ok "marketplace.json is valid JSON"
  else bad "marketplace.json is not valid JSON"; return; fi

  # every source listed in the marketplace must exist and carry a manifest
  while read -r entry; do
    [ -n "$entry" ] || continue
    if [ -d "$REPO/$entry" ]; then ok "marketplace source exists: $entry"
    else bad "marketplace lists $entry but no such directory"; continue; fi
    if [ -f "$REPO/$entry/.claude-plugin/plugin.json" ]; then :
    else bad "$entry has no .claude-plugin/plugin.json"; fi
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for p in d.get("plugins",[]):
    print(str(p.get("source","")).lstrip("./"))
' "$mk" 2>/dev/null)

  # every plugin on disk must have a valid manifest whose name matches its dir
  while read -r d; do
    local name manifest
    name="$(basename "$d")"
    manifest="$d/.claude-plugin/plugin.json"
    if [ ! -f "$manifest" ]; then bad "$name: no .claude-plugin/plugin.json"; continue; fi
    if ! python3 -m json.tool "$manifest" >/dev/null 2>&1; then
      bad "$name: plugin.json is not valid JSON"; continue
    fi
    declared=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$manifest")
    if [ "$declared" = "$name" ]; then ok "$name: manifest valid, name matches directory"
    else bad "$name: plugin.json declares name '$declared'"; fi
  done < <(plugin_dirs)

  # hook configs must be valid JSON too
  while read -r h; do
    [ -f "$h" ] || continue
    rel="${h#$REPO/}"
    if python3 -m json.tool "$h" >/dev/null 2>&1; then ok "$rel is valid JSON"
    else bad "$rel is not valid JSON"; fi
  done < <(find "$PLUGINS" -name 'hooks.json' | sort)
}

lint_scripts() {
  head_ "bash -n: shipped scripts"
  local n=0
  while read -r f; do
    n=$((n+1))
    if err=$(bash -n "$f" 2>&1); then ok "${f#$REPO/}"; else bad "${f#$REPO/}: $err"; fi
  done < <(find "$PLUGINS" -name '*.sh' | sort)
  [ "$n" -eq 0 ] && bad "found no shipped scripts at all"
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
  done < <(find "$PLUGINS" -name '*.sh' | sort)
}

# Commands address their scripts as ${CLAUDE_PLUGIN_ROOT}/scripts/... .
# Resolve that per plugin: the variable expands to the plugin's own root.
lint_command_paths() {
  head_ "command -> script path resolution (\${CLAUDE_PLUGIN_ROOT})"
  local n=0
  while read -r d; do
    [ -d "$d/commands" ] || continue
    local root="$d" name; name="$(basename "$d")"

    while read -r p; do
      n=$((n+1))
      resolved="${p/\$\{CLAUDE_PLUGIN_ROOT\}/$root}"
      case "$p" in
        *'${CLAUDE_PLUGIN_ROOT}'*) ;;
        *) bad "$name: !bash $p does not use \${CLAUDE_PLUGIN_ROOT}"; continue ;;
      esac
      if [ -f "$resolved" ]; then ok "$name: !bash ${resolved#$REPO/}"
      else bad "$name: !bash $p (no such script)"; fi
    done < <(grep -rhoE '^!bash [^ ]+\.sh' "$d/commands" | sed 's/^!bash //' | sort -u)

    while read -r p; do
      resolved="${p/\$\{CLAUDE_PLUGIN_ROOT\}/$root}"
      case "$p" in
        *'${CLAUDE_PLUGIN_ROOT}'*) ;;
        *) bad "$name: allowed-tools $p does not use \${CLAUDE_PLUGIN_ROOT}"; continue ;;
      esac
      if [ -f "$resolved" ]; then ok "$name: allowed-tools ${resolved#$REPO/}"
      else bad "$name: allowed-tools $p (no such script)"; fi
    done < <(grep -rhoE 'Bash\(bash [^ )]+\.sh' "$d/commands" | sed 's/^Bash(bash //' | sort -u)
  done < <(plugin_dirs)
  [ "$n" -eq 0 ] && bad "found no !bash invocation lines at all"
}

lint_frontmatter() {
  head_ "command frontmatter"
  local n=0
  while read -r f; do
    n=$((n+1)); rel="${f#$REPO/}"
    if [ "$(head -1 "$f")" != "---" ]; then bad "$rel: does not open with ---"; continue; fi
    close=$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")
    if [ -z "$close" ]; then bad "$rel: frontmatter never closes"; continue; fi
    if ! sed -n "2,$((close-1))p" "$f" | grep -q '^allowed-tools:'; then bad "$rel: no allowed-tools"; continue; fi
    ok "$rel"
  done < <(find "$PLUGINS" -path '*/commands/*' -name '*.md' | sort)
  [ "$n" -eq 0 ] && bad "found no command files at all"
}

# The rules/*.md bundle became the ccpm-rules plugin's auto-activating skills.
# Skills are matched by description, not by path, so the check is now: every
# SKILL.md carries name+description, and no command still points at a rules path.
lint_skills() {
  head_ "ccpm-rules skills"
  local n=0
  while read -r f; do
    n=$((n+1)); rel="${f#$REPO/}"
    dir="$(basename "$(dirname "$f")")"
    if [ "$(head -1 "$f")" != "---" ]; then bad "$rel: does not open with ---"; continue; fi
    close=$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")
    if [ -z "$close" ]; then bad "$rel: frontmatter never closes"; continue; fi
    fm=$(sed -n "2,$((close-1))p" "$f")
    declared=$(grep -m1 '^name:' <<<"$fm" | sed 's/^name: *//')
    if [ -z "$declared" ]; then bad "$rel: no name in frontmatter"; continue; fi
    if [ "$declared" != "$dir" ]; then bad "$rel: name '$declared' != directory '$dir'"; continue; fi
    if ! grep -q '^description:' <<<"$fm"; then
      bad "$rel: no description -- the skill can never auto-activate"; continue
    fi
    ok "$rel"
  done < <(find "$PLUGINS" -path '*/skills/*' -name 'SKILL.md' | sort)
  [ "$n" -eq 0 ] && bad "found no skills at all"

  head_ "no stale rules/*.md references remain"
  local stale
  stale=$(grep -rlE '(\.claude|ccpm)/rules/[A-Za-z0-9._-]+\.md' "$PLUGINS" 2>/dev/null)
  if [ -z "$stale" ]; then ok "no command or skill points at a retired rules/ path"
  else
    bad "stale rules/ references (those files no longer exist):"
    sed "s|^$REPO/|       |" <<<"$stale" | head -10
  fi
}

lint_bash_blocks() {
  head_ "bash -n: fenced blocks inside command/skill/agent markdown"
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
  done < <(find "$PLUGINS" \( -path '*/commands/*' -o -path '*/skills/*' -o -path '*/agents/*' \) -name '*.md' | sort)
  rm -rf "$tmp"
  echo "  checked $total blocks: $newbad new failures, $knownhit known-bad"
  [ "$total" -eq 0 ] && bad "found no fenced bash blocks at all -- the glob is probably wrong"
  [ "$newbad" -eq 0 ] && ok "no new bash-block regressions"
}

lint_path_standards() {
  # NOTE: this script can never exit 0 (see SKILL.md "check-path-standards.sh
  # cannot pass"). Assert the substantive scans -- Checks 1-3 -- instead.
  head_ "check-path-standards.sh (Checks 1-3)"
  local out
  out=$(cd "$REPO" && bash "$PLUGINS/pm-core/scripts/check-path-standards.sh" 2>&1)
  for c in "No absolute path violations found" \
           "No user-specific paths found" \
           "Path formats are consistent"; do
    if grep -qF "$c" <<<"$out"; then ok "$c"; else bad "check-path-standards: '$c' did not pass"; fi
  done
  if grep -qF "Found absolute path violations" <<<"$out" \
  || grep -qF "Found user-specific paths"    <<<"$out"; then
    bad "real path violations introduced:"; grep -E '^\.claude|^plugins' <<<"$out" | head -10 | sed 's/^/       /'
  fi
}

cmd_lint() {
  lint_manifests; lint_scripts; lint_shebangs; lint_command_paths
  lint_frontmatter; lint_skills; lint_bash_blocks; lint_path_standards
}

# ------------------------------------------------------------- sandbox

cmd_sandbox() {
  head_ "building sandbox at $SANDBOX"
  rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  ( cd "$SANDBOX" || exit 1
  git init -q .
  git remote add origin https://github.com/acme/demo-app.git   # NOT automazeio/ccpm
  # Under the plugin model there is no copy step: Claude Code installs the
  # plugin out-of-tree and the commands reach their scripts through
  # ${CLAUDE_PLUGIN_ROOT}. The user's project holds runtime data only --
  # exactly the two directories init.sh creates.
  mkdir -p .claude/prds .claude/epics
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
  # Scripts run from the user's project but live in the installed plugin --
  # CLAUDE_PLUGIN_ROOT is what Claude Code exports for exactly this.
  # NB: "${args[@]:-}" would pass one empty string, not zero args.
  if [ ${#args[@]} -eq 0 ]; then
    out=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$PLUGINS/pm-core" bash "$PM_SCRIPTS/$script" 2>&1); rc=$?
  else
    out=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$PLUGINS/pm-core" bash "$PM_SCRIPTS/$script" "${args[@]}" 2>&1); rc=$?
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
    out=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$PLUGINS/pm-core" timeout 120 bash "$PM_SCRIPTS/init.sh" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "Initialization Complete" <<<"$out"; then
      ok "init.sh completes (exit 0) despite unauthenticated gh"
    else
      bad "init.sh exit $rc"; tail -5 <<<"$out" | sed 's/^/         | /'
    fi
    # Under the plugin model init.sh creates runtime data only. The old
    # copy-scripts-into-.claude step (and the empty-dir defect it left behind)
    # is gone -- assert it stays gone.
    if [ -d "$SANDBOX/.claude/prds" ] && [ -d "$SANDBOX/.claude/epics" ]; then
      ok "init.sh creates the runtime data directories"
    else
      bad "init.sh did not create .claude/prds and .claude/epics"
    fi
    if [ -e "$SANDBOX/.claude/scripts" ]; then
      bad "init.sh still creates .claude/scripts -- that is the retired copy-install step"
    else
      ok "init.sh no longer copies scripts into .claude (plugin resolves its own paths)"
    fi
  else
    echo "  skipped: gh not installed (apt-get install -y gh)"
  fi

  head_ "install wiring: every command's script resolves from its plugin root"
  local n=0 broken=0
  while read -r d; do
    [ -d "$d/commands" ] || continue
    while read -r f; do
      scr=$(grep -oE '^!bash [^ ]+\.sh' "$f" | sed 's/^!bash //')
      [ -n "$scr" ] || continue
      n=$((n+1))
      resolved="${scr/\$\{CLAUDE_PLUGIN_ROOT\}/$d}"
      [ -f "$resolved" ] || { broken=$((broken+1)); bad "${f#$REPO/} -> $scr unresolved"; }
    done < <(find "$d/commands" -name '*.md' | sort)
  done < <(plugin_dirs)
  if [ "$n" -gt 0 ] && [ "$broken" -eq 0 ]; then
    ok "$n script-backed commands resolve against their plugin root"
  elif [ "$n" -eq 0 ]; then bad "no script-backed commands found"; fi

  head_ "validate.sh catches a broken dependency reference"
  local out
  sed -i 's/^depends_on: \[001\]/depends_on: [099]/' "$SANDBOX/.claude/epics/user-auth/002.md"
  out=$(cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$PLUGINS/pm-core" bash "$PM_SCRIPTS/validate.sh" 2>&1)
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
