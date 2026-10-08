#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # fakes are written with literal $vars; outputs are read by eval'd check strings
# Adversarial regression suite for promotions (audit 2026-10-07, auditors B and C): every case drives real lane
# loops (supervise.py, script backend, hostile fake workers) and must FAIL on main@e318f8b and PASS with the
# trusted promotion coordinator (promote.py). Control run: KIT=<an older tree>/skills/agent-org bash <this file>.
#   F1/C1  the merged candidate is verified: a lying worker, and two lanes that break main only together
#   F2     two lanes landing at once: serialized, no false CONFLICT, each landing recorded with its own SHA
#   F3     a main diverged from origin refuses LAND
#   F4b    a crash after main moved is reconciled; hubs and Index are part of the landing (board green)
#   F4d    a leftover half-merge in the shared checkout is never silently discarded
#   F6/A4  only this lane's own integration lands; only dispatched agent branches merge; no origin/ or safety net
#   F7     MERGE refreshes integration from main
#   C6     DONE is derived from the owner's acceptance criteria on main's tree, never asserted
#   state  hash chain intact after a kill -9 mid-promotion; a fresh db rebuilt from the journal has the same head
set -u
KIT=${KIT:-$(cd "$(dirname "$0")/.." && pwd)}
SB=$(mktemp -d "${TMPDIR:-/tmp}/adv-promo.XXXXXX"); SB=$(cd "$SB" && pwd -P)
PASS=0; FAIL=0
cleanup() { if [ "${KEEP:-}" = 1 ]; then echo "sandbox kept: $SB"; else rm -rf "$SB"; fi; }
trap cleanup EXIT
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
tmo() { perl -e 'alarm shift; exec @ARGV or die "exec $ARGV[0]: $!"' "$@"; }
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@example.invalid
export HOME=$SB/home; mkdir -p "$HOME"

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────
cat > "$SB/vars.json" <<'JSON'
{"PROJECT": "Adv", "MAIN_BRANCH": "main", "MISSION": "first-mission", "MISSION_TITLE": "First mission",
 "MISSION_GOAL": "Ship", "VISION_ONE_LINER": "An adversarial sandbox", "USERS": "t", "ACCEPTANCE_BAR": "check.sh passes",
 "OWNER_WORDS": "w", "NOT_WORKED": "n", "NEXT_MOVE": "s", "FIRST_TRACK": "core", "FIRST_TRACK_ITEM": "s",
 "SOURCE_AREAS": "| `src/` | code | src/check.sh |", "SUPERVISOR_DESC": "canned", "WORKER_DESC": "fake",
 "RUNTIME": "local", "HOST": "localhost", "ORG_ROOT": "/tmp/org", "STATE_BRANCH": "backup/lane-state",
 "LANE_TABLE": "| a | x | a | lane/a/* | 2 | yes |", "EXTRA_RULINGS": "- (none yet)"}
JSON
# The fake worker: runs the hostile script $ORG_ROOT/worker-<name>.sh in its worktree, commits, reports.
cat > "$SB/fake-claude.sh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
org=${FAKE_ORG:?}   # baked in by the per-org claude.sh: workers get no LANE_ROOT/ORG_ROOT (isolation A5)
msg=$(printf '%s work\n\nEVIDENCE-GROWTH: vault/Reports/%s.md records what %s did, which the lane needs to judge it.' "$AGENT_NAME" "$AGENT_NAME" "$AGENT_NAME")
printf '# %s\n\nwork\n' "$AGENT_NAME" > "vault/Reports/$AGENT_NAME.md"
[ -f "$org/worker-$AGENT_NAME.sh" ] && . "$org/worker-$AGENT_NAME.sh"
git add -A && git commit -qm "$msg"
printf '## TL;DR\n%s: all tests pass, production ready.\n' "$AGENT_NAME" > "$report"
EOF
chmod +x "$SB/fake-claude.sh"

