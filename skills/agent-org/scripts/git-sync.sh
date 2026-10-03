#!/usr/bin/env bash
# Keep GitHub and the work host in lockstep. Every <interval>:
#  - main: fast-forward from origin if behind — the main BRANCH, whichever branch the checkout has out (merge
#    into HEAD only when HEAD is main; otherwise `git fetch origin main:main`). Push if ahead and sync.push_main
#    is true (default false; never force). If both moved: log DIVERGED and touch nothing — a human or the
#    overseer reconciles. NOTE: if pushing main deploys, a landing = a deploy.
#  - push every work branch matching the configured globs (non-force).
# usage: git-sync.sh <ORG_ROOT> [--once]
set -f                     # branch_globs ("lane/*") are refspecs, never filename patterns
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
R=$(j 'd["repo"]'); MAIN=$(j 'd.get("main_branch","main")')
INT=$(j 'd.get("sync",{}).get("interval_s",300)'); PUSH_MAIN=$(j 'd.get("sync",{}).get("push_main",False)')
GLOBS=$(j '" ".join(d.get("sync",{}).get("branch_globs",["lane/*"]))')
L=$ORG_ROOT/logs/git-sync.log; mkdir -p "$ORG_ROOT/logs"
while true; do
  cd "$R"
  if git fetch -q origin "$MAIN" 2>/dev/null; then
    lb=$(git rev-list --left-right --count "$MAIN"...origin/"$MAIN"); a=${lb%%	*}; b=${lb##*	}
    if [ "$b" -gt 0 ] && [ "$a" -eq 0 ]; then
      if [ "$(git symbolic-ref -q --short HEAD)" = "$MAIN" ]; then git merge --ff-only -q origin/"$MAIN" 2>>"$L.err"
      else git fetch -q origin "$MAIN:$MAIN" 2>>"$L.err"; fi \
        && echo "$(date -u +%F' '%H:%M) $MAIN fast-forwarded to $(git rev-parse --short "$MAIN")" >> "$L" \
        || echo "$(date -u +%F' '%H:%M) $MAIN fast-forward FAILED (see git-sync.log.err)" >> "$L"
    elif [ "$a" -gt 0 ] && [ "$b" -eq 0 ] && [ "$PUSH_MAIN" = True ]; then git push -q origin "$MAIN" && echo "$(date -u +%F' '%H:%M) $MAIN pushed $(git rev-parse --short "$MAIN") (+$a)" >> "$L"
    elif [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then echo "$(date -u +%F' '%H:%M) DIVERGED $MAIN +$a/-$b vs origin: not touched" >> "$L"; fi
  else echo "$(date -u +%F' '%H:%M) fetch failed" >> "$L"; fi
  refs=(); for g in $GLOBS; do refs+=("refs/heads/$g:refs/heads/$g"); done
  git push -q origin "${refs[@]}" >/dev/null 2>>"$L.err" || echo "$(date -u +%F' '%H:%M) some branch pushes refused (see git-sync.log.err)" >> "$L"
  [ "${2:-}" = --once ] && break
  sleep "$INT"
done
