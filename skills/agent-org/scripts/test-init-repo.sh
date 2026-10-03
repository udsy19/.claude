#!/usr/bin/env bash
# Offline end-to-end test of the installer (init-repo.mjs) and what it installs: a fresh git repo
# (path with a space), a sandboxed HOME, then the landing gates graded against real commits.
#   bash scripts/test-init-repo.sh          (KEEP=1 keeps the sandbox for inspection)
# Exercises: refusal on a missing key → install (no placeholder left) → the owner-rulings rule and
# the PR-gate workflow, filled → setup commit passes org-board and plan-ownership → commits to the
# protected rulings/settings files without authority are red, with it green → re-run changes nothing,
# an existing workflow is kept → a renamed main branch reaches the workflow.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
SB=$(mktemp -d /tmp/init-repo-test.XXXXXX)
REPO="$SB/my repo"
PASS=0; FAIL=0
cleanup() { [ "${KEEP:-}" = 1 ] && echo "sandbox kept: $SB" || rm -rf "$SB"; }
trap cleanup EXIT
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
export HOME="$SB/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset ORG_ROLE ORG_MAIN_BRANCH AGENT_NAME AGENT_ORG_HEADLESS

vars() {   # vars <file> <main-branch> [omit-key] — from the shared fixture scripts/test-vars.json
  python3 - "$KIT/scripts/test-vars.json" "$1" "$2" "${3:-}" <<'EOF'
import json, sys
v = json.load(open(sys.argv[1])); v["MAIN_BRANCH"] = sys.argv[3]; v.pop(sys.argv[4], None)
json.dump(v, open(sys.argv[2], "w"))
EOF
}
yaml_ok() {   # parse with whatever the host has; no new dependency
  if python3 -c 'import yaml' 2>/dev/null; then python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1"
  elif command -v ruby >/dev/null; then ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$1"
  else echo "no YAML parser (python3-yaml or ruby) to check $1" >&2; return 1; fi
}
install() { node "$KIT/scripts/init-repo.mjs" --repo "$1" --vars "$2"; }

echo "== sandbox $SB"
git init -q -b main "$REPO" && cd "$REPO" || exit 2
git commit -q --allow-empty -m root && git checkout -q -b agent-org-setup

echo "== a missing key refuses before writing"
vars "$SB/partial.json" main EXTRA_RULINGS
out=$(install "$REPO" "$SB/partial.json" 2>&1); rc=$?
check "missing EXTRA_RULINGS: exit 2, names the key" "[ $rc = 2 ] && printf '%s' \"\$out\" | grep -q EXTRA_RULINGS"
check "...and wrote nothing" "[ -z \"\$(git status --porcelain)\" ]"

echo "== install"
vars "$SB/vars.json" main
install "$REPO" "$SB/vars.json" > "$SB/install.log" 2>&1; rc=$?
check "init-repo exits 0" "[ $rc = 0 ]"
check "no {{UPPER_SNAKE}} placeholder left anywhere" "! grep -rlE '\{\{[A-Z][A-Z0-9_]*\}\}' --exclude-dir=.git . >/dev/null"
R=.claude/rules/owner-rulings.md
check "owner-rulings rule installed (rules.tmpl -> rules)" "[ -f $R ]"
check "...carrying the four standing rulings and the owner's extra one" "grep -q 'Goals, not tests' $R && grep -q 'Ship weekly' $R"
check "...and saying who may write it (Authority: owner)" "grep -q 'Authority: owner' $R"
WF=.github/workflows/org-gates.yml
check "PR-gate workflow installed (dot-dir walked)" "[ -f $WF ]"
check "...on PRs to the main branch, filled" "grep -q 'branches: \[main\]' $WF && grep -q 'ORG_MAIN_BRANCH: main' $WF"
check "...runs org-board, plan-ownership and sprawl" "grep -q 'org-board.sh' $WF && grep -q 'plan-ownership.mjs' $WF && grep -q 'sprawl.mjs' $WF"
check "...and is valid YAML" "yaml_ok $WF"
check "settings.json is protected by the shared declaration" "grep -q \"'.claude/settings.json'\" scripts/lib/protected-paths.mjs"

echo "== setup commit, then the board"
git add -A && git commit -qm "agent-org setup

Authority: owner
EVIDENCE-GROWTH: adds vault/Home.md and the vault contracts, .claude/rules/owner-rulings.md with the
other rules, and .github/workflows/org-gates.yml so the gates run on every PR."
board=$(bash scripts/gates/org-board.sh 2>&1); rc=$?
check "org-board exits 0 on the fresh install" "[ $rc = 0 ]" || printf '%s\n' "$board" | tail -6
check "plan-ownership passes the setup commit" "node scripts/gates/plan-ownership.mjs >/dev/null 2>&1"
SETUP=$(git rev-parse HEAD)

echo "== the protected rulings and settings files, graded from git"
po() { node scripts/gates/plan-ownership.mjs --since "$SETUP" >/dev/null 2>&1; echo $?; }
git checkout -q -b drift
echo "- **A ruling nobody gave.**" >> $R && git commit -qam "tweak rulings"
check "a commit to owner-rulings.md with no Authority is RED (plan-ownership exit 1)" "[ \$(po) = 1 ]"
git reset -q --hard "$SETUP"
echo "- **Ship weekly, measured on main.**" >> $R && git commit -qam "record the owner's ruling

Authority: owner"
check "...with Authority: owner it is green" "[ \$(po) = 0 ]"
git reset -q --hard "$SETUP"
python3 -c "import json;p='.claude/settings.json';d=json.load(open(p));d['hooks'].pop('PreToolUse');json.dump(d,open(p,'w'),indent=2)"
git commit -qam "quiet the hook"
check "a commit unwiring the contract hook in settings.json is RED" "[ \$(po) = 1 ]"
git reset -q --hard "$SETUP"; git checkout -q agent-org-setup; git branch -qD drift

echo "== re-run is idempotent; an existing workflow is kept"
install "$REPO" "$SB/vars.json" > /dev/null 2>&1; rc=$?
check "re-run exits 0 and changes nothing (git status clean)" "[ $rc = 0 ] && [ -z \"\$(git status --porcelain)\" ]"
echo "# the team's own gate" > $WF && git commit -qam "own workflow"
install "$REPO" "$SB/vars.json" > /dev/null 2>&1
check "an existing org-gates.yml is never overwritten" "[ \"\$(cat $WF)\" = '# the team'\"'\"'s own gate' ]"

echo "== a different main branch reaches the workflow"
R2="$SB/trunk repo"; git init -q -b trunk "$R2" && git -C "$R2" commit -q --allow-empty -m root
vars "$SB/trunk.json" trunk
install "$R2" "$SB/trunk.json" > /dev/null 2>&1
check "MAIN_BRANCH=trunk: workflow gates PRs to trunk" "grep -q 'branches: \[trunk\]' \"$R2/$WF\" && grep -q 'ORG_MAIN_BRANCH: trunk' \"$R2/$WF\""

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
