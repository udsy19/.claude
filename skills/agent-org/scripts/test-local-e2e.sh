#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # fakes use literal $vars; outputs are read by eval'd check strings
# Local runtime, end to end (spec item G), on macOS or Linux, every binary that would act on the machine faked.
# /setup scope=org runtime=local → two lanes → consults (one A1-refused LAND, one gate-refused LAND)
# → snapshot via the launchd job's own command line → gc → loop restart adopts a running agent → STOP.
# Takes ~3 min (one 60 s feed poll, one 90 s agent). KEEP=1 keeps the sandbox.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
SB=$(mktemp -d "${TMPDIR:-/tmp}/local-e2e.XXXXXX"); SB=$(cd "$SB" && pwd -P)
cleanup() { pkill -f "$SB" 2>/dev/null; if [ "${KEEP:-}" = 1 ]; then echo "sandbox kept: $SB"; else rm -rf "$SB"; fi; }
trap cleanup EXIT
export HOME="$SB/home"; mkdir -p "$HOME"
P="$SB/my proj"; ORG="$SB/org root"; F="$SB/fakes"; LOG="$SB/fake.log"; mkdir -p "$F"
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
step() { echo; echo "== $*"; }

# ── fakes: nothing here can reach launchd, cron, sudo, tmux, claude or codex for real ──
fake() { printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$LOG" "$2" > "$F/$1"; chmod +x "$F/$1"; }
fake launchctl 'exit 0'; fake systemctl 'exit 1'
# crontab: a file-backed store, so the Linux cron path runs without touching the real crontab
fake crontab "c=$SB/crontab.txt; case \"\$1\" in -l) [ -f \"\$c\" ] && cat \"\$c\";; -) cat > \"\$c\";; esac"; fake sudo 'echo "sudo must not run" >&2; exit 99'
fake useradd 'exit 99'; fake codex 'exit 0'
# tmux: new-session runs the command detached in its own process group and remembers the pid per session.
cat > "$F/tmux" <<EOF
#!/bin/bash
echo "tmux \$*" >> "$LOG"; d="$SB/tmux"; mkdir -p "\$d"
case "\$1" in
  new-session) shift; while [ "\$1" != "\${1#-}" ]; do [ "\$1" = -s ] && { s=\$2; shift; }; shift; done
     perl -e 'setpgrp; exec @ARGV' bash -c "\$1" > "\$d/\$s.out" 2>&1 & echo \$! > "\$d/\$s.pid";;
  has-session) s=\$3; [ -f "\$d/\$s.pid" ] && kill -0 "\$(cat "\$d/\$s.pid")" 2>/dev/null;;
  kill-session) s=\$3; [ -f "\$d/\$s.pid" ] && kill -- -"\$(cat "\$d/\$s.pid")" 2>/dev/null; rm -f "\$d/\$s.pid"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x "$F/tmux"
# claude: the auth probe answers OK; workers act by AGENT_NAME; the prompt is stdin.
cat > "$F/claude" <<'EOF'
#!/bin/bash
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
case "$AGENT_NAME" in
  planner) echo "- planner moved a row on its own" >> vault/Plan.md; msg="planner: retune the plan";;
  sleeper) sleep 90; printf '# Sleeper\n\nslow measurement\n' > vault/Reports/sleeper.md
           msg=$(printf 'sleeper: slow measurement\n\nEVIDENCE-GROWTH: vault/Reports/sleeper.md keeps the slow measurement.');;
  *) printf '# %s\n\nmeasured\n' "$AGENT_NAME" > "vault/Reports/$AGENT_NAME.md"
     msg=$(printf '%s: measure\n\nEVIDENCE-GROWTH: vault/Reports/%s.md records the measurement.' "$AGENT_NAME" "$AGENT_NAME");;
esac
git add -A && git commit -qm "$msg"
printf '## TL;DR\n%s done\n\n## Vault check\nread vault/Index.md\n' "$AGENT_NAME" > "$report"
EOF
chmod +x "$F/claude"
# supervisor (script backend): per-lane canned consults; the lane is the parent of the consult's cwd (<lane>/int).
cat > "$SB/sup.sh" <<EOF
#!/bin/bash
lane=\$(basename "\$(dirname "\$PWD")"); c="$SB/count-\$lane"; n=\$(( \$(cat "\$c" 2>/dev/null || echo 0) + 1 )); echo \$n > "\$c"; cat > /dev/null
case "\$lane:\$n" in
  core:1) printf '=== AGENT name=planner model=opus ===\nretune\n=== END AGENT ===\n=== AGENT name=sleeper model=opus ===\nslow\n=== END AGENT ===\n';;
  core:2) printf '=== MERGE branch=lane/core/planner ===\n=== LAND branch=lane/core/planner ===\n';;
  core:*) printf '=== PLAN ===\nwaiting on sleeper\n=== END PLAN ===\n';;
  ui:1)   printf '=== AGENT name=alpha model=opus ===\nmeasure\n=== END AGENT ===\n';;
  ui:2)   printf '=== MERGE branch=lane/ui/alpha ===\n=== LAND branch=--force ===\n';;
  ui:*)   printf '=== DONE ===\n';;