mkrepo() {   # mkrepo <dir>: an agent-org project (init-repo) whose product check is limit*factor <= 10, pushed to origin
  local d=$1; git init -q --bare "$d/origin.git"; git init -q -b main "$d/repo"
  ( cd "$d/repo" || exit 2; git commit -q --allow-empty -m root
    node "$KIT/scripts/init-repo.mjs" --repo "$d/repo" --vars "$SB/vars.json" > "$d/init.out" 2>&1 || exit 2
    mkdir -p src; printf 'limit=5\n' > src/a.conf; printf 'factor=1\n' > src/b.conf
    printf '#!/bin/sh\nl=$(sed -n "s/limit=//p" src/a.conf); f=$(sed -n "s/factor=//p" src/b.conf)\n[ $((l*f)) -le 10 ] || { echo "CHECK FAIL: limit*factor=$((l*f))"; exit 1; }\necho "check ok: $((l*f))"\n' > src/check.sh
    chmod +x src/check.sh; node scripts/vault-hubs.mjs >/dev/null; python3 scripts/gen-subject-index.py >/dev/null 2>&1
    git add -A && git commit -q -m "set-up" -m "Authority: owner" \
      -m "EVIDENCE-GROWTH: vault/Home.md, scripts/gates/org-board.sh, src/check.sh, src/a.conf and src/b.conf arrive with the repo layer and the product so the gates and the check have a real project." \
    && git remote add origin "$d/origin.git" && git push -q origin main ) || { echo "mkrepo failed: $(tail -3 "$d/init.out")"; exit 2; }
}
mkorg() {    # mkorg <dir> <lanes...>: an org on <dir>/repo (verify = the product check), one canned supervisor per lane
  local d=$1; shift; local o=$d/org; mkdir -p "$o"
  cp "$KIT/scripts/supervise.py" "$o/"; cp "$KIT/scripts/promote.py" "$KIT/scripts/orgstate.py" "$o/" 2>/dev/null
  cp "$KIT/scripts/lanes.sh" "$KIT/scripts/git-sync.sh" "$o/"; mkdir -p "$o/templates"; cp -R "$KIT/templates/lane" "$o/templates/"
  cat > "$o/sup.sh" <<EOF
#!/usr/bin/env bash
lane=\$(basename "\$(dirname "\$PWD")"); c=$o/count-\$lane; n=\$(( \$(cat "\$c" 2>/dev/null || echo 0) + 1 )); echo \$n > "\$c"
cat > "$o/seen-\$lane-\$n.txt"; f="$o/script-\$lane-\$n.txt"; if [ -f "\$f" ]; then cat "\$f"; else printf '=== DONE ===\\n'; fi
EOF
  chmod +x "$o/sup.sh"
  printf '#!/usr/bin/env bash\nFAKE_ORG=%q exec %q "$@"\n' "$o" "$SB/fake-claude.sh" > "$o/claude.sh"; chmod +x "$o/claude.sh"
  cat > "$o/org.json" <<EOF
{ "project": "adv", "repo": "$d/repo", "main_branch": "main", "worker_user": "", "claude_bin": "$o/claude.sh",
  "supervisor": { "backend": "script", "command": "$o/sup.sh" }, "worker_models": { "opus": "fake" }, "default_worker_model": "opus",
  "agent_timeout_s": 120, "report_overdue_s": 600, "poll_interval_s": 1, "idle_wait_s": 1, "consult_timeout_s": 60,
  "verify": [{"name": "product-check", "run": "sh src/check.sh"}], "sync": {"interval_s": 1, "branch_globs": ["lane/*"]},
  "isolation": {"mode": "none"} }
EOF
  for k in "$@"; do bash "$o/lanes.sh" "$o" new "$k" "goal $k" 2 true >/dev/null || { echo "lanes.sh new $k failed"; exit 2; }
    python3 -c "import re,sys
for p in sys.argv[1:]:
    t = re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}', 'filled', open(p).read()); open(p, 'w').write(t)" "$o/lanes/$k/context.md" "$o/lanes/$k/supervisor-brief.md"; done
}
say() { printf '%b' "$3" > "$1/org/script-$2.txt"; }        # say <dir> <lane>-<n> <canned supervisor output>
worker() { printf '%s\n' "$3" > "$1/org/worker-$2.sh"; }     # worker <dir> <agent> <shell run in its worktree>
loop() {     # loop <dir> <lane> [env...]: run the lane loop to its end; output in <dir>/<lane>.out
  local d=$1 ln=$2; shift 2
  (cd "$d/org/lanes/$ln" && env ORG_ROOT="$d/org" "$@" perl -e 'alarm 150; exec @ARGV' python3 "$d/org/supervise.py" "$d/org/lanes/$ln" 1 > "$d/$ln.out" 2>&1)
}
LOG() { cat "$1/org/lanes/$2/lane.log" 2>/dev/null; }
main_check() { git -C "$1/repo" show main:src/a.conf > "$SB/mc.a" && git -C "$1/repo" show main:src/b.conf > "$SB/mc.b" \
  && l=$(sed -n 's/limit=//p' "$SB/mc.a") && f=$(sed -n 's/factor=//p' "$SB/mc.b") && [ $((l*f)) -le 10 ]; }

