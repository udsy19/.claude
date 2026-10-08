#!/usr/bin/env bash
SB=$1; bash ./setup.sh "$SB" >/dev/null || exit 2
export HOME=$SB/home GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@x.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@x.invalid; R=$SB/repo
cd $R && wa=$(mktemp -d)
for k in a b; do git branch lane/$k/x main; git worktree add -q $wa/$k lane/$k/x
  (cd $wa/$k && mkdir -p vault/Reports && printf '# note %s\n\nmeasured\n' $k > vault/Reports/note-$k.md && git add -A && git commit -qm "note $k

EVIDENCE-GROWTH: vault/Reports/note-$k.md records lane $k's measurement."); git worktree remove --force $wa/$k
  printf '=== LAND branch=lane/%s/x ===\n' $k > $SB/script-$k-1.txt; done
for k in a b; do (cd $SB/org/lanes/$k && ORG_ROOT=$SB/org perl -e 'alarm 120; exec @ARGV' python3 $SB/org/supervise.py $SB/org/lanes/$k 1 > $SB/sup-$k.out 2>&1) & done; wait
for k in a b; do grep -hE "LAND|hubs" $SB/org/lanes/$k/lane.log | sed "s/^/$k: /"; done
cd $R; echo "main: $(git log --oneline | wc -l | tr -d ' ') commits; status: $(git status --porcelain | wc -l | tr -d ' ') dirty; lock: $(ls .git/index.lock 2>/dev/null || echo none)"
node scripts/vault-hubs.mjs --check >/dev/null 2>&1 && echo "hubs current" || echo "HUBS STALE on main"
