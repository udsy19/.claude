#!/usr/bin/env bash
# The /setup permutation matrix, offline: setup.mjs (the engine behind commands/setup.md) run against every
# pairwise combination of scope × install × existing state × OS, every runtime × supervisor × run for
# scope=org, and the named rows that must refuse or hold. Each row gets its own temp HOME, a project whose
# path has a space ("my proj"), and an ORG_ROOT with a space. PATH holds ONLY fakes (uname, id, useradd,
# chown, crontab, launchctl, systemctl, tmux, flock, loginctl, claude, codex) plus links to a fixed list of
# real tools, so nothing here touches the machine: no cron, users, launch agents, logins or pushes.
#   bash scripts/test-setup-matrix.sh          (KEEP=1 keeps the sandbox; the results table is printed last)
# Every row ends PASS (assertions held), REFUSED (the named message, and nothing written), or UNTESTABLE
# (with the reason); a row whose assertions fail is FAIL and fails the run.
# shellcheck disable=SC2016  # the fakes' bodies are single-quoted on purpose: they expand when the fake runs
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd); SC=$KIT/scripts; ENGINE=$SC/setup.mjs
SB=$(mktemp -d "${TMPDIR:-/tmp}/setup-matrix.XXXXXX"); SB=$(cd "$SB" && pwd -P)
FAKES=$SB/fakes; REAL=$SB/real; LOG=$SB/calls.log; RES=$SB/results.md
PASS=0; FAIL=0; ROWFAIL=0
cleanup() { if [ "${KEEP:-}" = 1 ]; then echo "sandbox kept: $SB"; else rm -rf "$SB"; fi; }
trap cleanup EXIT
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); ROWFAIL=1; echo "  FAIL $1"; fi; }
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
row() { ROWFAIL=0; ROW="$1"; DIMS="$2"; echo "== $1  $2"; }
done_row() {  # done_row PASS|REFUSED|UNTESTABLE "<evidence>"
  local o=$1; [ "$ROWFAIL" = 1 ] && o=FAIL
  printf '| %s | %s | %s | %s |\n' "$ROW" "$DIMS" "$o" "$2" >> "$RES"; }
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_NOSYSTEM=1 SB LOG
unset ORG_ROLE ORG_MAIN_BRANCH AGENT_NAME AGENT_ORG_HEADLESS ORG_VAULT CLAUDE_PROJECT_DIR

mkdir -p "$REAL" "$FAKES" "$SB/users"
for t in bash sh env git node python3 rsync mkdir cp chmod ln install cat grep sed awk head tail tr cut sort uniq xargs \
         basename dirname date mktemp rm mv ls touch seq sleep du find wc ps pgrep kill cksum tee readlink pwd true false cmp jq; do
  p=$(command -v "$t") && ln -s "$p" "$REAL/$t"
done
fake() { printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n%s\n' "$1" "$2" > "$FAKES/$1"; chmod +x "$FAKES/$1"; }
fake uname     'echo "${FAKE_OS:-Darwin}"'
fake id        'case "$1" in -u) echo "${FAKE_UID:-501}";; -un) echo "${FAKE_USER:-tester}";; *) [ -f "$SB/users/$1" ];; esac'
fake useradd   'for a; do n=$a; done; touch "$SB/users/$n"'
fake chown     'exit 0'
fake crontab   'u=${FAKE_USER:-tester}; [ "$1" = -u ] && { u=$2; shift 2; }
case "$1" in -l) [ -f "$SB/cron.$u" ] && cat "$SB/cron.$u" || { echo "crontab: no crontab for $u" >&2; exit 1; };;
  -) cat > "$SB/cron.$u.tmp" && mv "$SB/cron.$u.tmp" "$SB/cron.$u";; esac'
