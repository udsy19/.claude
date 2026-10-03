#!/usr/bin/env bash
# Offline end-to-end test of the lane loop (supervise.py) and its tooling (lanes.sh gc, lane-metrics.py,
# lane-events.sh's event pattern). No network, no real claude or codex: a throw-away org in /tmp, a canned
# supervisor (org.json "backend": "script", TEST-ONLY) and a fake worker binary (org.json "claude_bin").
#   bash scripts/test-supervise.sh          (KEEP=1 keeps the sandbox for inspection)
# Exercises: dispatch → finish → MERGE + LAND (hubs regenerated) → REPORT OVERDUE → KILL → NO ACTIONABLE BLOCK
# → DONE; rulings/owner-answers trimming; report digests; code view; image freshness; hub-only merge conflict;
# gc; lane-metrics (dated and legacy undated lines).
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
SB=$(mktemp -d /tmp/supervise-test.XXXXXX)
ORG=$SB/org; REPO=$SB/repo; L=$ORG/lanes/t
PASS=0; FAIL=0
cleanup() {
  pkill -f "sleep 611" 2>/dev/null; pkill -f "cd $L/wt/beta && sleep" 2>/dev/null
  [ "${KEEP:-}" = 1 ] && echo "sandbox kept: $SB" || rm -rf "$SB"
}
trap cleanup EXIT
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
# A deadline for the harness itself without GNU timeout (stock macOS lacks it): perl's alarm, then exec.
tmo() { perl -e 'alarm shift; exec @ARGV or die "exec $ARGV[0]: $!"' "$@"; }
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

echo "== sandbox $SB"
# ── the project repo: the agent-org repo layer installed by init-repo.mjs (vault, gates), an origin to push to ──
git init -q --bare "$SB/origin.git"
git init -q -b main "$REPO" && cd "$REPO" || exit 2
git commit -q --allow-empty -m root
cat > "$SB/vars.json" <<'JSON'
{"PROJECT": "Sandbox", "MAIN_BRANCH": "main", "MISSION": "first-mission", "MISSION_TITLE": "First mission",
 "MISSION_GOAL": "Ship the sandbox", "VISION_ONE_LINER": "A sandbox", "USERS": "testers", "ACCEPTANCE_BAR": "works",
 "OWNER_WORDS": "make it work", "NOT_WORKED": "nothing yet", "NEXT_MOVE": "start", "FIRST_TRACK": "core",
 "FIRST_TRACK_ITEM": "scaffold", "SOURCE_AREAS": "| `src/` | code | src/index.js |", "SUPERVISOR_DESC": "canned",
 "WORKER_DESC": "fake", "RUNTIME": "local", "HOST": "localhost", "ORG_ROOT": "/tmp/org", "STATE_BRANCH": "backup/lane-state",
 "LANE_TABLE": "| t | test | lane/t/* | lane/t/* | 2 | yes |", "EXTRA_RULINGS": "- (none yet)"}
JSON
node "$KIT/scripts/init-repo.mjs" --repo "$REPO" --vars "$SB/vars.json" > "$SB/init-repo.out" 2>&1 \
  || { echo "init-repo failed in the sandbox:"; tail -5 "$SB/init-repo.out"; exit 2; }
printf 'node_modules/\n' >> .gitignore; mkdir -p node_modules/dep && echo shared > node_modules/dep/index.js
mkdir -p .claude/rules && printf '# Owner rulings\n\n- RULING-PROJECT-42: the standing law of the project\n' > .claude/rules/owner-rulings.md
printf '# First report\n\nMeasured something.\n' > vault/Reports/first.md
node scripts/vault-hubs.mjs >/dev/null || { echo "vault-hubs failed in the sandbox"; exit 2; }
git add -A && git commit -q -F - <<'MSG' && git remote add origin "$SB/origin.git" && git push -q origin main
agent-org set-up for the sandbox

Authority: owner
EVIDENCE-GROWTH: vault/Home.md, scripts/gates/org-board.sh and .claude/rules/owner-rulings.md arrive with the
repo layer so that the loop's landing gates have a real project to grade in this sandbox.
MSG

# ── fakes ──
cat > "$SB/fake-claude.sh" <<'EOF'
#!/usr/bin/env bash
# Fake worker: commits work, saves an image in $RENDERS_DIR, writes a long report with a TL;DR.
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
raw=$(mktemp); cat > "$raw"; prompt=$(cat "$raw")   # the prompt is stdin, never an argument
if [ "$ORG_ROLE" = supervisor ]; then   # backend "claude": record how it was called, then end the lane
  printf '%s\n' "$*" > ../claude-sup.args; mv "$raw" ../claude-sup.stdin
  printf '=== DONE ===\n'; exit 0
fi
printf '%s\n' "$*" > "$LANE_ROOT/args-$AGENT_NAME.txt"
mv "$raw" "$LANE_ROOT/stdin-$AGENT_NAME.txt"
report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
case "$AGENT_NAME" in
  slowpoke|hang) sleep 611; exit 0;;     # never reports: overdue warning, then KILL / its deadline
  sleeper) sleep 6;;                     # outlives a loop restart
  alpha) sleep 2;;
  beta) sleep 8;;