# ── F1 / C1: the exact merged candidate is verified ─────────────────────────────────────────────────────────
echo "== F1/C1: verification of the merged candidate"
D=$SB/f1; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a b
worker "$D" x 'printf "limit=8\n" > src/a.conf'          # alone: 8*1 = 8, passes
worker "$D" y 'printf "factor=2\n" > src/b.conf'         # alone: 5*2 = 10, passes; together with x: 16
say "$D" a-1 '=== AGENT name=x model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/x ===\n=== LAND branch=lane/a/x ===\n=== LAND branch=lane/a/integration ===\n'
say "$D" b-1 '=== AGENT name=y model=opus ===\ny\n=== END AGENT ===\n'
say "$D" b-2 '=== MERGE branch=lane/b/y ===\n=== LAND branch=lane/b/y ===\n=== LAND branch=lane/b/integration ===\n'
loop "$D" a; loop "$D" b
check "F1: x lands, then y — which passes alone — is refused (at MERGE, integration carrying main, or at LAND)" \
  "LOG $D a | grep -q 'LAND lane/a/integration ok' && LOG $D b | grep -qE '(MERGE lane/b/y|LAND lane/b/integration) REFUSED — verification failed' && ! git -C $D/repo merge-base --is-ancestor lane/b/y main"
check "F1: main still passes the product check" "main_check $D"
check "F1: the refusal report names the failing check on the merged candidate" "grep -l 'CHECK FAIL: limit\*factor=16' $D/org/lanes/b/reports/*zz-*-refused-*.md >/dev/null 2>&1"
D=$SB/c1; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" t
worker "$D" liar 'printf "limit=50\n" > src/a.conf'      # breaks the product, reports "all tests pass"
say "$D" t-1 '=== AGENT name=liar model=opus ===\nx\n=== END AGENT ===\n'
say "$D" t-2 '=== MERGE branch=lane/t/liar ===\n=== LAND branch=lane/t/liar ===\n=== LAND branch=lane/t/integration ===\n'
loop "$D" t
check "C1: a lying worker's broken change is refused at MERGE, never reaches integration or main" \
  "LOG $D t | grep -q 'MERGE lane/t/liar REFUSED' && ! git -C $D/repo merge-base --is-ancestor lane/t/liar lane/t/integration && main_check $D"

# ── F6 / A4: scope ──────────────────────────────────────────────────────────────────────────────────────────
echo "== F6/A4: what a lane may promote"
D=$SB/f6; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a b
git -C "$D/repo" branch lane/b/wip main; git -C "$D/repo" worktree add -q "$D/wip" lane/b/wip
( cd "$D/wip" && printf 'EVIL\n' > vault/Reports/evil.md && git add -A && git commit -qm "evil" -m "EVIDENCE-GROWTH: vault/Reports/evil.md is needed." && git push -q origin lane/b/wip:lane/b/pushed )
git -C "$D/repo" fetch -q origin
git -C "$D/repo" branch lane/a/ghost main; ( cd "$D/wip" && git checkout -q -b lane/a/net && printf 'x\n' > vault/Reports/net.md && git add -A && git commit -qm "lane/a net: uncommitted agent work (safety net)" )
say "$D" a-1 '=== MERGE branch=lane/b/wip ===\n=== LAND branch=lane/b/wip ===\n=== LAND branch=origin/lane/b/pushed ===\n=== MERGE branch=lane/a/ghost ===\n=== MERGE branch=lane/a/net ===\n'
main0=$(git -C "$D/repo" rev-parse main); int0=$(git -C "$D/repo" rev-parse lane/a/integration)
loop "$D" a
check "F6: another lane's branch is refused (MERGE and LAND)" "LOG $D a | grep -q 'MERGE lane/b/wip REFUSED' && LOG $D a | grep -q 'LAND lane/b/wip REFUSED'"
check "F6: a remote-tracking ref is refused, by scope" "LOG $D a | grep -q 'LAND origin/lane/b/pushed REFUSED — origin/lane/b/pushed is not a local work branch'"
check "A4: a branch this lane never dispatched is refused" "LOG $D a | grep -q 'MERGE lane/a/ghost REFUSED'"
check "F4c: a safety-net tip is refused" "LOG $D a | grep -q 'MERGE lane/a/net REFUSED'"
check "F6: main and integration did not move" "[ \$(git -C $D/repo rev-parse main) = $main0 ] && [ \$(git -C $D/repo rev-parse lane/a/integration) = $int0 ]"

