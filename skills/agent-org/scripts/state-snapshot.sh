#!/usr/bin/env bash
# Hourly: copy each lane's RECOVERY state — what lives outside git and a restart needs — into a git branch
# (org.json state_backup_branch, default backup/lane-state) and push it to origin: anyone who can read origin can
# read it. Per lane, only: plan.md, lane-memory*.md, rulings.md, owner-questions.md, lane.json, loop-state.json,
# context.md and supervisor-brief.md (the lane's goal: recovery must not mean retyping it) and the pinned renders
# (renders/owner, renders/latest); plus org.json with secrets-shaped keys removed. Anything else
# (prompts, rounds, reports, owner-answers.md, supervise.out …) only if org.json state_backup.include
# names it, as a path or rsync pattern relative to a lane dir. Never build dirs or worktrees.
# usage: state-snapshot.sh <ORG_ROOT>        (hourly, from the job bootstrap-host.sh installs)
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
R=$(j 'd["repo"]'); BR=$(j 'd.get("state_backup_branch","backup/lane-state")')
W=$ORG_ROOT/state-wt
cd "$R" || exit 1
git show-ref -q --verify "refs/heads/$BR" || git branch -q "$BR" "$(git commit-tree "$(git hash-object -t tree /dev/null)" -m 'lane state root')"
[ -d "$W" ] || { git worktree prune; git worktree add -q "$W" "$BR"; }   # prune: a deleted state-wt stays registered
[ -e "$W/.git" ] || { echo "$(date -u +%F' '%H:%M) no snapshot worktree at $W — not snapshotting"; exit 1; }
inc=(); for p in plan.md 'lane-memory*.md' rulings.md owner-questions.md lane.json loop-state.json context.md supervisor-brief.md \
                 renders/ renders/owner/ 'renders/owner/*.png' renders/latest/ 'renders/latest/*.png'; do inc+=(--include="/*/$p"); done
while IFS= read -r p; do [ -n "$p" ] && inc+=(--include="/*/${p%/}" --include="/*/${p%/}/**"); done \
  < <(j '"\n".join(d.get("state_backup", {}).get("include", []))')
mkdir -p "$ORG_ROOT/lanes" "$W/lanes"
rsync -a --delete --delete-excluded --include='/*/' "${inc[@]}" --exclude='*' "$ORG_ROOT/lanes/" "$W/lanes/"
find "$W" -mindepth 1 -maxdepth 1 ! -name .git ! -name lanes -exec rm -rf {} +   # older kits copied scripts and renders here
python3 - "$CFG" "$W/org.json" <<'PY'
import json, re, sys
SECRET = re.compile(r"token|secret|key|password|auth", re.I)
def strip(v):
    if isinstance(v, dict): return {k: strip(x) for k, x in v.items() if not SECRET.search(k)}
    if isinstance(v, list): return [strip(x) for x in v]
    return v
json.dump(strip(json.load(open(sys.argv[1]))), open(sys.argv[2], "w"), indent=2)
PY
cd "$W" && git add -A && { git commit -q --no-verify -m "lane state snapshot $(date -u +%F' '%H:%MZ)" || true; } \
  && git push -q origin "$BR" && echo "$(date -u +%F' '%H:%M) lane state snapshot pushed"   # pushes a missed commit too
exit 0