esac
echo "lane=$ORG_LANE headless=$AGENT_ORG_HEADLESS role=$ORG_ROLE" > "$LANE_ROOT/env-$AGENT_NAME.seen"
msg="$AGENT_NAME work"
case "$AGENT_NAME" in
  planner)   # changes the plan, claims no authority, and neuters the gate on its branch: still refused
    echo "- planner moved a row on its own" >> vault/Plan.md; msg="planner: retune the plan"
    printf 'process.exit(0)\n' > scripts/gates/plan-ownership.mjs;;
  clean)     # a justified addition: lands
    printf '# Clean note\n\nMeasured cleanly.\n' > vault/Reports/clean-note.md
    msg=$(printf 'clean: record the measurement\n\nEVIDENCE-GROWTH: vault/Reports/clean-note.md holds the measurement the lane needs, recorded once so nobody measures it again.');;
  *) echo "$AGENT_NAME" > "work-$AGENT_NAME.txt"
     if [ "$AGENT_NAME" = alpha ]; then
       printf '# Alpha finding\n\nAlpha measured a thing.\n' > vault/Reports/alpha-finding.md
       msg=$(printf 'alpha work\n\nEVIDENCE-GROWTH: vault/Reports/alpha-finding.md and work-alpha.txt record what alpha measured, which the lane needs to judge the next step.')
     fi;;
esac
git add -A && git commit -qm "$msg"
printf 'PNG-%s' "$AGENT_NAME" > "$RENDERS_DIR/$AGENT_NAME.png"
{ printf '## TL;DR\nTLDR-%s: done, evidence in renders.\n\n## Vault check\nread vault/Index.md\n\n' "$AGENT_NAME"
  python3 -c "print('filler line\n' * 350, end='')"; echo "MIDDLE-SECRET-$AGENT_NAME"
  python3 -c "print('filler line\n' * 350, end='')"; printf '\n## Next\nNEXT-STEP-%s\n' "$AGENT_NAME"; } > "$report"
EOF
cat > "$SB/fake-sup.sh" <<EOF
#!/usr/bin/env bash
# Canned supervisor (TEST-ONLY backend "script"): the prompt arrives on stdin and is kept for assertions.
n=\$(( \$(cat $SB/count 2>/dev/null || echo 0) + 1 )); echo \$n > $SB/count
mkdir -p $SB/seen; cat > $SB/seen/\$n.txt
case \$n in
  1) printf '=== PLAN ===\nplan v1\n=== END PLAN ===\n\n=== AGENT name=alpha model=opus ===\ndo alpha\n=== END AGENT ===\n\n=== AGENT name=slowpoke model=opus ===\nhang\n=== END AGENT ===\n';;
  2) printf '=== MERGE branch=lane/t/alpha ===\n=== LAND branch=lane/t/alpha ===\n=== LEARN ===\nalpha merged\n=== END LEARN ===\n\n=== AGENT name=beta model=opus ===\ndo beta\n=== END AGENT ===\n';;
  3) printf 'slowpoke is overdue.\n=== KILL name=slowpoke ===\n=== KILL name=../x ===\n=== AGENT name=../../escape model=opus ===\nx\n=== END AGENT ===\n=== AGENT name=okname model=opus base=--force ===\nx\n=== END AGENT ===\n=== MERGE branch=--force ===\n=== LAND branch=main@{1} ===\n';;
  4) printf 'I think we should wait and see what happens next.\n';;
  *) printf '=== DONE ===\n';;
esac
EOF
chmod +x "$SB"/fake-*.sh

# ── the org and one lane ──
mkdir -p "$ORG"
cp "$KIT/scripts/supervise.py" "$KIT/scripts/lane-metrics.py" "$ORG/"
cat > "$ORG/org.json" <<EOF
{ "project": "sandbox", "repo": "$REPO", "main_branch": "main", "worker_user": "",
  "claude_bin": "$SB/fake-claude.sh",
  "supervisor": { "backend": "script", "command": "$SB/fake-sup.sh" },
  "worker_models": { "opus": "fake-model" }, "default_worker_model": "opus",
  "agent_timeout_s": 300, "report_overdue_s": 4, "poll_interval_s": 1, "idle_wait_s": 2 }
EOF
bash "$KIT/scripts/lanes.sh" "$ORG" new t "sandbox goal" 2 true >/dev/null || { echo "lanes.sh new failed"; exit 2; }
check "lanes.sh new creates rulings.md and renders/owner" "[ -f $L/rulings.md ] && [ -d $L/renders/owner ]"
fill() { python3 -c "import re,sys
for p in sys.argv[1:]:
    t = re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}', 'filled', open(p).read()); open(p, 'w').write(t)" "$@"; }
fill "$L/context.md" "$L/supervisor-brief.md"     # the overseer fills these; supervise.py refuses UNFILLED ones
echo "- RULING-KEEP-7: the owner's current law" >> "$L/rulings.md"
for i in $(seq -w 1 15); do printf '\n## 2026-10-%s · question A%s\nanswer-A%s\n' "$i" "$i" "$i" >> "$L/owner-answers.md"; done
printf 'PNG-owner' > "$L/renders/owner/ref-owner.png"

