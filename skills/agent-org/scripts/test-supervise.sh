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
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

echo "== sandbox $SB"
# ── the project repo: main + a vault with generated hubs, and an origin to push to ──
git init -q --bare "$SB/origin.git"
git init -q -b main "$REPO" && cd "$REPO" || exit 2
mkdir -p vault/Reports scripts/lib
cp "$KIT/templates/repo/scripts/vault-hubs.mjs" scripts/; cp "$KIT/templates/repo/scripts/lib/argv.mjs" scripts/lib/
printf '# Home\n\nStart here. [[Map]]\n' > vault/Home.md
printf '# First report\n\nMeasured something.\n' > vault/Reports/first.md
node scripts/vault-hubs.mjs >/dev/null || { echo "vault-hubs failed in the sandbox"; exit 2; }
git add -A && git commit -qm "init" && git remote add origin "$SB/origin.git" && git push -q origin main

# ── fakes ──
cat > "$SB/fake-claude.sh" <<'EOF'
#!/usr/bin/env bash
# Fake worker: commits work, saves an image in $RENDERS_DIR, writes a long report with a TL;DR.
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
report=$(printf '%s' "$*" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
case "$AGENT_NAME" in
  slowpoke) sleep 611; exit 0;;          # never reports: overdue warning, then KILL
  alpha) sleep 2;;
  beta) sleep 8;;
esac
echo "$AGENT_NAME" > "work-$AGENT_NAME.txt"
[ "$AGENT_NAME" = alpha ] && printf '# Alpha finding\n\nAlpha measured a thing.\n' > vault/Reports/alpha-finding.md
git add -A && git commit -qm "$AGENT_NAME work"
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
  3) printf 'slowpoke is overdue.\n=== KILL name=slowpoke ===\n';;
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
echo "- RULING-KEEP-7: the owner's current law" >> "$L/rulings.md"
for i in $(seq -w 1 15); do printf '\n## 2026-10-%s · question A%s\nanswer-A%s\n' "$i" "$i" "$i" >> "$L/owner-answers.md"; done
printf 'PNG-owner' > "$L/renders/owner/ref-owner.png"

# ── run the loop ──
echo "== supervise.py (canned consults 1-5)"
( cd "$L" && ORG_ROOT=$ORG timeout 180 python3 "$ORG/supervise.py" "$L" 1 > "$SB/supervise.out" 2>&1 ); rc=$?
check "loop exits cleanly on DONE (rc $rc)" "[ $rc = 0 ] && has $L/lane.log 'supervisor declared DONE'"
check "five consults ran" "[ \$(grep -c '=== CONSULT' $L/lane.log) = 5 ]"
check "log lines carry the date" "grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} === CONSULT 1' $L/lane.log"
S=$SB/seen
# prompt budget
check "rulings.md injected in full" "has $S/1.txt RULING-KEEP-7"
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

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