# ── F7: integration follows main ────────────────────────────────────────────────────────────────────────────
echo "== F7: MERGE refreshes integration from main"
D=$SB/f7; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a b
worker "$D" p 'printf "limit=6\n" > src/a.conf'
worker "$D" q 'printf "# q\n" > vault/Reports/q-extra.md'
say "$D" a-1 '=== AGENT name=p model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/p ===\n=== LAND branch=lane/a/integration ===\n'
say "$D" b-1 '=== AGENT name=q model=opus ===\nx\n=== END AGENT ===\n'
say "$D" b-2 '=== MERGE branch=lane/b/q ===\n'
loop "$D" a; loop "$D" b
check "F7: after lane a lands, lane b's MERGE carries a's change into b's integration" \
  "LOG $D b | grep -q 'MERGE lane/b/q ok' && git -C $D/repo show lane/b/integration:src/a.conf | grep -qx 'limit=6'"

# ── F4b / C5: a crash right after main moved; hubs and Index belong to the landing ──────────────────────────
echo "== F4b/C5: crash after the ref update, then restart"
D=$SB/f4; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a
worker "$D" n 'printf "# Note n\n\nfinding\n" > vault/Reports/n-note.md'
say "$D" a-1 '=== AGENT name=n model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/n ===\n=== LAND branch=lane/a/n ===\n=== LAND branch=lane/a/integration ===\n'
loop "$D" a PROMOTE_CRASH_AT=after-cas
printf '=== PLAN ===\nafter the crash\n=== END PLAN ===\n' > "$D/org/script-a-3.txt"
(cd "$D/org/lanes/a" && ORG_ROOT="$D/org" perl -e 'alarm 60; exec @ARGV' python3 "$D/org/supervise.py" "$D/org/lanes/a" 3 > "$D/a2.out" 2>&1)
check "F4b: the interrupted MERGE is reconciled as promoted on restart, and the supervisor is told" \
  "LOG $D a | grep -q 'RECONCILED: PROM-[0-9]* (MERGE lane/a/n into lane/a/integration) was interrupted after it moved' && has $D/org/seen-a-3.txt 'was interrupted after it moved'"
check "F4b: integration carries n exactly once; no promotion is left half-done" \
  "git -C $D/repo merge-base --is-ancestor lane/a/n lane/a/integration && [ \$(git -C $D/repo log --oneline --grep='merge lane/a/n' lane/a/integration | wc -l | tr -d ' ') -le 1 ] && python3 -c \"import sqlite3,sys; c=sqlite3.connect('$D/org/state/org.db'); sys.exit(c.execute(\\\"select count(*) from promotions where state in ('requested','verifying')\\\").fetchone()[0])\""
D=$SB/c5; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a
worker "$D" m 'printf "# Note m\n\nfinding\n" > vault/Reports/m-note.md'
say "$D" a-1 '=== AGENT name=m model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/m ===\n=== LAND branch=lane/a/m ===\n=== LAND branch=lane/a/integration ===\n'
loop "$D" a
check "C5/F4b: after the loop's own landing, main's hubs and Index are current (org-board rows green)" \
  "git -C $D/repo merge-base --is-ancestor lane/a/m main && (cd $D/repo && git checkout -q main && node scripts/vault-hubs.mjs --check >/dev/null 2>&1 && python3 scripts/gen-subject-index.py --check >/dev/null 2>&1)"