# ── run the loop ──
echo "== supervise.py (canned consults 1-5)"
( cd "$L" && ORG_ROOT=$ORG tmo 180 python3 "$ORG/supervise.py" "$L" 1 > "$SB/supervise.out" 2>&1 ); rc=$?
check "loop exits cleanly on DONE (rc $rc)" "[ $rc = 0 ] && has $L/lane.log 'supervisor declared DONE'"
check "five consults ran" "[ \$(grep -c '=== CONSULT' $L/lane.log) = 5 ]"
check "log lines carry the date" "grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} === CONSULT 1' $L/lane.log"
S=$SB/seen
# prompt budget
check "rulings.md injected in full" "has $S/1.txt RULING-KEEP-7"
check "D7: project .claude/rules/owner-rulings.md inlined into the consult" "has $S/1.txt \"## Owner rulings: the project's standing rules\" && has $S/1.txt RULING-PROJECT-42"
check "only the newest 10 raw owner answers" "has $S/1.txt answer-A06 && has $S/1.txt answer-A15 && ! has $S/1.txt answer-A05"
check "report digest: TL;DR + tail" "has $S/2.txt TLDR-alpha && has $S/2.txt NEXT-STEP-alpha"
check "report digest: middle omitted" "! has $S/2.txt MIDDLE-SECRET-alpha && has $S/2.txt 'chars omitted'"
# code view
check "code view: lane log and diff vs main" "has $S/2.txt 'git log --oneline -15 lane/t/integration' && has $S/2.txt 'git diff --stat main...lane/t/integration'"
check "code view: finished agent's branch diff" "has $S/2.txt 'git diff --stat lane/t/integration...lane/t/alpha' && has $S/2.txt work-alpha.txt"
# images
check "owner image always shown" "has $S/1.txt ref-owner.png && has $S/3.txt ref-owner.png"
check "fresh worker image shown" "has $S/2.txt renders/alpha/alpha.png && has $S/3.txt renders/beta/beta.png"
check "stale worker image dropped" "! has $S/3.txt renders/alpha/alpha.png"
check "worker images land in renders/<agent>/" "[ -f $L/renders/alpha/alpha.png ] && [ ! -e $L/renders/latest ]"
# merge, land, hubs
check "MERGE ok + hubs regenerated on the lane branch" "has $L/lane.log 'MERGE lane/t/alpha ok' && git -C $REPO log --format=%s lane/t/integration | grep -q 'vault: regenerate hubs after merge'"
check "merged hub lists the new note" "grep -q alpha-finding $L/int/vault/Reports/README.md"
check "LAND ok + hubs regenerated on main" "has $L/lane.log 'LAND lane/t/alpha ok' && git -C $REPO log --format=%s main | grep -q 'vault: regenerate hubs after merge' && git -C $REPO show main:vault/Reports/README.md | grep -q alpha-finding"
check "hub commit carries Authority: supervisor" "git -C $REPO log -1 --format=%B main | grep -q 'Authority: supervisor'"
check "main checkout left clean" "[ -z \"\$(git -C $REPO status --porcelain)\" ]"
# overdue, kill, no-action
check "REPORT OVERDUE logged once" "[ \$(grep -c 'REPORT OVERDUE slowpoke' $L/lane.log) = 1 ]"
check "overdue flagged in the next prompt" "has $S/3.txt 'slowpoke  (REPORT OVERDUE'"
check "KILL terminated the agent" "has $L/lane.log 'KILLED slowpoke' && has $L/lane.log 'agent slowpoke finished' && ! pgrep -f 'sleep 611' >/dev/null"
check "NO ACTIONABLE BLOCK logged" "has $L/lane.log 'NO ACTIONABLE BLOCK in consult 4'"
check "...and quoted into the next prompt" "has $S/5.txt 'produced no actionable block (first 500 chars:' && has $S/5.txt 'I think we should wait'"
check "LEARN still journaled" "has $L/lane-memory.md 'alpha merged'"
# A1: supervisor output is untrusted input
check "A1: hostile names/refs refused and logged" "has $L/lane.log 'REFUSED AGENT name=../../escape' && has $L/lane.log 'REFUSED AGENT name=okname base=--force' && has $L/lane.log 'REFUSED MERGE branch=--force' && has $L/lane.log 'REFUSED LAND branch=main@{1}' && has $L/lane.log 'REFUSED KILL name=../x'"
check "A1: nothing written outside the lane, no branch made" "[ ! -e $ORG/escape ] && [ ! -e $ORG/lanes/escape ] && [ ! -e $L/wt/okname ] && ! git -C $REPO rev-parse -q --verify refs/heads/lane/t/okname >/dev/null && ! ls $L/prompts | grep -q -e escape -e okname"
check "A1: refusals quoted back to the supervisor" "has $S/4.txt 'Your block \`AGENT name=../../escape\` was refused'"

# ── a conflict ONLY in generated hubs is resolved by regeneration ──
echo "== hub-only merge conflict"
for h in h1 h2; do
  git -C "$REPO" worktree add -q -b "lane/t/$h" "$SB/$h" lane/t/integration
  ( cd "$SB/$h" && printf '# Note %s\n\nText.\n' $h > vault/Reports/$h.md && node scripts/vault-hubs.mjs >/dev/null && git add -A && git commit -qm "$h with its own hubs" )