fake launchctl 'exit 0'
fake systemctl 'exit 0'
fake tmux      'case "$1" in has-session) [ -f "$SB/tmux.$3" ];; new-session) touch "$SB/tmux.$4";; esac'
fake flock     'exit 0'
fake loginctl  'exit 0'
fake claude    'case "$*" in *"reply with just OK"*) echo OK;; esac'
fake codex     'echo "Logged in (fake)"'
path_without() { local d; d=$SB/path-$(echo "x $*" | cksum | cut -d' ' -f1); mkdir -p "$d"
  for f in "$FAKES"/*; do case " $* " in *" $(basename "$f") "*) ;; *) ln -sf "$f" "$d/";; esac; done; echo "$d:$REAL"; }
export PATH; PATH=$(path_without)

# ── one box per row: a temp HOME, a project "my proj" (git, one commit, a src/ dir), an ORG_ROOT ──
box() {   # box <name> <state: fresh|other|vault|org> <base-install for prior state>
  B=$SB/$1; export HOME=$B/home; P="$B/my proj"; ORGR="$B/org root"; rm -rf "$SB"/cron.* "$SB"/tmux.* "$SB"/users/*
  mkdir -p "$HOME" "$P/src" && git init -q -b main "$P" && echo "# demo" > "$P/README.md" && echo x > "$P/src/a.txt"
  git -C "$P" add -A && git -C "$P" commit -qm init
  case $2 in
    other) mkdir -p "$P/.claude/agents"
      printf '{\n  "permissions": {"allow": ["Bash(npm test)"]},\n  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo other-config"}]}]}\n}\n' > "$P/.claude/settings.json"
      echo "# someone else's agent" > "$P/.claude/agents/other.md"
      git -C "$P" add -A && git -C "$P" commit -qm "another config" ;;
    vault) ans "$B/prior.json" vault "$3"; eng "$B/prior" FAKE_OS=Darwin -- --scope vault --install project --answers "$B/prior.json"; commit_all ;;
    org)   ans "$B/prior.json" org "$3"; eng "$B/prior" FAKE_OS=Darwin -- --scope org --install project --answers "$B/prior.json"; commit_all ;;
  esac
}
commit_all() { git -C "$P" add -A && git -C "$P" commit -qm "setup

Authority: owner
EVIDENCE-GROWTH: adds vault/Home.md and the vault contracts so the project has its mission control." >/dev/null; }
# ans <file> <scope> <base-install> [runtime] [worker_user] [backend] [main]
ans() { python3 - "$KIT/scripts/test-vars.json" "$@" "$ORGR" "$B" <<'PY'
import json, sys
vars_f, out, scope, base, *rest = sys.argv[1:]
orgr, b = rest[-2], rest[-1]; rest = rest[:-2] + [None] * 4
runtime, wuser, backend, main = (rest[0] or "local"), (rest[1] or ""), (rest[2] or "claude"), rest[3]
a = {"permissions": "default", "base_install": base, "project": "Demo", "vision": "A demo for the matrix"}
if main: a["main_branch"] = main
if scope == "org":
    v = json.load(open(vars_f)); v.pop("MAIN_BRANCH"); v.pop("PROJECT"); v["ORG_ROOT"] = orgr
    sup = {"backend": "codex", "model": "gpt-x", "effort": "high"} if backend == "codex" else {"backend": "claude", "model": "opus"}
    a.update(vars=v, org_root=orgr, org={"runtime": runtime, "worker_user": wuser, "supervisor": sup,
             "worker_models": {"opus": "opus"}, "default_worker_model": "opus", "bin_dir": b + "/srvbin"})
json.dump(a, open(out, "w"), indent=1)
PY
}
# eng <outprefix> [ENV=…] -- <setup.mjs args>    → <outprefix>.out, <outprefix>.rc
eng() { local o=$1; shift; local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  (cd "$P" && env ${e[@]+"${e[@]}"} node "$ENGINE" --project "$P" "$@") > "$o.out" 2>&1; echo $? > "$o.rc"; }
rc() { cat "$1.rc"; }
clean() { [ -z "$(git -C "$P" status --porcelain)" ]; }
nothing_written() { [ ! -e "$P/vault" ] && [ ! -e "$HOME/.claude" ] && clean; }

echo "== sandbox $SB"
printf '| row | dimensions | outcome | evidence |\n|---|---|---|---|\n' > "$RES"

# ── 1. pairwise: scope × install × existing state × OS (12 rows cover every pair) ──
pairwise() {  # pairwise <n> <scope> <install> <state> <os>
  local n=$1 scope=$2 inst=$3 state=$4 os=$5 osv; [ "$os" = macOS ] && osv=Darwin || osv=Linux
  row "P$n" "scope=$scope install=$inst state=$state os=$os"
  box "p$n" "$state" "$inst"
  local pre; pre=$(git -C "$P" rev-parse HEAD)
  ans "$B/a.json" "$scope" "$inst"
  local bs=(); [ "$scope" = org ] && bs=(--bootstrap)
  eng "$B/run" FAKE_OS=$osv FAKE_UID=1000 FAKE_USER=tester -- --scope "$scope" --install "$inst" --answers "$B/a.json" ${bs[@]+"${bs[@]}"}
  if [ "$scope" != base ] && [ "$inst" = global ]; then
    check "refused (exit 2) with the per-project message" "[ $(rc "$B/run") = 2 ] && has '$B/run.out' 'the vault is per project; run \`/setup\` inside the project'"
    check "...and nothing new was written in the project" "clean && [ \"\$(git -C \"\$P\" rev-parse HEAD)\" = $pre ] && { [ $state = vault ] || [ $state = org ] || [ ! -e \"\$P/vault\" ]; }"
    done_row REFUSED "\`setup.mjs --scope $scope --install global\` → exit 2, \"the vault is per project; run \`/setup\` inside the project\""
    return
  fi
  check "exit 0" "[ $(rc "$B/run") = 0 ]" || tail -5 "$B/run.out"
  local cfg; [ "$inst" = global ] && cfg=$HOME/.claude || cfg=$P/.claude
  check "base config in $inst scope (skills, hooks, settings.json with the router hook)" \
    "[ -f '$cfg/skills/agent-org/SKILL.md' ] && [ -x '$cfg/hooks/skill-router.sh' ] && grep -q skill-router.sh '$cfg/settings.json'"
  check "setup.json remembers install=$inst" "python3 -c 'import json,sys;sys.exit(json.load(open(sys.argv[1]))[\"install\"]!=sys.argv[2])' '$HOME/.claude/setup.json' $inst"
  if [ "$inst" = project ] && { [ "$scope" != base ] || [ "$state" = vault ] || [ "$state" = org ]; }; then
    check "vault repo: the base personas stay out of .claude/agents (the role cards are its agents)" "[ ! -e '$P/.claude/agents/code-reviewer.md' ] && [ -f '$P/.claude/agents/builder.md' ]"
  fi
  if [ "$state" = other ]; then
    check "the other config's hook, permission and agent are kept" \
      "grep -q other-config '$P/.claude/settings.json' && grep -q 'Bash(npm test)' '$P/.claude/settings.json' && [ -f '$P/.claude/agents/other.md' ]"
  fi
  if [ "$scope" != base ]; then
    check "vault installed in the project, no placeholder left" "[ -f '$P/vault/AGENTS.md' ] && ! grep -rlE '\{\{[A-Z][A-Z0-9_]*\}\}' --exclude-dir=.git --exclude-dir=skills '$P' >/dev/null"
  fi
  if [ "$scope" = org ]; then
    check "org.json written for this repo, bootstrap reached 'host ready'" \
      "python3 -c 'import json,sys;sys.exit(json.load(open(sys.argv[1]))[\"repo\"]!=sys.argv[2])' '$ORGR/org.json' '$P' && has '$B/run.out' 'host ready (local'"
  fi
  local ev="files in place"
  if [ "$scope" = vault ] && [ "$state" = fresh ]; then   # a vault-only install (with its [setup:…] tokens) is a working org board
    commit_all; check "vault-only install: org-board.sh exits 0 after the setup commit" "(cd \"\$P\" && bash scripts/gates/org-board.sh >'$B/board.out' 2>&1)" || tail -5 "$B/board.out"
    ev="org-board.sh exit 0 after the setup commit"
  fi
  if [ "$scope" = org ] && [ "$state" = vault ]; then
    check "vault → org upgrade: every [setup:…] token filled from the interview" \
      "! grep -rq '\[setup:' '$P/vault' '$P/.claude/rules' && grep -q 'claude, read-only' '$P/vault/Design/lanes-and-supervisors.md' && grep -q 'Ship weekly' '$P/.claude/rules/owner-rulings.md'"
    check "...the mission file is the vault's (no second mission)" "[ \$(ls '$P/vault/Missions/' | grep -vc README) = 1 ]"
    ev="vault upgraded in place: no [setup:…] token left"
  elif [ "$state" = vault ] || [ "$state" = org ]; then
    check "existing $state + re-run: zero files changed (git status clean)" "clean"; ev="git status clean"
  fi
  done_row PASS "\`setup.mjs --scope $scope --install $inst\` → exit 0; $ev"
}
pairwise 1  base  global  fresh macOS
pairwise 2  base  project other Linux
pairwise 3  base  global  vault Linux
pairwise 4  base  project org   macOS
pairwise 5  vault project fresh Linux
pairwise 6  vault global  other macOS
pairwise 7  vault project vault macOS
pairwise 8  vault global  org   Linux
pairwise 9  org   global  fresh Linux
pairwise 10 org   project other macOS
pairwise 11 org   project vault Linux
pairwise 12 org   project org   macOS

# ── 2. scope=org: runtime × supervisor × run ──
orgrow() {  # orgrow <n> <local|vps> <claude|codex> <first|same|changed>
  local n=$1 rt=$2 sup=$3 run=$4
  row "O$n" "scope=org runtime=$rt supervisor=$sup run=$run"
  box "o$n" fresh project
  local envs runtime wuser
  if [ "$rt" = local ]; then envs=(FAKE_OS=Darwin FAKE_UID=501 FAKE_USER=tester); runtime=local; wuser=""
  else envs=(FAKE_OS=Linux FAKE_UID=1000 FAKE_USER=agent); runtime=remote; wuser=agent; fi
  ans "$B/a.json" org project "$runtime" "$wuser" "$sup"
  if [ "$rt" = vps ]; then   # phase 1 as root on the box, then phase 2 as the worker user (bootstrap-host.sh)
    eng "$B/root" FAKE_OS=Linux FAKE_UID=0 FAKE_USER=root -- --scope org --install project --answers "$B/a.json" --bootstrap
    check "VPS phase 1 (root): creates the worker user and its crontab, exits 0" \
      "[ $(rc "$B/root") = 0 ] && has '$B/root.out' 'phase 1 done' && [ -f '$SB/users/agent' ] && has '$SB/cron.agent' '# agent-org'"
  fi
  eng "$B/run" "${envs[@]}" -- --scope org --install project --answers "$B/a.json" --bootstrap
  check "first run: exit 0, host ready ($runtime, as ${envs[2]#FAKE_USER=})" "[ $(rc "$B/run") = 0 ] && has '$B/run.out' 'host ready ($runtime, as ${envs[2]#FAKE_USER=})'" || tail -4 "$B/run.out"
  [ "$rt" = local ] && check "local org: claude_bin is the absolute path on PATH, bootstrap prints no NOTE" \
    "python3 -c 'import json,os,sys;b=json.load(open(sys.argv[1]))[\"claude_bin\"];sys.exit(not(os.path.isabs(b) and os.access(b,os.X_OK)))' '$ORGR/org.json' && ! has '$B/run.out' 'is not absolute'"
  [ "$rt" = vps ] && check "VPS org: claude_bin stays the bare name (resolved on the VPS)" "grep -q '\"claude_bin\": \"claude\"' '$ORGR/org.json'"
  [ "$n" = 1 ] && check "defaults accepted: org.json states the backstop caps 100/40/48" \
    "python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(not(d[\"max_consults_per_day\"],d[\"max_agent_starts_per_day\"],d[\"max_agent_hours_per_day\"])==(100,40,48))' '$ORGR/org.json'"
  if [ "$n" = 1 ]; then commit_all; check "org install: org-board.sh exits 0 after the setup commit" "(cd \"\$P\" && bash scripts/gates/org-board.sh >'$B/board.out' 2>&1)" || tail -5 "$B/board.out"; fi
  [ "$sup" = codex ] && check "codex supervisor: login status probed" "has '$B/run.out' 'codex: Logged in (fake)'"
  [ "$rt" = local ] && check "local macOS: launchd agent, no crontab line" "ls '$HOME/Library/LaunchAgents/'agent-org.*.plist >/dev/null 2>&1 && [ ! -s '$SB/cron.tester' ]"
  [ "$rt" = vps ] && check "VPS: no sudo anywhere in the calls" "! grep -q '^sudo' '$LOG'"
  local ev="first run → exit 0, \"host ready ($runtime)\""
  if [ "$run" != first ]; then
    commit_all; cp "$ORGR/org.json" "$B/org.before"
    if [ "$run" = same ]; then
      eng "$B/again" "${envs[@]}" -- --scope org --install project --answers "$B/a.json" --bootstrap
      check "re-run unchanged: exit 0, git status clean, org.json byte-identical" "[ $(rc "$B/again") = 0 ] && clean && cmp -s '$B/org.before' '$ORGR/org.json'"
      ev="re-run with the same answers → exit 0, git status clean, org.json unchanged"
    else
      ans "$B/b.json" org project "$runtime" "$wuser" "$sup" trunk
      eng "$B/again" "${envs[@]}" -- --scope org --install project --answers "$B/b.json" --change
      check "changed main branch: exit 0" "[ $(rc "$B/again") = 0 ]" || tail -4 "$B/again.out"
      check "...git changes exactly settings.json and the PR-gate workflow" \
        "[ \"\$(git -C \"\$P\" status --porcelain | sort | tr '\n' ' ')\" = ' M .claude/settings.json  M .github/workflows/org-gates.yml ' ]"
      check "...which now name trunk" "grep -q '\"ORG_MAIN_BRANCH\": \"trunk\"' '$P/.claude/settings.json' && grep -q 'branches: \[trunk\]' '$P/.github/workflows/org-gates.yml'"
      check "...org.json differs only in main_branch" "python3 -c 'import json,sys;a,b=(json.load(open(f)) for f in sys.argv[1:]);sys.exit(not(b[\"main_branch\"]==\"trunk\" and {k:v for k,v in a.items() if k!=\"main_branch\"}=={k:v for k,v in b.items() if k!=\"main_branch\"}))' '$B/org.before' '$ORGR/org.json'"
      check "...and says settings.json needs Authority: owner" "has '$B/again.out' 'Authority: owner'"
      ev="main_branch main→trunk with --change → only org.json, .claude/settings.json, org-gates.yml change"
    fi
  fi
  done_row PASS "$ev"
}
n=0
for rt in local vps; do for sup in claude codex; do for run in first same changed; do
  n=$((n+1)); orgrow $n $rt $sup $run
done; done; done

# ── 3. named rows ──
row N1 "macOS + runtime remote + worker_user, on this box"
box n1 fresh project; ans "$B/a.json" org project remote agent claude
eng "$B/run" FAKE_OS=Darwin FAKE_UID=501 FAKE_USER=tester -- --scope org --install project --answers "$B/a.json" --bootstrap
check "bootstrap refuses (exit 2) with the existing message" "[ $(rc "$B/run") = 2 ] && has '$B/run.out' 'worker_user is Linux-only (useradd). On macOS set'"
check "...no launch agent, no crontab, no user" "[ ! -d '$HOME/Library/LaunchAgents' ] && [ ! -e '$SB/cron.tester' ] && [ ! -e '$SB/users/agent' ]"
done_row REFUSED "bootstrap-host.sh → exit 2, \"worker_user is Linux-only (useradd). On macOS set \\\"worker_user\\\": \\\"\\\" …\""

row N2 "Linux as root + runtime local"
box n2 fresh project; ans "$B/a.json" org project local "" claude
eng "$B/run" FAKE_OS=Linux FAKE_UID=0 FAKE_USER=root -- --scope org --install project --answers "$B/a.json" --bootstrap
check "refused (exit 2) naming the fix" "[ $(rc "$B/run") = 2 ] && has '$B/run.out' 'claude will not skip permissions as root; set a worker user or run as a normal user'"
done_row REFUSED "bootstrap-host.sh → exit 2, \"claude will not skip permissions as root; set a worker user or run as a normal user\""

row N3 "scope=vault + install=global"
box n3 fresh global; ans "$B/a.json" vault global
eng "$B/run" -- --scope vault --install global --answers "$B/a.json"
check "refused (exit 2) with the per-project message" "[ $(rc "$B/run") = 2 ] && has '$B/run.out' 'the vault is per project; run \`/setup\` inside the project'"
check "...nothing written (no vault, no ~/.claude, git status clean)" "nothing_written"
done_row REFUSED "\`--scope vault --install global\` → exit 2, \"the vault is per project; run \`/setup\` inside the project\""

row N4 "supervisor=codex with no codex binary"
box n4 fresh project; ans "$B/a.json" org project local "" codex
PATH=$(path_without codex) eng "$B/run" FAKE_OS=Darwin -- --scope org --install project --answers "$B/a.json" --bootstrap
check "bootstrap stops at the need check (exit 3), naming the install command" "[ $(rc "$B/run") = 3 ] && has '$B/run.out' 'MISSING: codex — npm i -g @openai/codex'"
done_row REFUSED "bootstrap-host.sh → exit 3, \"MISSING: codex — npm i -g @openai/codex …\""

row N5 "existing .claude/settings.json hook carrying {{PLACEHOLDER}}"
box n5 fresh project
mkdir -p "$P/.claude"; printf '{\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash {{HOOK_DIR}}/stop.sh"}]}]}\n}\n' > "$P/.claude/settings.json"
git -C "$P" add -A && git -C "$P" commit -qm "half-filled template"
ans "$B/a.json" vault project
eng "$B/run" -- --scope vault --install project --answers "$B/a.json"
check "settings.json not merged: byte-identical to the committed one" "git -C \"\$P\" diff --quiet -- .claude/settings.json"
check "...reported by name, run exits 1" "[ $(rc "$B/run") = 1 ] && has '$B/run.out' 'carries an unfilled {{HOOK_DIR}}' && has '$B/run.out' 'NOT merged'"
done_row PASS "settings.json unchanged (git diff --quiet); \"carries an unfilled {{HOOK_DIR}}; … NOT merged\", exit 1"

row N6 "existing vault + re-run"
box n6 vault project; ans "$B/a.json" vault project
eng "$B/run" -- --scope vault --install project --answers "$B/a.json"
check "exit 0 and zero files changed (git status --porcelain empty)" "[ $(rc "$B/run") = 0 ] && clean"
done_row PASS "re-run \`--scope vault\` → exit 0, \`git status --porcelain\` empty"

row N7 "changed answer: main branch renamed (vault only, no org)"
box n7 vault project; ans "$B/b.json" vault project "" "" "" trunk
eng "$B/run" -- --scope vault --install project --answers "$B/b.json"
check "without --change: refused, names the answer" "[ $(rc "$B/run") = 2 ] && has '$B/run.out' 'differ from the remembered ones: main_branch' && clean"
eng "$B/run2" -- --scope vault --install project --answers "$B/b.json" --change
check "with --change: settings env and workflow updated, nothing else" \
  "[ $(rc "$B/run2") = 0 ] && [ \"\$(git -C \"\$P\" status --porcelain | sort | tr '\n' ' ')\" = ' M .claude/settings.json  M .github/workflows/org-gates.yml ' ]"
done_row PASS "\`--change\` main→trunk → only .claude/settings.json and org-gates.yml change (org rows O3/O6/O9/O12 add org.json)"

row N8 "changed answer: install global → project"
box n8 fresh global; ans "$B/a.json" base global
eng "$B/run" -- --scope base --install global --answers "$B/a.json"
eng "$B/run2" -- --scope base --install project --answers "$B/a.json" --change
check "refused (exit 2) even with --change, with the hand-migration note" \
  "[ $(rc "$B/run2") = 2 ] && has '$B/run2.out' 'cannot be done automatically' && has '$B/run2.out' 'By hand: remove it from ~/.claude'"
check "...the project got no .claude" "[ ! -e '$P/.claude' ]"
done_row REFUSED "\`--install project\` after global → exit 2, \"…moving it to project cannot be done automatically. By hand: …\""

row N9 "base in the project first, the vault later"
box n9 fresh project; ans "$B/a.json" vault project
eng "$B/run" -- --scope base --install project --answers "$B/a.json"
check "base-only project install: the base personas are there" "[ -f '$P/.claude/agents/code-reviewer.md' ]"
eng "$B/run2" -- --scope vault --install project --answers "$B/a.json"
check "the vault takes back its unmodified copies, and says so" "[ $(rc "$B/run2") = 0 ] && [ ! -e '$P/.claude/agents/code-reviewer.md' ] && has '$B/run2.out' 'removed unmodified copies: code-reviewer.md'"
commit_all; check "...and the board is green" "(cd \"\$P\" && bash scripts/gates/org-board.sh >/dev/null 2>&1)"
done_row PASS "base then vault (project) → personas removed (\"removed unmodified copies: code-reviewer.md, …\"), org-board.sh exit 0"

# ── 4. the vault gate (hooks/vault-gate.sh), run through the settings.json command a global install registers ──
box g fresh global; ans "$B/a.json" base global; eng "$B/run" -- --scope base --install global --answers "$B/a.json"
GATE_CMD=$(jq -r '.hooks.PreToolUse[] | select(.matcher | test("Write")) | .hooks[].command | select(test("vault-gate"))' "$HOME/.claude/settings.json")
export CLAUDE_VAULT_GATE_DIR=$B/gate
GATE_HOME=$HOME   # every gate call runs under the HOME that has the gate installed: later rows switch HOME (box),
                  # and a HOME without the hook makes the command a silent no-op, so "silent" rows would pass vacuously
gate() {   # gate <dir> <session> [ENV=…] → $B/gate.rc, $B/gate.err
  local d=$1 sid=$2; shift 2
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/x"}}' "$sid" "$d" "$d" |
    (cd "$d" && env HOME="$GATE_HOME" CLAUDE_PROJECT_DIR="$d" "$@" sh -c "$GATE_CMD") > "$B/gate.out" 2> "$B/gate.err"; echo $? > "$B/gate.rc"; }
grc() { cat "$B/gate.rc"; }
row G1 "gate: git repo without a vault"
check "the global settings.json registers the gate on write tools" "[ -n \"\$GATE_CMD\" ]"
gate "$P" s1 A=1; check "first write of a session: blocked (exit 2), stderr says run /setup" "[ $(grc) = 2 ] && has '$B/gate.err' 'run \`/setup\` here'"
gate "$P" s1 A=1; check "second write, same session: allowed (exit 0, silent)" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ]"
gate "$P" s2 A=1; check "a new session is reminded once again" "[ $(grc) = 2 ]"
done_row PASS "PreToolUse via settings.json: exit 2 + \"run \`/setup\` here\" once, then exit 0 for the session"
row G2 "gate: ORG_VAULT=off"
gate "$P" s3 ORG_VAULT=off; check "silent, exit 0" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ]"
gate "$P" s3 ORG_VAULT=off; check "...logged once for the session" "[ \$(grep -c 'ORG_VAULT=off' '$B/gate/vault-gate.log') = 1 ]"
done_row PASS "exit 0, no stderr; vault-gate.log has exactly one 'ORG_VAULT=off' line after two writes"
row G3 "gate: .claude/no-vault marker"
mkdir -p "$P/.claude" && : > "$P/.claude/no-vault"
gate "$P" s4 A=1; gate "$P" s4 A=1; check "silent, exit 0, logged once" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ] && [ \$(grep -c 'no-vault' '$B/gate/vault-gate.log') = 1 ]"
rm "$P/.claude/no-vault"
done_row PASS "exit 0, no stderr; one '.claude/no-vault' log line"
row G4 "gate: headless worker in a repo without a vault"
gate "$P" s5 AGENT_NAME=w1 AGENT_ORG_HEADLESS=1; check "silent, exit 0, nothing logged" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ] && ! grep -q s5 '$B/gate/vault-gate.log'"
done_row PASS "AGENT_NAME/AGENT_ORG_HEADLESS → exit 0, no stderr, no log line"
row G5 "gate: not a git repository"
mkdir -p "$B/plain dir"; gate "$B/plain dir" s6 A=1; check "silent, exit 0" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ]"
done_row PASS "exit 0, no stderr"
check "the gate script is installed where every gate row runs" "[ -f '$GATE_HOME/.claude/hooks/vault-gate.sh' ]"
row G6 "gate: repo with a vault"
box g6 vault project; gate "$P" s7 A=1; check "silent, exit 0" "[ $(grc) = 0 ] && [ ! -s '$B/gate.err' ]"
done_row PASS "exit 0, no stderr"
row G7 "gate: inside this config repo itself"
CONF_TOP=$(git -C "$KIT" rev-parse --show-toplevel)
gate "$CONF_TOP" s8 A=1; check "the config repo ships .claude/no-vault: silent, exit 0" "[ -f '$CONF_TOP/.claude/no-vault' ] && [ $(grc) = 0 ] && [ ! -s '$B/gate.err' ]"
done_row PASS "the config repo's own .claude/no-vault → exit 0, no stderr (no nudge in its own clone)"
unset CLAUDE_VAULT_GATE_DIR

row N11 "repo path with a space, in every scope"
check "every base/vault/org row above ran in \"my proj\" and passed" "! grep -E '^\| (P|O)[0-9]+ ' '$RES' | grep -q '| FAIL |'"
done_row PASS "rows P1–P12 and O1–O12 all use \"…/my proj\" and \"…/org root\""

row N12 "budget answered: caps the owner would notice"
box n12 fresh project; ans "$B/a.json" org project
python3 - "$B/a.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); a["org"].update(max_consults_per_day=30, max_agent_starts_per_day=10, max_agent_hours_per_day=12)
json.dump(a, open(sys.argv[1], "w"))
PY
eng "$B/run" FAKE_OS=Darwin FAKE_UID=501 FAKE_USER=tester -- --scope org --install project --answers "$B/a.json"
check "exit 0, org.json carries 30/10/12" "[ $(rc "$B/run") = 0 ] && python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(not(d[\"max_consults_per_day\"],d[\"max_agent_starts_per_day\"],d[\"max_agent_hours_per_day\"])==(30,10,12))' '$ORGR/org.json'"
done_row PASS "answers with caps 30/10/12 → exit 0, org.json max_consults/starts/hours = 30/10/12"

row U1 "real Linux host: useradd, crontab -u, systemd --user + linger"
done_row UNTESTABLE "stubbed here (no Linux VM); the Ubuntu CI job runs this script, still with the fakes — needs a real VPS"
row U2 "the AskUserQuestion interview in commands/setup.md"
done_row UNTESTABLE "an interactive Claude Code session; the engine it drives is what rows P/O/N exercise"

echo
cat "$RES"
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