esac
EOF
chmod +x "$SB/sup.sh"
export PATH="$F:$PATH"

step "project with a bare origin (path with a space)"
git init -q --bare "$SB/origin.git"; mkdir -p "$P"; git -C "$P" init -q -b main
git -C "$P" commit -q --allow-empty -m root; git -C "$P" remote add origin "$SB/origin.git"; git -C "$P" push -q origin main

step "/setup scope=base, then scope=org runtime=local (engine + bootstrap)"
node "$KIT/scripts/setup.mjs" --scope base --install global > "$SB/setup-base.out" 2>&1 || cat "$SB/setup-base.out"
python3 - "$KIT/scripts/test-vars.json" "$SB/answers.json" "$ORG" "$F/claude" "$SB/sup.sh" "$P" <<'PY'
import json, sys
v = json.load(open(sys.argv[1])); v.update(ORG_ROOT=sys.argv[3], RUNTIME="local", HOST="localhost")
json.dump({"permissions": "default", "base_install": "global", "project": "Demo", "vision": "A demo",
           "main_branch": "main", "vars": v, "org_root": sys.argv[3],
           "org": {"runtime": "local", "repo": sys.argv[6], "worker_user": "", "host": "",
                   "claude_bin": sys.argv[4], "supervisor": {"backend": "script", "command": sys.argv[5]},
                   "worker_models": {"opus": "fake-model"}, "default_worker_model": "opus",
                   "agent_timeout_s": 300, "report_overdue_s": 120, "poll_interval_s": 1, "idle_wait_s": 2}},
          open(sys.argv[2], "w"), indent=2)
PY
node "$KIT/scripts/setup.mjs" --scope org --install project --project "$P" --answers "$SB/answers.json" --bootstrap > "$SB/setup-org.out" 2>&1; rc=$?
tail -4 "$SB/setup-org.out"
check "setup org + bootstrap exit 0" "[ $rc = 0 ]"
check "no sudo / useradd was called" "! grep -qE '^(sudo|useradd) ' '$LOG'"
if [ "$(uname)" = Darwin ]; then
  PL=$(find "$HOME/Library/LaunchAgents" -name 'agent-org.*.plist' 2>/dev/null | head -1)
  check "launchd agent written and loaded (macOS: launchd, not cron)" "[ -f \"$PL\" ] && grep -q '^launchctl bootstrap' '$LOG'"
else
  check "hourly crontab line written, tagged # agent-org" "grep -q '# agent-org' '$SB/crontab.txt'"
fi

step "commit the setup (Authority: owner) and merge it to main"
git -C "$P" checkout -q -b agent-org-setup && git -C "$P" add -A
git -C "$P" commit -q -m "agent-org setup

Authority: owner
EVIDENCE-GROWTH: adds vault/Home.md and the vault contracts, .claude/rules/owner-rulings.md, scripts/gates/org-board.sh with the gates."
(cd "$P" && bash scripts/gates/org-board.sh > "$SB/board.out" 2>&1); check "org-board passes on the setup commit" "grep -q 'ORG-BOARD PASS' '$SB/board.out'"
git -C "$P" checkout -q main && git -C "$P" merge -q --ff-only agent-org-setup && git -C "$P" push -q origin main

step "two lanes"
bash "$ORG/lanes.sh" "$ORG" new core "core goal" 2 true > /dev/null && bash "$ORG/lanes.sh" "$ORG" new ui "ui goal" 1 true > /dev/null
for k in core ui; do python3 -c "import re,sys
for p in sys.argv[1:]:
    t = re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}', 'filled', open(p).read()); open(p, 'w').write(t)" "$ORG/lanes/$k/context.md" "$ORG/lanes/$k/supervisor-brief.md"; done