done
out=$(cd "$L" && ORG_ROOT=$ORG python3 -c "
import sys; sys.argv = ['supervise.py', '$L']; sys.path.insert(0, '$ORG'); import supervise as s
print(s.merge(s.INT, 'lane/t/h1', 'merge h1', 'test h1').returncode, s.merge(s.INT, 'lane/t/h2', 'merge h2', 'test h2').returncode)" | tail -1)
check "both merges succeed (rc: $out)" "[ \"$out\" = '0 0' ]"
check "regenerated hub lists both notes" "grep -q 'Reports/h1' $L/int/vault/Reports/README.md && grep -q 'Reports/h2' $L/int/vault/Reports/README.md && ! grep -q '<<<<<<<' $L/int/vault/Reports/README.md"
git -C "$REPO" worktree remove --force "$SB/h1"; git -C "$REPO" worktree remove --force "$SB/h2"

# ── back-compat and digest units ──
echo "== owner-answers fallback, short reports"
mv "$L/rulings.md" "$SB/rulings.bak"
out=$(cd "$L" && ORG_ROOT=$ORG python3 -c "
import sys; sys.argv = ['supervise.py', '$L']; sys.path.insert(0, '$ORG'); import supervise as s
b = s.owner_block(); open('$SB/short.md', 'w').write('## TL;DR\nshort\n'); print('A01' in b and 'A15' in b, s.report_digest('$SB/short.md') == '## TL;DR\nshort\n')")
check "no rulings.md: whole owner-answers (back-compat); short report verbatim" "[ \"$out\" = 'True True' ]"
mv "$SB/rulings.bak" "$L/rulings.md"

# ── gc ──
echo "== lanes.sh gc"
git -C "$L/int" merge -q --no-edit lane/t/beta
mkdir -p "$L/target/alpha" "$L/target/beta"; head -c 200000 /dev/zero > "$L/target/alpha/blob"
printf old > "$L/renders/beta/old.png"; touch -t 202601010000 "$L/renders/beta/old.png"
printf old > "$L/renders/owner/old-owner.png"; touch -t 202601010000 "$L/renders/owner/old-owner.png"
bash -c "cd $L/wt/beta && sleep 30" & DUMMY=$!     # beta looks "running" (same command shape as a live agent)
sleep 0.5
gcout=$(bash "$KIT/scripts/lanes.sh" "$ORG" gc t 2>&1); echo "$gcout" | sed 's/^/    /'
kill $DUMMY 2>/dev/null; wait $DUMMY 2>/dev/null; pkill -f "cd $L/wt/beta && sleep" 2>/dev/null
check "merged, finished worktrees removed (+ build dir)" "[ ! -d $L/wt/alpha ] && [ ! -d $L/wt/slowpoke ] && [ ! -d $L/target/alpha ]"
check "running agent's worktree kept" "[ -d $L/wt/beta ] && echo \"\$gcout\" | grep -q 'keep wt/beta'"
check "old renders pruned, owner renders kept" "[ ! -e $L/renders/beta/old.png ] && [ -e $L/renders/owner/old-owner.png ] && [ -e $L/renders/beta/beta.png ]"
check "gc reports bytes freed" "echo \"\$gcout\" | grep -qE 'gc t: removed 2 worktree\(s\), 1 render\(s\).*freed [0-9]+ KB'"

# ── lane-events pattern ──
EVENTS=$(grep '^EVENTS=' "$KIT/scripts/lane-events.sh" | sed 's/^EVENTS=//; s/^"//; s/"$//')
feed=$(grep -E "$EVENTS" "$L/lane.log")
check "A1: event feed shows supervisor-block refusals" "echo \"\$feed\" | grep -q 'REFUSED AGENT name=../../escape'"
check "event feed shows KILLED / NO ACTIONABLE BLOCK / REPORT OVERDUE" \
  "echo \"\$feed\" | grep -q 'KILLED slowpoke' && echo \"\$feed\" | grep -q 'NO ACTIONABLE BLOCK' && echo \"\$feed\" | grep -q 'REPORT OVERDUE slowpoke'"

# ── metrics ──
echo "== lane-metrics"
mkdir -p "$ORG/lanes/old"
printf '23:50 === CONSULT 1: x\n23:55 agent x (opus) start on y\n00:10 agent x finished rc=124 report=MISSING\n2026-10-02 00:20 MERGE lane/old/x ok\n' > "$ORG/lanes/old/lane.log"
python3 "$ORG/lane-metrics.py" "$ORG" --days 0 | sed 's/^/    /'
json=$(python3 "$ORG/lane-metrics.py" "$ORG" --days 0 --json)
m() { printf '%s' "$json" | python3 -c "import json,sys; d=json.load(sys.stdin)[sys.argv[1]]; print(sum((r[sys.argv[2]] or 0) for r in d.values()))" "$1" "$2"; }
check "metrics: consults/dispatches/finished" "[ $(m t consults) = 5 ] && [ $(m t dispatches) = 3 ] && [ $(m t finished) = 3 ]"
check "metrics: merges/lands/kills/no-action/missing" "[ $(m t merges_ok) = 1 ] && [ $(m t lands) = 1 ] && [ $(m t kills) = 1 ] && [ $(m t no_action) = 1 ] && [ $(m t report_missing) = 1 ]"
check "metrics: legacy HH:MM lines dated across midnight" \
  "printf '%s' \"\$json\" | python3 -c \"import json,sys; o=json.load(sys.stdin)['old']; assert o['2026-10-01']['dispatches']==1 and o['2026-10-02']['rc_timeouts']==1 and o['2026-10-02']['med_finish_min']==15 and o['2026-10-02']['med_merge_min']==25\""

# ── lane-events.sh: offsets without bash-4 arrays (macOS /bin/bash is 3.2) ──
echo "== lane-events.sh under /bin/bash ($(/bin/bash -c 'echo $BASH_VERSION'))"
mkdir -p "$ORG/logs"; printf '%s 0\n' "$L/lane.log" > "$ORG/logs/lane-events.state"
evout=$(tmo 6 /bin/bash "$KIT/scripts/lane-events.sh" "$ORG" 2>&1)
check "feed replays from the saved offset" "echo \"\$evout\" | grep -q 't: .*KILLED slowpoke' && ! echo \"\$evout\" | grep -q 'invalid option'"
check "offset saved as the file's line count" "grep -qF \"$L/lane.log \$(wc -l < $L/lane.log | tr -d ' ')\" $ORG/logs/lane-events.state"

# ── lanes.sh: refusal, literal goals, refill, STOP, and supervise.py's UNFILLED refusal ──
echo "== lanes.sh new / start guards"
ORG2=$SB/org2; mkdir -p "$ORG2/fakebin"; cp "$ORG/org.json" "$ORG/supervise.py" "$ORG2/"
git -C "$REPO" branch noagents "$(git -C "$REPO" commit-tree "$(git -C "$REPO" hash-object -t tree /dev/null)" -m empty)"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['main_branch']='noagents'; json.dump(d,open(sys.argv[2],'w'))" "$ORG/org.json" "$SB/org-noagents.json"
mkdir -p "$SB/orgr" && cp "$SB/org-noagents.json" "$SB/orgr/org.json"
rout=$(bash "$KIT/scripts/lanes.sh" "$SB/orgr" new x "goal" 2>&1); rrc=$?
check "new refuses when main has no vault/AGENTS.md (rc $rrc)" "[ $rrc = 2 ] && echo \"\$rout\" | grep -q 'merge the agent-org set-up commit' && [ ! -d $SB/orgr/lanes/x ]"
G='Fast & simple | a/b \1'
bash "$KIT/scripts/lanes.sh" "$ORG2" new g "$G" 1 false >/dev/null 2>&1
check "a goal with & | / \\ lands literally" "grep -qF -- 'Fast & simple | a/b \1' $ORG2/lanes/g/supervisor-brief.md"
: > "$ORG2/lanes/g/context.md"; echo "- MARK-KEEP" >> "$ORG2/lanes/g/rulings.md"
bash "$KIT/scripts/lanes.sh" "$ORG2" new g "$G" 1 false >/dev/null 2>&1
check "re-run refills an empty file, keeps a filled one" "[ -s $ORG2/lanes/g/context.md ] && has $ORG2/lanes/g/rulings.md MARK-KEEP"
urc=0; (cd "$ORG2/lanes/g" && ORG_ROOT=$ORG2 tmo 30 python3 "$ORG2/supervise.py" "$ORG2/lanes/g" 1 >/dev/null 2>&1) || urc=$?
check "supervise.py refuses an UNFILLED lane (rc $urc)" "[ $urc = 2 ] && grep -q 'UNFILLED context.md: .*{{VISION_PARAGRAPH}}' $ORG2/lanes/g/lane.log && ! grep -q 'CONSULT' $ORG2/lanes/g/lane.log"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['worker_user']='agent-org-nobody'; json.dump(d,open(sys.argv[1],'w'))" "$ORG2/org.json"
wrc=0; (cd "$ORG2/lanes/g" && ORG_ROOT=$ORG2 tmo 30 python3 "$ORG2/supervise.py" "$ORG2/lanes/g" 1 >/dev/null 2>&1) || wrc=$?
check "B1: a loop not running as worker_user refuses (no sudo) (rc $wrc)" "[ $wrc = 2 ] && grep -q \"REFUSED to start: this lane runs as worker_user 'agent-org-nobody'\" $ORG2/lanes/g/lane.log && ! grep -q CONSULT $ORG2/lanes/g/lane.log"
check "B1: no sudo/chown/as_worker left in the loop or the feed" "! grep -nE 'sudo|chown|as_worker' $KIT/scripts/supervise.py $KIT/scripts/lane-events.sh"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['worker_user']=''; json.dump(d,open(sys.argv[1],'w'))" "$ORG2/org.json"
printf '#!/usr/bin/env bash\necho "$*" >> %q\n[ "$1" = has-session ] && exit 1; exit 0\n' "$SB/tmux.args" > "$ORG2/fakebin/tmux"; chmod +x "$ORG2/fakebin/tmux"
touch "$ORG2/lanes/g/STOP"
PATH="$ORG2/fakebin:$PATH" bash "$KIT/scripts/lanes.sh" "$ORG2" start g >/dev/null 2>&1
check "start clears STOP and launches the loop" "[ ! -e $ORG2/lanes/g/STOP ] && grep -q 'new-session -d -s lane-g' $SB/tmux.args"

# ── a repo and an org whose paths contain a space ──
echo "== paths with a space"
SP="$SB/sp ace"; mkdir -p "$SP"
git init -q --bare "$SP/origin.git"; git init -q -b main "$SP/repo"
( cd "$SP/repo" && mkdir -p vault/Reports && printf '# Agents\n' > vault/AGENTS.md && git add -A && git commit -qm init \
  && git remote add origin "$SP/origin.git" && git push -q origin main )
cat > "$SP/sup.sh" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$SP/count" 2>/dev/null || echo 0) + 1 )); echo \$n > "$SP/count"; cat > "$SP/seen-\$n.txt"
echo "role=\$ORG_ROLE headless=\$AGENT_ORG_HEADLESS" > "$SP/sup.env"
case \$n in
  1) printf '=== AGENT name=alpha model=opus ===\ndo alpha\n=== END AGENT ===\n';;
  2) printf '=== MERGE branch=lane/s/alpha ===\n';;
  *) printf '=== DONE ===\n';;
