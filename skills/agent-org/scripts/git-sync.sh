#!/usr/bin/env bash
# Keep GitHub and the work host in lockstep. Every <interval>:
#  - main (promote.py sync-main, under the promotion lock): fast-forward the main BRANCH from origin if behind
#    (compare-and-swap; the checkout's files follow only if it has main out and clean). Push if ahead and
#    sync.push_main is true (default false; never force). If both moved: log DIVERGED and touch nothing — LAND is
#    refused until a human or the overseer reconciles. NOTE: if pushing main deploys, a landing = a deploy.
#  - push every work branch matching the configured globs (non-force).
# usage: git-sync.sh <ORG_ROOT> [--once]
set -f                     # branch_globs ("lane/*") are refspecs, never filename patterns
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
R=$(j 'd["repo"]'); INT=$(j 'd.get("sync",{}).get("interval_s",300)')
GLOBS=$(j '" ".join(d.get("sync",{}).get("branch_globs",["lane/*"]))')
L=$ORG_ROOT/logs/git-sync.log; mkdir -p "$ORG_ROOT/logs"
while true; do
  cd "$R" || exit 1
  # main moves only under the promotion lock, never at the same time as a landing (promote.py sync-main)
  python3 "$ORG_ROOT/promote.py" "$ORG_ROOT" sync-main >/dev/null 2>>"$L.err" || echo "$(date -u +%F' '%H:%M) sync-main failed (see git-sync.log.err)" >> "$L"
  refs=(); for g in $GLOBS; do refs+=("refs/heads/$g:refs/heads/$g"); done
  git push -q origin "${refs[@]}" >/dev/null 2>>"$L.err" || echo "$(date -u +%F' '%H:%M) some branch pushes refused (see git-sync.log.err)" >> "$L"
  [ "${2:-}" = --once ] && break
  sleep "$INT"
done
