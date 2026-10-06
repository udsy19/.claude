#!/usr/bin/env bash
# Manage lanes.   usage:
#   lanes.sh <ORG_ROOT> new <name> "<one-line goal>" [max_parallel] [may_land:true|false]
#   lanes.sh <ORG_ROOT> start [name...]        start lane loops (tmux session lane-<name>), adopting running agents
#   lanes.sh <ORG_ROOT> restart [name...]      kill ONLY the python loop (agents keep running) and start again
#   lanes.sh <ORG_ROOT> stop <name>            touch STOP (the loop finishes its current wait and exits)
#   lanes.sh <ORG_ROOT> status                 last lines of every lane log + running agents
#   lanes.sh <ORG_ROOT> gc [name...]           remove worktrees (and build dirs) of finished agents whose branch is
#                                              merged into the lane integration branch; prune renders older than 14 days
#                                              (never renders/owner); git worktree prune. Hourly from cron.
# lane.log lines are "YYYY-MM-DD HH:MM msg" (older lines: "HH:MM msg"); everything here reads both.
set -e
ORG_ROOT=${1:?ORG_ROOT}; cmd=${2:?command}; shift 2
CFG=$ORG_ROOT/org.json; KIT=$(cd "$(dirname "$0")" && pwd)
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
REPO=$(j 'd["repo"]'); MAIN=$(j 'd.get("main_branch","main")')
# One user runs the org. Commands that create or remove lane state refuse up front as anyone else (or root), so
# a wrong-user start never looks like it worked (supervise.py would only refuse inside the tmux session).
U=$(j 'd.get("worker_user") or ""')
case $cmd in new|start|restart|gc)
  run_as="run: su - $U -c \"bash $0 $ORG_ROOT $cmd $*\""
  if [ "$(id -u)" = 0 ]; then
    if [ -n "$U" ]; then echo "refused: lanes run as $U, never root — $run_as"; else echo "refused: lanes never run as root (claude will not skip permissions as root); run them as a normal user"; fi; exit 2; fi
  if [ -n "$U" ] && [ "$(id -un)" != "$U" ]; then echo "refused: this org runs as worker_user $U, not $(id -un) — $run_as"; exit 2; fi;;