esac
EOF
chmod +x "$SP/sup.sh"; mkdir -p "$SP/org"; cp "$ORG/supervise.py" "$SP/org/"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['repo']=sys.argv[2]; d['supervisor']['command']=sys.argv[3]; json.dump(d,open(sys.argv[4],'w'))" \
  "$ORG/org.json" "$SP/repo" "$SP/sup.sh" "$SP/org/org.json"
bash "$KIT/scripts/lanes.sh" "$SP/org" new s "space goal" 1 false >/dev/null 2>&1
fill "$SP/org/lanes/s/context.md" "$SP/org/lanes/s/supervisor-brief.md"
src=0; (cd "$SP/org/lanes/s" && ORG_ROOT="$SP/org" tmo 120 python3 "$SP/org/supervise.py" "$SP/org/lanes/s" 1 >/dev/null 2>&1) || src=$?
SL="$SP/org/lanes/s/lane.log"
check "space: agent ran and reported (rc $src)" "[ $src = 0 ] && grep -q 'agent alpha finished rc=0 report=present' \"$SL\""
check "space: MERGE ok and the work is on the lane branch" "grep -q 'MERGE lane/s/alpha ok' \"$SL\" && git -C \"$SP/repo\" show lane/s/integration:work-alpha.txt >/dev/null 2>&1"
check "worker env: ORG_LANE, AGENT_ORG_HEADLESS, no ORG_ROLE" "grep -qx 'lane=s headless=1 role=' \"$SP/org/lanes/s/env-alpha.seen\""
check "supervisor env: ORG_ROLE=supervisor, AGENT_ORG_HEADLESS" "grep -qx 'role=supervisor headless=1' \"$SP/sup.env\""
check "D7: no owner-rulings.md in the project: no heading, no error" "grep -q '^# CONSULT 1' \"$SP/seen-1.txt\" && ! grep -q \"project's standing rules\" \"$SP/seen-1.txt\""

