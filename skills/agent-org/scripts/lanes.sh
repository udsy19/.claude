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
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
REPO=$(j 'd["repo"]'); MAIN=$(j 'd.get("main_branch","main")'); U=$(j 'd.get("worker_user") or ""')
all() { ls -d "$ORG_ROOT"/lanes/*/ 2>/dev/null | xargs -n1 basename; }
next_round() { local n; n=$(grep -oE "CONSULT [0-9]+" "$ORG_ROOT/lanes/$1/lane.log" 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1); echo $(( ${n:-0} + 1 )); }
start_one() { local k=$1 D=$ORG_ROOT/lanes/$1
  tmux has-session -t "lane-$k" 2>/dev/null && { echo "lane-$k already running"; return; }
  tmux new-session -d -s "lane-$k" "cd $D && ORG_ROOT=$ORG_ROOT python3 $ORG_ROOT/supervise.py $D $(next_round $k) 2>&1 | tee -a $D/supervise.out"
  echo "$(date -u '+%F %H:%M') restarted $k at consult $(next_round $k)" >> "$D/lane.log"; echo "started lane-$k"; }
case $cmd in
  new) k=${1:?name}; goal=${2:?goal}; par=${3:-2}; land=${4:-false}; D=$ORG_ROOT/lanes/$k
    mkdir -p "$D"/{reports,prompts,logs,rounds,wt,target,renders/owner}
    python3 - "$D" "$k" "$par" "$land" <<'PY'
import json,sys; D,k,par,land=sys.argv[1:]
json.dump({"name":k,"branch_prefix":f"lane/{k}","max_parallel":int(par),"may_land":land=="true"},open(f"{D}/lane.json","w"),indent=2)
PY
    for t in context supervisor-brief agent-rules owner-answers rulings; do
      [ -f "$D/$t.md" ] || sed -e "s|{{LANE}}|$k|g" -e "s|{{LANE_GOAL}}|$goal|g" -e "s|{{LANE_ROOT}}|$D|g" -e "s|{{ORG_ROOT}}|$ORG_ROOT|g" "$KIT/../templates/lane/$t.md" > "$D/$t.md"; done
    cd "$REPO"; git show-ref -q --verify "refs/heads/lane/$k/integration" || git branch "lane/$k/integration" "$MAIN"
    [ -e "$D/int/.git" ] || git worktree add -q "$D/int" "lane/$k/integration"
    [ -n "$U" ] && chown -R "$U:$U" "$D" "$REPO/.git"
    echo "lane $k created at $D — edit $D/supervisor-brief.md (the lane GOAL section) before starting";;
  start) for k in ${@:-$(all)}; do start_one "$k"; done;;
  restart) for k in ${@:-$(all)}; do D=$ORG_ROOT/lanes/$k
      for q in $(pgrep -f "supervise.py $D"); do kill "$q"; done; sleep 2; tmux kill-session -t "lane-$k" 2>/dev/null || true
      start_one "$k"; done;;
  stop) touch "$ORG_ROOT/lanes/${1:?name}/STOP"; echo "STOP set for $1";;
  status) for k in $(all); do echo "== $k: $(tail -1 "$ORG_ROOT/lanes/$k/lane.log" 2>/dev/null)"; done
    pgrep -af "claude -p" | grep -oE "You are agent .[a-z0-9-]+." | sort -u;;
  gc) for k in ${@:-$(all)}; do D=$ORG_ROOT/lanes/$k
      P=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('branch_prefix','lane/'+d['name']))" "$D/lane.json")
      before=$(du -sk "$D" | cut -f1); nw=0
      merged=$(cd "$REPO" && git branch --merged "$P/integration" --format='%(refname:short)')
      for w in "$D"/wt/*/; do [ -d "$w" ] || continue; n=$(basename "$w")
        echo "$merged" | grep -qxF "$P/$n" || continue
        if pgrep -f "cd $D/wt/$n &&" >/dev/null; then echo "  keep wt/$n (agent running)"; continue; fi
        (cd "$REPO" && git worktree remove --force "$w") && { rm -rf "$D/target/$n"; nw=$((nw+1)); echo "  removed wt/$n + target/$n"; }
      done
      nr=$(find "$D/renders" -type f -mtime +14 -not -path "$D/renders/owner/*" -print -delete 2>/dev/null | wc -l | tr -d ' ')
      echo "gc $k: removed $nw worktree(s), $nr render(s) older than 14 days; freed $(( before - $(du -sk "$D" | cut -f1) )) KB"
    done; (cd "$REPO" && git worktree prune);;
  *) echo "unknown command $cmd"; exit 2;;
esac