# the overseer's Monitor runs the feed continuously; start it before the lanes, as it would be
bash "$ORG/lane-events.sh" "$ORG" > "$SB/feed.out" 2>&1 & FEED=$!
sleep 3; bash "$ORG/lanes.sh" "$ORG" start > /dev/null
wait_for() { local _; for _ in $(seq 1 "$2"); do eval "$1" && return 0; sleep 1; done; return 1; }
L=$ORG/lanes
wait_for "grep -q 'LAND --force REFUSED\|REFUSED LAND' '$L/ui/lane.log' 2>/dev/null" 60
wait_for "grep -q 'LAND lane/core/planner REFUSED' '$L/core/lane.log' 2>/dev/null" 60
check "ui: LAND branch=--force refused (A1)" "grep -qE 'REFUSED.*--force' '$L/ui/lane.log'"
check "core: LAND of a Plan.md change without Authority refused by the gates (B3)" "grep -q 'LAND lane/core/planner REFUSED' '$L/core/lane.log' && ls '$L/core/reports/'*zz-land-refused-lane-core-planner.md >/dev/null"
check "main did not move" "[ \"\$(git -C '$P' log --oneline main | wc -l | tr -d ' ')\" = 2 ]"
wait_for "grep -q 'core: .*REFUSED' '$SB/feed.out' && grep -q 'ui: .*REFUSED' '$SB/feed.out'" 75   # the feed polls every 60 s
check "event feed prints both refusals" "grep -q 'core: .*LAND lane/core/planner REFUSED' '$SB/feed.out' && grep -q 'ui: .*REFUSED LAND branch=--force' '$SB/feed.out'"

step "loop restart adopts the running agent"
wait_for "bash '$ORG/lanes.sh' '$ORG' status | grep -q 'running: core/sleeper'" 20
check "sleeper is running and listed by status" "bash '$ORG/lanes.sh' '$ORG' status | grep -q 'running: core/sleeper'"
bash "$ORG/lanes.sh" "$ORG" restart core > /dev/null 2>&1
wait_for "grep -qi 'adopt' '$L/core/lane.log'" 20
check "restarted loop adopted sleeper" "grep -qi 'adopt.*sleeper\|sleeper.*adopt' '$L/core/lane.log'"
wait_for "grep -q 'sleeper.*finished\|finished.*sleeper\|sleeper.*rc=' '$L/core/lane.log'" 120
check "adopted sleeper finished and its work is committed" "git -C '$P' log --oneline lane/core/sleeper | grep -q 'sleeper: slow measurement'"

step "snapshot via the launchd job's own command line, then gc"
if [ "$(uname)" = Darwin ]; then   # the launchd job's own argv
  args=$(python3 -c "import plistlib,sys,shlex;print(' '.join(shlex.quote(a) for a in plistlib.load(open(sys.argv[1],'rb'))['ProgramArguments']))" "$PL")
else                               # the cron line minus its schedule (5 fields) and tag
  args=$(grep '# agent-org' "$SB/crontab.txt" | head -1 | sed -E 's/^([^ ]+ +){5}//; s/ *# agent-org.*$//')
fi
eval "$args" > "$SB/timer.out" 2>&1; rc=$?; check "the timer's own command ran (exit $rc)" "[ $rc = 0 ]"
SBR=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('state_backup_branch','backup/lane-state'))" "$ORG/org.json")
tree=$(git -C "$SB/origin.git" ls-tree -r --name-only "$SBR" 2>/dev/null)
check "snapshot branch $SBR reached origin with lane recovery state" "printf '%s' \"\$tree\" | grep -q 'lanes/core/lane.json'"
check "snapshot carries each lane's goal (supervisor-brief.md, context.md)" "printf '%s' \"\$tree\" | grep -qx 'lanes/core/supervisor-brief.md' && printf '%s' \"\$tree\" | grep -qx 'lanes/core/context.md'"
check "snapshot lacks prompts/, rounds/, owner-answers.md" "! printf '%s' \"\$tree\" | grep -qE '/(prompts|rounds)/|owner-answers.md'"
bash "$ORG/lanes.sh" "$ORG" gc > "$SB/gc.out" 2>&1; rc=$?; check "gc ran (exit $rc)" "[ $rc = 0 ]"

step "STOP"
bash "$ORG/lanes.sh" "$ORG" stop core > /dev/null; bash "$ORG/lanes.sh" "$ORG" stop ui > /dev/null
wait_for "! pgrep -f 'supervise.py $L/core' > /dev/null && ! pgrep -f 'supervise.py $L/ui' > /dev/null" 30
check "both lane loops exited after STOP" "! pgrep -f 'supervise.py $ORG' > /dev/null"
kill "$FEED" 2>/dev/null; pkill -f "$ORG/git-sync.sh" 2>/dev/null   # the feed and git-sync are org-wide, not per lane: STOP leaves them
sleep 1; check "no stray processes (lane loops, agents, feed, git-sync)" "! pgrep -f '$SB' > /dev/null"

echo; echo "fake calls:"; sed 's/^/    /' "$LOG" | sort | uniq -c | sort -rn | head -12
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