# ── org.example.json documents every key the host scripts read ──
check "org.example.json: runtime remote, bin_dir, build_queue.real, state_backup.include, push_main false" \
  "python3 -c \"import json,sys; d=json.load(open('$KIT/scripts/org.example.json')); assert d['runtime'] in ('local','remote') and d['bin_dir'] and d['build_queue']['real']=={} and d['state_backup']['include']==[] and d['sync']['push_main'] is False\""

# ── B8: no GNU timeout; agents survive a loop restart and are adopted; a deadline kills the process group ──
echo "== agent lifetime: restart adoption and deadlines"
check "B8: supervise.py and the feed do not run GNU timeout" "! grep -nE '\"timeout\"|timeout [0-9]' $KIT/scripts/supervise.py $KIT/scripts/lane-events.sh"
newlane() {   # newlane <org dir> <lane> <agent_timeout_s> <canned outputs...>: an org + filled lane with a canned supervisor
  local o=$1 ln=$2 t=$3; shift 3; mkdir -p "$o"; cp "$ORG/supervise.py" "$o/"
  { echo '#!/usr/bin/env bash'; echo "n=\$(( \$(cat '$o/count' 2>/dev/null || echo 0) + 1 )); echo \$n > '$o/count'; cat > '$o/seen-'\$n.txt"
    echo 'case $n in'; i=1; for c in "$@"; do printf "  %s) printf '%%b' %q;;\n" $i "$c"; i=$((i+1)); done
    echo "  *) printf '=== DONE ===\\n';;"; echo 'esac'; } > "$o/sup.sh"; chmod +x "$o/sup.sh"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['supervisor']['command']=sys.argv[2]; d['agent_timeout_s']=int(sys.argv[3]); json.dump(d,open(sys.argv[4],'w'))" \
    "$ORG/org.json" "$o/sup.sh" "$t" "$o/org.json"
  bash "$KIT/scripts/lanes.sh" "$o" new "$ln" "goal" 2 false >/dev/null 2>&1; fill "$o/lanes/$ln/context.md" "$o/lanes/$ln/supervisor-brief.md"
}
O3=$SB/org3; L3=$O3/lanes/r
newlane "$O3" r 120 '=== AGENT name=sleeper model=opus ===\ndo it\n=== END AGENT ===\n' '=== PLAN ===\nwaiting on sleeper\n=== END PLAN ===\n'
( cd "$L3" && ORG_ROOT=$O3 exec python3 "$O3/supervise.py" "$L3" 1 > "$SB/r1.out" 2>&1 ) & LP=$!
for _ in $(seq 1 100); do [ -f "$L3/pids/sleeper.json" ] && break; sleep 0.2; done
kill -9 $LP 2>/dev/null; wait $LP 2>/dev/null
check "B8: agent survives a killed loop (own session)" "pgrep -f '$L3/wt/sleeper' >/dev/null"
rrc=0; (cd "$L3" && ORG_ROOT=$O3 tmo 90 python3 "$O3/supervise.py" "$L3" 2 > "$SB/r2.out" 2>&1) || rrc=$?
check "B8: restarted loop adopts it from its pid file (rc $rrc)" "[ $rrc = 0 ] && has $L3/lane.log 'adopted running agent sleeper'"
check "B8: adopted agent finishes through the safety net, pid file gone" "grep -q 'agent sleeper finished rc=? report=present' $L3/lane.log && [ ! -e $L3/pids/sleeper.json ] && git -C $REPO rev-parse -q --verify refs/heads/lane/r/sleeper >/dev/null"
O4=$SB/org4; L4=$O4/lanes/h
newlane "$O4" h 3 '=== AGENT name=hang model=opus ===\nhang\n=== END AGENT ===\n'
hrc=0; (cd "$L4" && ORG_ROOT=$O4 tmo 90 python3 "$O4/supervise.py" "$L4" 1 > "$SB/h.out" 2>&1) || hrc=$?
check "B8: a deadline kills the agent's whole process group (rc $hrc)" "[ $hrc = 0 ] && has $L4/lane.log 'agent hang TIMED OUT' && grep -q 'agent hang finished rc=124' $L4/lane.log && ! pgrep -f '$L4/wt/hang' >/dev/null"

# ── B6: a usage limit is the CLI's complaint, never a word in a normal reply ──
echo "== usage-limit detection"
O7=$SB/org7; L7=$O7/lanes/u
newlane "$O7" u 120 '=== PLAN ===\nWe are well within quota.\n=== END PLAN ===\n'
qrc=0; (cd "$L7" && ORG_ROOT=$O7 tmo 40 python3 "$O7/supervise.py" "$L7" 1 > "$SB/u.out" 2>&1) || qrc=$?
check "B6: a short reply saying 'quota' is not a usage limit (rc $qrc)" "[ $qrc = 0 ] && ! has $L7/lane.log 'usage limit' && has $L7/lane.log 'supervisor declared DONE'"
O8=$SB/org8; L8=$O8/lanes/v
newlane "$O8" v 120
printf '#!/usr/bin/env bash\nn=$(( $(cat %q 2>/dev/null || echo 0) + 1 )); echo $n > %q; cat >/dev/null\n[ $n = 1 ] && { echo "Claude usage limit reached" >&2; exit 1; }\nprintf "=== DONE ===\\n"\n' "$O8/count" "$O8/count" > "$O8/sup.sh"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['usage_limit_wait_s']=2; json.dump(d,open(sys.argv[1],'w'))" "$O8/org.json"
vrc=0; (cd "$L8" && ORG_ROOT=$O8 tmo 40 python3 "$O8/supervise.py" "$L8" 1 > "$SB/v.out" 2>&1) || vrc=$?
check "B6: a limit on stderr waits, then consults again (rc $vrc)" "[ $vrc = 0 ] && has $L8/lane.log 'supervisor hit a usage limit' && has $L8/lane.log 'supervisor declared DONE' && [ \$(cat $O8/count) = 2 ]"