# ── F4d: a leftover half-merge in the shared checkout is never discarded ────────────────────────────────────
echo "== F4d: a half-merge left in the shared checkout"
D=$SB/f4d; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a
git -C "$D/repo" branch lane/y main; git -C "$D/repo" worktree add -q "$D/y" lane/y
( cd "$D/y" && printf 'y\n' > vault/Reports/y-half.md && git add -A && git commit -qm y )
git -C "$D/repo" merge --no-ff --no-commit -q lane/y >/dev/null 2>&1   # interrupted: MERGE_HEAD + staged y
worker "$D" z 'printf "# z\n" > vault/Reports/z-note.md'
say "$D" a-1 '=== AGENT name=z model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/z ===\n=== LAND branch=lane/a/z ===\n=== LAND branch=lane/a/integration ===\n'
loop "$D" a
check "F4d: the leftover half-merge is still there (MERGE_HEAD, y staged): nobody aborted it" \
  "[ -f $D/repo/.git/MERGE_HEAD ] && git -C $D/repo diff --cached --name-only | grep -qx vault/Reports/y-half.md"

# ── F3: divergence ──────────────────────────────────────────────────────────────────────────────────────────
echo "== F3: main diverged from origin"
D=$SB/f3; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a
git -C "$D/repo" commit -q --allow-empty -m "a local landing, not pushed (push_main false)"
git clone -q "$D/origin.git" "$D/other" && ( cd "$D/other" && git commit -q --allow-empty -m "hotfix on origin" && git push -q origin main )
say "$D" a-1 '=== AGENT name=w model=opus ===\nx\n=== END AGENT ===\n'
say "$D" a-2 '=== MERGE branch=lane/a/w ===\n=== LAND branch=lane/a/w ===\n=== LAND branch=lane/a/integration ===\n'
main0=$(git -C "$D/repo" rev-parse main)
loop "$D" a
check "F3: LAND refused while main is DIVERGED from origin; main unmoved" \
  "LOG $D a | grep -q 'LAND lane/a/integration REFUSED — main is DIVERGED from origin' && [ \$(git -C $D/repo rev-parse main) = $main0 ]"

# ── F2: two lanes landing at the same time ──────────────────────────────────────────────────────────────────
echo "== F2: concurrent landings (trials)"
TRIALS=${ADV_TRIALS:-5}; bad=0; okall=0
for t in $(seq 1 "$TRIALS"); do
  D=$SB/f2-$t; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a b
  worker "$D" r1 'printf "# r1\n" > vault/Reports/r1-a.md'; worker "$D" r2 'printf "# r2\n" > vault/Reports/r2-b.md'
  say "$D" a-1 '=== AGENT name=r1 model=opus ===\nx\n=== END AGENT ===\n'; say "$D" a-2 '=== MERGE branch=lane/a/r1 ===\n=== LAND branch=lane/a/r1 ===\n=== LAND branch=lane/a/integration ===\n'
  say "$D" b-1 '=== AGENT name=r2 model=opus ===\nx\n=== END AGENT ===\n'; say "$D" b-2 '=== MERGE branch=lane/b/r2 ===\n=== LAND branch=lane/b/r2 ===\n=== LAND branch=lane/b/integration ===\n'
  loop "$D" a & p1=$!; loop "$D" b & p2=$!; wait $p1 $p2
  if LOG "$D" a | grep -q 'CONFLICT' || LOG "$D" b | grep -q 'CONFLICT'; then bad=$((bad+1)); fi
  if git -C "$D/repo" merge-base --is-ancestor lane/a/r1 main && git -C "$D/repo" merge-base --is-ancestor lane/b/r2 main; then
    sa=$(LOG "$D" a | sed -n 's/.*LAND lane\/a\/integration ok (\([0-9a-f]*\),.*/\1/p'); sb=$(LOG "$D" b | sed -n 's/.*LAND lane\/b\/integration ok (\([0-9a-f]*\),.*/\1/p')
    if [ -n "$sa" ] && [ -n "$sb" ] && git -C "$D/repo" log --format=%B -1 "$sa" | grep -q 'lane/a' && git -C "$D/repo" log --format=%B -1 "$sb" | grep -q 'lane/b'; then okall=$((okall+1)); fi
  fi
