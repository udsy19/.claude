#!/usr/bin/env bash
# Hourly (cron): copy everything that lives OUTSIDE git — each lane's plan, consult outputs, prompts, reports,
# owner Q&A, renders — into a git branch, so losing the host never costs the supervisors' memory again.
# No secrets, no build dirs, no worktrees.   cron:  7 * * * * /path/state-snapshot.sh <ORG_ROOT>
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
R=$(j 'd["repo"]'); BR=$(j 'd.get("state_backup_branch","backup/lane-state")')
W=$ORG_ROOT/state-wt
cd "$R"
git show-ref -q --verify "refs/heads/$BR" || git branch -q "$BR" "$(git commit-tree "$(git hash-object -t tree /dev/null)" -m 'lane state root')"
[ -d "$W" ] || git worktree add -q "$W" "$BR"
for d in "$ORG_ROOT"/lanes/*/; do n=$(basename "$d")
  rsync -a --delete --exclude wt --exclude int --exclude target --exclude renders --exclude '*.log' "$d" "$W/lanes/$n/" 2>/dev/null
  mkdir -p "$W/renders/$n"; cp "$d"/renders/owner/*.png "$d"/renders/latest/*.png "$W/renders/$n/" 2>/dev/null   # pinned images only
done
cp "$ORG_ROOT"/org.json "$ORG_ROOT"/*.sh "$W/" 2>/dev/null
cd "$W" && git add -A && git commit -q --no-verify -m "lane state snapshot $(date -u +%F' '%H:%MZ)" && git push -q origin "$BR" && echo "$(date -u +%F' '%H:%M) lane state snapshot pushed"
exit 0