# ── B3/B2: LAND runs the gates (code from main) and lands only on a checked-out main ──
echo "== LAND gates"
mayland() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['may_land']=True; json.dump(d,open(sys.argv[1],'w'))" "$1/lane.json"; }
O9=$SB/org9; L9=$O9/lanes/gate
newlane "$O9" gate 120 '=== AGENT name=planner model=opus ===\nretune\n=== END AGENT ===\n' \
  '=== LAND branch=lane/gate/planner ===\n=== AGENT name=clean model=opus ===\nmeasure\n=== END AGENT ===\n' \
  '=== LAND branch=lane/gate/clean ===\n'
mayland "$L9"
main0=$(git -C "$REPO" rev-parse main)
grc=0; (cd "$L9" && ORG_ROOT=$O9 tmo 120 python3 "$O9/supervise.py" "$L9" 1 > "$SB/g.out" 2>&1) || grc=$?
RF=$(ls "$L9"/reports/*-zz-land-refused-lane-gate-planner.md 2>/dev/null)
check "B3: a Plan.md change with no Authority: is refused (rc $grc)" "[ $grc = 0 ] && has $L9/lane.log 'LAND lane/gate/planner REFUSED — the landing gates failed' && [ -n '$RF' ] && grep -q 'plan-ownership: exit 1 (FAIL)' '$RF'"
check "B3: the gate code is main's, not the candidate's (its neutered gate did not pass it)" "git -C $REPO show lane/gate/planner:scripts/gates/plan-ownership.mjs | grep -qx 'process.exit(0)' && grep -q 'PLAN-OWNERSHIP\\|Authority' '$RF'"
check "B3: ...never merged: main does not carry the planner's commit" "! git -C $REPO merge-base --is-ancestor lane/gate/planner main"
check "B3: a clean, justified candidate lands" "has $L9/lane.log 'LAND lane/gate/clean ok' && git -C $REPO merge-base --is-ancestor lane/gate/clean main"
check "B3: the refusal reaches the supervisor and the event feed" "has $O9/seen-3.txt 'LAND lane/gate/planner was refused' && grep -E \"\$EVENTS\" $L9/lane.log | grep -q 'LAND lane/gate/planner REFUSED'"
O10=$SB/org10; L10=$O10/lanes/p
newlane "$O10" p 120 '=== AGENT name=parker model=opus ===\nwork\n=== END AGENT ===\n' '=== LAND branch=lane/p/parker ===\n'
mayland "$L10"
git -C "$REPO" checkout -q -b parked main; main1=$(git -C "$REPO" rev-parse main)
prc=0; (cd "$L10" && ORG_ROOT=$O10 tmo 120 python3 "$O10/supervise.py" "$L10" 1 > "$SB/p.out" 2>&1) || prc=$?
check "B2: LAND refused while the repo has another branch checked out (rc $prc)" "[ $prc = 0 ] && has $L10/lane.log 'LAND lane/p/parker REFUSED — $REPO has parked checked out, not main' && ls $L10/reports/*-zz-land-refused-lane-p-parker.md >/dev/null 2>&1"
check "B2: ...main and the parked branch are untouched" "[ \$(git -C $REPO rev-parse main) = $main1 ] && [ \$(git -C $REPO rev-parse parked) = $main1 ]"
git -C "$REPO" checkout -q main

# ── D1/D2: per-lane daily spend caps, running totals ──
echo "== budget caps"
setorg() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d.update(json.loads(sys.argv[2])); json.dump(d,open(sys.argv[1],'w'))" "$@"; }
O11=$SB/org11; L11=$O11/lanes/bud
newlane "$O11" bud 120 '=== PLAN ===\none\n=== END PLAN ===\n' '=== PLAN ===\ntwo\n=== END PLAN ===\n' '=== PLAN ===\nthree\n=== END PLAN ===\n'
setorg "$O11/org.json" '{"max_consults_per_day": 2}'
( cd "$L11" && ORG_ROOT=$O11 exec python3 "$O11/supervise.py" "$L11" 1 > "$SB/bud.out" 2>&1 ) & BP=$!
for _ in $(seq 1 150); do has $L11/lane.log 'BUDGET cap reached' && break; sleep 0.2; done
sleep 2; touch "$L11/STOP"; for _ in $(seq 1 50); do kill -0 $BP 2>/dev/null || break; sleep 0.2; done; kill $BP 2>/dev/null; wait $BP 2>/dev/null
check "D1: consult cap 2 — two consults, then idle" "[ \$(grep -c '=== CONSULT' $L11/lane.log) = 2 ] && has $L11/lane.log 'BUDGET cap reached (consults 2/2)' && has $L11/lane.log 'supervisor loop exiting'"
check "D1: the breach is asked of the owner, once" "[ \$(grep -c '^## Budget' $L11/owner-questions.md) = 1 ] && has $L11/owner-questions.md 'max_consults_per_day'"
check "D1: counters live in loop-state.json" "python3 -c \"import json; b=json.load(open('$L11/loop-state.json'))['budget']; assert b['consults']==2 and b['breached']==['consults'], b\""
check "D2: running total in the lane log, shown by the event feed" "grep -E \"\$EVENTS\" $L11/lane.log | grep -q 'TOTAL [0-9-]*: consults 1/2' && grep -E \"\$EVENTS\" $L11/lane.log | grep -q 'BUDGET cap reached'"
O12=$SB/org12; L12=$O12/lanes/st
newlane "$O12" st 120 '=== AGENT name=a1 model=opus ===\nx\n=== END AGENT ===\n=== AGENT name=a2 model=opus ===\nx\n=== END AGENT ===\n=== AGENT name=a3 model=opus ===\nx\n=== END AGENT ===\n'
setorg "$O12/org.json" '{"max_agent_starts_per_day": 2}'; setorg "$L12/lane.json" '{"max_parallel": 3}'
( cd "$L12" && ORG_ROOT=$O12 exec python3 "$O12/supervise.py" "$L12" 1 > "$SB/st.out" 2>&1 ) & SP2=$!
for _ in $(seq 1 150); do [ "$(grep -c 'finished rc=0' "$L12/lane.log" 2>/dev/null)" = 2 ] && break; sleep 0.2; done
sleep 2; touch "$L12/STOP"; for _ in $(seq 1 50); do kill -0 $SP2 2>/dev/null || break; sleep 0.2; done; kill $SP2 2>/dev/null; wait $SP2 2>/dev/null
check "D1: agent-start cap 2 — the third agent never starts; finished work is still committed" "has $L12/lane.log 'agent a1 (opus) start' && has $L12/lane.log 'agent a2 (opus) start' && ! has $L12/lane.log 'agent a3 (opus) start' && has $L12/lane.log 'BUDGET cap reached (starts 2/2)' && has $L12/lane.log 'agent a2 finished rc=0 report=present' && [ \$(grep -c '=== CONSULT' $L12/lane.log) = 1 ] && has $L12/lane.log 'supervisor loop exiting'"
O13=$SB/org13; L13=$O13/lanes/ro
newlane "$O13" ro 120
printf '{"budget": {"day": "2000-01-01", "consults": 99, "starts": 99, "agent_s": 0, "tick": 0, "breached": ["consults"], "total_at": 0}}' > "$L13/loop-state.json"
rrc2=0; (cd "$L13" && ORG_ROOT=$O13 tmo 60 python3 "$O13/supervise.py" "$L13" 1 > "$SB/ro.out" 2>&1) || rrc2=$?
check "D1: counters reset at UTC midnight, closing total logged (rc $rrc2)" "[ $rrc2 = 0 ] && has $L13/lane.log 'TOTAL 2000-01-01 (closing): consults 99/100' && has $L13/lane.log '=== CONSULT 1' && python3 -c \"import json,datetime; b=json.load(open('$L13/loop-state.json'))['budget']; assert b['day']==datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d') and b['consults']==1, b\""

# ── decision 9: prompts travel on stdin, never argv (Linux caps one argument at 128 KiB) ──
echo "== prompts on stdin"
O5=$SB/org5; L5=$O5/lanes/b
newlane "$O5" b 120 '=== AGENT name=bigone model=opus ===\nread the big context\n=== END AGENT ===\n'
python3 -c "import sys; open(sys.argv[1],'a').write(('context line for the big prompt test. ' * 8 + '\n') * 1100)" "$L5/context.md"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['worktree_links']=['node_modules','vault/Home.md']; json.dump(d,open(sys.argv[1],'w'))" "$O5/org.json"
brc=0; (cd "$L5" && ORG_ROOT=$O5 tmo 90 python3 "$O5/supervise.py" "$L5" 1 > "$SB/b.out" 2>&1) || brc=$?
PF=$(ls "$L5"/prompts/0001-bigone.md 2>/dev/null)
check "A3: an ignored path is linked into the worktree" "[ -L $L5/wt/bigone/node_modules ] && [ -f $L5/wt/bigone/node_modules/dep/index.js ]"
check "A3: a tracked path is refused, logged, left as the branch's own file" "has $L5/lane.log \"worktree_links: skipped 'vault/Home.md' for bigone\" && [ ! -L $L5/wt/bigone/vault/Home.md ] && [ -f $L5/wt/bigone/vault/Home.md ]"
check "D9: worker argv carries no prompt (rc $brc)" "[ $brc = 0 ] && grep -qx -- '-p --dangerously-skip-permissions --model fake-model --disallowedTools Monitor' $L5/args-bigone.txt"
check "D9: a >300 KiB prompt reaches the worker intact on stdin" "[ \$(wc -c < '$PF') -gt 307200 ] && cmp -s '$PF' $L5/stdin-bigone.txt"
check "D9: the instruction is the last line of the prompt" "[ \"\$(tail -n 1 '$PF')\" = 'Follow the brief above verbatim, starting now.' ]"
O6=$SB/org6; L6=$O6/lanes/c
newlane "$O6" c 120
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['supervisor']={'backend':'claude','model':'sup-model'}; json.dump(d,open(sys.argv[1],'w'))" "$O6/org.json"
crc=0; (cd "$L6" && ORG_ROOT=$O6 tmo 60 python3 "$O6/supervise.py" "$L6" 1 > "$SB/c.out" 2>&1) || crc=$?
check "A2: claude supervisor is read-only by allowlist" "grep -q -- '--tools Read,Grep,Glob,WebSearch,WebFetch --disallowedTools mcp__\\* --dangerously-skip-permissions' $L6/claude-sup.args && ! grep -qwE 'Bash|Edit|Write|MultiEdit|NotebookEdit|LS' $L6/claude-sup.args"
check "D9: claude supervisor gets its prompt on stdin, none in argv (rc $crc)" "[ $crc = 0 ] && has $L6/lane.log 'supervisor declared DONE' && ! grep -q 'CONSULT' $L6/claude-sup.args && grep -q '^# CONSULT 1' $L6/claude-sup.stdin && [ \"\$(tail -n 1 $L6/claude-sup.stdin)\" = 'Follow the supervisor brief at the top of this prompt verbatim: emit your blocks now.' ]"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
