#!/usr/bin/env bash
set -u
KITSRC=$1; SB=$(mktemp -d "${TMPDIR:-/tmp}/sbd.XXXXXX"); SB=$(cd "$SB" && pwd -P); echo "SB=$SB"
export HOME=$SB/home; mkdir -p $HOME
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
KIT=$KITSRC/skills/agent-org; ORG=$SB/org; REPO=$SB/repo
git init -q --bare $SB/origin.git; git init -q -b main $REPO; git -C $REPO commit -q --allow-empty -m root; git -C $REPO remote add origin $SB/origin.git
node $KIT/scripts/init-repo.mjs --repo $REPO --vars $KIT/scripts/test-vars.json >/dev/null 2>&1
git -C $REPO add -A; git -C $REPO commit -qm "setup

Authority: owner
EVIDENCE-GROWTH: adds vault/Home.md and the vault contracts."; git -C $REPO push -q origin main
cat > $SB/fake-claude.sh <<'EOF'
#!/bin/bash
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
printf '# %s\n\nmeasured\n' "$AGENT_NAME" > "vault/Reports/$AGENT_NAME.md"
git add -A && git commit -qm "$(printf '%s: measure\n\nEVIDENCE-GROWTH: vault/Reports/%s.md records it.' "$AGENT_NAME" "$AGENT_NAME")"
printf '## TL;DR\n%s done, tried approach X which FAILED, approach Y worked\n' "$AGENT_NAME" > "$report"
EOF
cat > $SB/sup.sh <<EOF
#!/bin/bash
c=$SB/cnt; n=\$(( \$(cat \$c 2>/dev/null || echo 0) + 1 )); echo \$n > \$c; cat > /dev/null
case \$n in
 1) printf '=== PLAN ===\n1. alpha measures\n2. beta builds\n=== END PLAN ===\n=== AGENT name=alpha model=opus ===\nmeasure\n=== END AGENT ===\n';;
 2) printf '=== MERGE branch=lane/core/alpha ===\n=== LEARN ===\napproach X fails on Y; use Z\n=== END LEARN ===\n=== ASK_OWNER ===\nShould beta use Z?\n=== END ASK ===\n=== PLAN ===\n1. alpha DONE\n2. beta builds (waiting on owner)\n=== END PLAN ===\n';;
 *) printf '=== DONE ===\n';;
esac
EOF
chmod +x $SB/*.sh; mkdir -p $ORG; cp $KIT/scripts/*.sh $KIT/scripts/supervise.py $KIT/scripts/lane-metrics.py $ORG/; mkdir -p $ORG/templates; cp -R $KIT/templates/lane $ORG/templates/
cat > $ORG/org.json <<EOF
{"project":"sim","repo":"$REPO","main_branch":"main","worker_user":"","claude_bin":"$SB/fake-claude.sh",
 "supervisor":{"backend":"script","command":"$SB/sup.sh"},"worker_models":{"opus":"x"},"default_worker_model":"opus",
 "poll_interval_s":1,"idle_wait_s":1,"agent_timeout_s":60,"report_overdue_s":30,"api_token":"SECRET"}
EOF
bash $ORG/lanes.sh $ORG new core "core goal" 2 true >/dev/null
python3 -c "import re,sys
for p in sys.argv[1:]:
    t=re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}','filled',open(p).read()); open(p,'w').write(t)" $ORG/lanes/core/context.md $ORG/lanes/core/supervisor-brief.md
printf '\n## 2026-10-07 · beta\nUse Z.\n' >> $ORG/lanes/core/owner-answers.md
(cd $ORG/lanes/core && ORG_ROOT=$ORG perl -e 'alarm 120; exec @ARGV' python3 $ORG/supervise.py $ORG/lanes/core 1 >/dev/null 2>&1)
(cd $REPO && node scripts/propose.mjs --row 1 --kind split --why "beta too big" >/dev/null 2>&1)
bash $ORG/state-snapshot.sh $ORG >/dev/null 2>&1
snap() { (cd $1/lanes/core && find . -path ./wt -prune -o -path ./int -prune -o -type f -print | sort); }
snap $ORG > $SB/before.files; cp -R $ORG/lanes/core $SB/before-core
echo "next_round before: $(grep -oE 'CONSULT [0-9]+' $ORG/lanes/core/lane.log | tail -1)"
git -C $REPO status --porcelain > $SB/before.repo-dirty; git -C $REPO for-each-ref --format='%(refname:short)' refs/heads > $SB/before.branches
# ---- disaster: host gone. Rebuild from git (origin) + snapshot branch, per Recovery ----
rm -rf $ORG $REPO
git clone -q $SB/origin.git $REPO; git -C $REPO for-each-ref --format='%(refname:short)' refs/remotes > $SB/after.remote-branches
mkdir -p $ORG/lanes; git -C $REPO archive origin/backup/lane-state lanes org.json | tar -x -C $ORG
cp $KIT/scripts/*.sh $KIT/scripts/supervise.py $ORG/; mkdir -p $ORG/templates; cp -R $KIT/templates/lane $ORG/templates/
python3 - $ORG/org.json "$REPO" "$SB" <<'PY'
import json,sys; d=json.load(open(sys.argv[1])); d.update(repo=sys.argv[2], claude_bin=sys.argv[3]+"/fake-claude.sh", supervisor={"backend":"script","command":sys.argv[3]+"/sup.sh"}); json.dump(d,open(sys.argv[1],"w"))
PY
bash $ORG/lanes.sh $ORG new core "core goal" 2 true > $SB/new.out 2>&1
snap $ORG > $SB/after.files
echo "next_round after: lane.log has $(grep -c CONSULT $ORG/lanes/core/lane.log 2>/dev/null || echo 0) CONSULT lines -> next start round $(grep -oE 'CONSULT [0-9]+' $ORG/lanes/core/lane.log 2>/dev/null | tail -1 || echo none)"
echo "== files lost (before - after):"; comm -23 $SB/before.files $SB/after.files
echo "== files gained:"; comm -13 $SB/before.files $SB/after.files
echo "== content diffs on surviving files:"; for f in $(comm -12 $SB/before.files $SB/after.files); do cmp -s $SB/before-core/$f $ORG/lanes/core/$f || echo "  DIFFERS $f"; done
echo "== repo dirty before (uncommitted state in main checkout):"; cat $SB/before.repo-dirty
echo "== proposals after:"; ls $REPO/vault/_log/; wc -l < $REPO/vault/_log/proposals.jsonl
echo "== branches before (local):"; tr '\n' ' ' < $SB/before.branches; echo; echo "== remote after:"; tr '\n' ' ' < $SB/after.remote-branches; echo
echo "== lane.json before/after:"; cat $SB/before-core/lane.json; echo; cat $ORG/lanes/core/lane.json; echo
echo "== loop-state before/after:"; cat $SB/before-core/loop-state.json | head -c 600; echo; cat $ORG/lanes/core/loop-state.json | head -c 600; echo
echo "== org.json keys after:"; python3 -c "import json;print(sorted(json.load(open('$ORG/org.json'))))"
echo "SB=$SB"
