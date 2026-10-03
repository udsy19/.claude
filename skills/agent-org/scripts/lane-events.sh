#!/usr/bin/env bash
# The overseer's event feed: prints every noteworthy NEW line from every lane log (offsets persist across
# restarts, so a restarted watcher never skips events), plus a worker-auth probe every N minutes.
# The overseeing Claude session runs:  ssh <host> 'bash <ORG_ROOT>/lane-events.sh <ORG_ROOT>'  inside a Monitor.
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
CL=$(j 'd.get("claude_bin","claude")'); PI=$(j 'd.get("auth_probe_interval_s",1800)')
PM=$(j 'd["worker_models"][d.get("default_worker_model") or next(iter(d["worker_models"]))]')
# What counts as an event (scripts/test-supervise.sh reads this line). Log lines start "YYYY-MM-DD HH:MM" or "HH:MM".
EVENTS=" start on |finished|ASK_OWNER|MERGE|LAND|DONE|FAILED|exiting|DIVERGED|refused|usage limit|restarted|KILL|NO ACTIONABLE BLOCK|REPORT OVERDUE|UNFILLED|SUPERVISOR ERROR"
S=$ORG_ROOT/logs/lane-events.state; mkdir -p "$ORG_ROOT/logs"
# Offsets live in $S ("<path> <lines>" per line), not in a bash-4 associative array: macOS ships bash 3.2.
files() { ls "$ORG_ROOT"/lanes/*/lane.log "$ORG_ROOT"/logs/git-sync.log "$ORG_ROOT"/logs/*.run.log 2>/dev/null; }
offset() { awk -v f="$1" '{n=$NF; sub(/ [0-9]+$/, ""); if ($0 == f) c=n} END {print c}' "$S" 2>/dev/null; }
echo "lane-events watching $(date -u '+%F %H:%M')"
LASTPROBE=0; FIRST=1
while true; do
  : > "$S.tmp"
  while IFS= read -r f; do [ -n "$f" ] || continue
    c=$(wc -l < "$f" | tr -d ' '); n=$(offset "$f")
    [ -z "$n" ] && { [ "$FIRST" = 1 ] && n=$c || n=0; }   # at start: skip history; a lane added later: show all
    if [ "$c" -gt "$n" ]; then
      sed -n "$((n+1)),${c}p" "$f" | grep -E "$EVENTS" \
        | sed "s|^|$(basename "$(dirname "$f")"): |" | cut -c1-260
    fi
    echo "$f $c" >> "$S.tmp"
  done <<EOF
$(files)
EOF
  mv "$S.tmp" "$S"; FIRST=0
  if [ $(( $(date +%s) - LASTPROBE )) -ge "$PI" ]; then LASTPROBE=$(date +%s)
    out=$(cd /tmp && timeout 300 "$CL" -p "reply with just OK" --model "$PM" 2>&1 | tail -3)   # as this user: one user runs the org
    # alert only on a REAL auth error — a slow reply on a busy box is not a failure
    if echo "$out" | grep -qiE "oauth|authenticat|expired|401|unauthorized|log ?in"; then echo "$(date -u '+%F %H:%M') WORKER AUTH FAILED: $(echo $out | cut -c1-120)"; fi
  fi
  sleep 60
done