esac
all() { local d; for d in "$ORG_ROOT"/lanes/*/; do [ -d "$d" ] && basename "$d"; done; return 0; }
# alive <pid file>: prints the agent's pid if supervise.py's pid file names a live process. The pid file is the
# one record of a running agent: command lines are not (bash 5 execs the last command of `bash -c`, dropping "cd <wt>").
alive() { local p; p=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pid"])' "$1" 2>/dev/null) && kill -0 "$p" 2>/dev/null && echo "$p"; }
named_or_all() { if [ $# -gt 0 ]; then printf '%s\n' "$@"; else all; fi; }   # lane names are [a-z0-9-]
next_round() { local n; n=$(grep -oE "CONSULT [0-9]+" "$ORG_ROOT/lanes/$1/lane.log" 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1); echo $(( ${n:-0} + 1 )); }
start_one() { local k=$1 D=$ORG_ROOT/lanes/$1
  tmux has-session -t "lane-$k" 2>/dev/null && { echo "lane-$k already running"; return; }
  rm -f "$D/STOP"                                   # a stopped lane starts again
  tmux new-session -d -s "lane-$k" "cd $(printf %q "$D") && ORG_ROOT=$(printf %q "$ORG_ROOT") python3 $(printf %q "$ORG_ROOT/supervise.py") $(printf %q "$D") $(next_round "$k") 2>&1 | tee -a $(printf %q "$D/supervise.out")"
  echo "$(date -u '+%F %H:%M') restarted $k at consult $(next_round "$k")" >> "$D/lane.log"; echo "started lane-$k"; }
case $cmd in
  new) k=${1:?name}; goal=${2:?goal}; par=${3:-2}; land=${4:-false}; D=$ORG_ROOT/lanes/$k
    if ! git -C "$REPO" show-ref -q --verify "refs/heads/lane/$k/integration" && ! git -C "$REPO" cat-file -e "$MAIN:vault/AGENTS.md" 2>/dev/null; then
      echo "refused: $MAIN has no vault/AGENTS.md — merge the agent-org set-up commit into $MAIN first (the lane branch is cut from $MAIN)"; exit 2; fi
    TPL=$ORG_ROOT/templates/lane; [ -d "$TPL" ] || TPL=$KIT/../templates/lane
    [ -f "$TPL/context.md" ] || { echo "no lane templates in $ORG_ROOT/templates/lane or $KIT/../templates/lane (re-run bootstrap-host.sh)"; exit 2; }
    mkdir -p "$D"/{reports,prompts,logs,rounds,wt,target,renders/owner}
    python3 - "$D" "$k" "$par" "$land" "$goal" "$ORG_ROOT" "$TPL" <<'PY'
import json,os,sys; D,k,par,land,goal,org,tpl=sys.argv[1:]
json.dump({"name":k,"branch_prefix":f"lane/{k}","max_parallel":int(par),"may_land":land=="true"},open(f"{D}/lane.json","w"),indent=2)
sub={"{{LANE}}":k,"{{LANE_GOAL}}":goal,"{{LANE_ROOT}}":D,"{{ORG_ROOT}}":org}
for t in ("context","supervisor-brief","agent-rules","owner-answers","rulings"):
    out=f"{D}/{t}.md"
    if os.path.exists(out) and os.path.getsize(out): continue      # never overwrite a filled file; refill an empty one
    s=open(f"{tpl}/{t}.md").read()
    for a,b in sub.items(): s=s.replace(a,b)                    # literal: a goal may hold | & / \
    open(out,"w").write(s)
PY
    cd "$REPO"; git show-ref -q --verify "refs/heads/lane/$k/integration" || git branch "lane/$k/integration" "$MAIN"
    [ -e "$D/int/.git" ] || git worktree add -q "$D/int" "lane/$k/integration"
    echo "lane $k created at $D — fill $D/context.md and the GOAL section of $D/supervisor-brief.md before starting";;
  start) for k in $(named_or_all "$@"); do start_one "$k"; done;;
  restart) for k in $(named_or_all "$@"); do D=$ORG_ROOT/lanes/$k
      for q in $(pgrep -f "supervise.py $D"); do kill "$q"; done; sleep 2; tmux kill-session -t "lane-$k" 2>/dev/null || true
      start_one "$k"; done;;
  stop) touch "$ORG_ROOT/lanes/${1:?name}/STOP"; echo "STOP set for $1";;
  status) for k in $(all); do echo "== $k: $(tail -1 "$ORG_ROOT/lanes/$k/lane.log" 2>/dev/null)"; done
    for f in "$ORG_ROOT"/lanes/*/pids/*.json; do
      [ -f "$f" ] && p=$(alive "$f") && echo "running: $(basename "$(dirname "$(dirname "$f")")")/$(basename "$f" .json) (pid $p)"
    done; true;;
  gc) for k in $(named_or_all "$@"); do D=$ORG_ROOT/lanes/$k
      P=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('branch_prefix','lane/'+d['name']))" "$D/lane.json")
      before=$(du -sk "$D" | cut -f1); nw=0
      merged=$(cd "$REPO" && git branch --merged "$P/integration" --format='%(refname:short)')
      for w in "$D"/wt/*/; do [ -d "$w" ] || continue; n=$(basename "$w")
        echo "$merged" | grep -qxF "$P/$n" || continue
        if alive "$D/pids/$n.json" > /dev/null; then echo "  keep wt/$n (agent running)"; continue; fi
        (cd "$REPO" && git worktree remove --force "$w") && { rm -rf "$D/target/$n"; nw=$((nw+1)); echo "  removed wt/$n + target/$n"; }
      done
      nr=$(find "$D/renders" -type f -mtime +14 -not -path "$D/renders/owner/*" -print -delete 2>/dev/null | wc -l | tr -d ' ')
      echo "gc $k: removed $nw worktree(s), $nr render(s) older than 14 days; freed $(( before - $(du -sk "$D" | cut -f1) )) KB"
    done; (cd "$REPO" && git worktree prune);;
  *) echo "unknown command $cmd"; exit 2;;
esac