done
check "F2: no false CONFLICT on disjoint files in $TRIALS concurrent trials ($bad had one)" "[ $bad = 0 ]"
check "F2: in every trial both lanes landed, each logged SHA is that lane's own landing ($okall/$TRIALS)" "[ $okall = $TRIALS ]"

# ── C6: DONE is derived, never asserted ─────────────────────────────────────────────────────────────────────
echo "== C6: DONE"
D=$SB/c6; mkdir -p "$D"; mkrepo "$D"; mkorg "$D" a
say "$D" a-1 '=== DONE ===\n'
loop "$D" a
check "C6: DONE with no acceptance criteria is a claim, not done: lane halts, the owner is asked" \
  "LOG $D a | grep -q 'DONE claimed by the supervisor' && LOG $D a | grep -q 'DONE NOT verified — mission first-mission has no acceptance criteria' && has $D/org/lanes/a/owner-questions.md 'DONE claimed, not verified'"
( cd "$D/repo" && python3 - vault/Missions/first-mission.md <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("| # | property that must hold | gate or browser check that proves it | status |\n|---|---|---|---|\n",
              "| # | property that must hold | gate or browser check that proves it | status |\n|---|---|---|---|\n"
              "| AC-1 | the product check passes | `sh src/check.sh` | open |\n| AC-2 | limit is at least 7 | `grep -q 'limit=[7-9]' src/a.conf` | open |\n")
open(p, "w").write(t)
PY
  git commit -qam "mission: acceptance criteria" -m "Authority: owner" )
rm -f "$D/org/count-a"; say "$D" a-1 '=== DONE ===\n'
loop "$D" a
check "C6: a failing criterion on main's tree: NOT verified, the criterion named" "LOG $D a | grep -q 'DONE NOT verified — AC-2 (limit is at least 7) fails on'"
( cd "$D/repo" && printf 'limit=7\n' > src/a.conf && git commit -qam "limit 7" )
rm -f "$D/org/count-a"; say "$D" a-1 '=== DONE ===\n'
loop "$D" a
check "C6: every criterion passes on main's current tree: DONE verified" "LOG $D a | grep -q 'DONE verified: mission first-mission: 2 acceptance criteria verified'"
check "C6: each acceptance verification is recorded against that exact tree" \
  "python3 -c \"import sqlite3,subprocess,sys; c=sqlite3.connect('$D/org/state/org.db'); t=subprocess.check_output(['git','-C','$D/repo','rev-parse','main^{tree}'],text=True).strip(); n=c.execute(\\\"select count(*) from verifications where kind='acceptance' and exit=0 and tree_sha=?\\\",(t,)).fetchone()[0]; sys.exit(0 if n==2 else 1)\""

# ── canonical state: chain, crash, rebuild, evidence immutability ───────────────────────────────────────────
echo "== canonical state"
O=$SB/f1/org
check "state: the hash chain verifies" "python3 $O/orgstate.py $O verify | grep -q 'chain ok'"
check "state: evidence logs are content-addressed and read-only" "ls $O/state/artifacts/ | grep -qE '^[0-9a-f]{64}$' && ! find $O/state/artifacts -type f -perm -u+w | grep -q ."
check "state: every refusal and promotion of lane b is recorded with its verifications" \
  "python3 -c \"import sqlite3,sys; c=sqlite3.connect('$O/state/org.db'); r=c.execute(\\\"select count(*) from promotions where lane='b' and state='refused'\\\").fetchone()[0]; v=c.execute(\\\"select count(*) from verifications v join promotions p on v.promotion=p.id where p.lane='b' and v.exit!=0\\\").fetchone()[0]; sys.exit(0 if r>=1 and v>=1 else 1)\""
check "state: the journal is on the repo's state/journal branch" "git -C $SB/f1/repo ls-tree -r --name-only state/journal | grep -q '^journal/.*\.jsonl$'"
h1=$(python3 "$O/orgstate.py" "$O" head 2>/dev/null); h2=$(python3 "$O/orgstate.py" "$O" rebuild "$SB/rebuilt.db" 2>/dev/null)
check "state: a fresh db rebuilt from the journal has the same head ($h1)" "[ -n \"$h1\" ] && [ \"$h1\" = \"$h2\" ]"
D=$SB/f4; O=$D/org
check "state: the chain still verifies after the kill mid-promotion" "python3 $O/orgstate.py $O verify | grep -q 'chain ok'"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
