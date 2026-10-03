#!/usr/bin/env bash
# The overseer's event feed: prints every noteworthy NEW line from every lane log (offsets persist across
# restarts, so a restarted watcher never skips events), plus a worker-auth probe every N minutes.
# The overseeing Claude session runs:  ssh <host> 'bash <ORG_ROOT>/lane-events.sh <ORG_ROOT>'  inside a Monitor.
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
U=$(j 'd.get("worker_user") or ""'); CL=$(j 'd.get("claude_bin","claude")'); PI=$(j 'd.get("auth_probe_interval_s",1800)')
# What counts as an event (scripts/test-supervise.sh reads this line). Log lines start "YYYY-MM-DD HH:MM" or "HH:MM".
EVENTS=" start on |finished|ASK_OWNER|MERGE|LAND|DONE|FAILED|exiting|DIVERGED|refused|usage limit|restarted|KILL|NO ACTIONABLE BLOCK|REPORT OVERDUE"
S=$ORG_ROOT/logs/lane-events.state; mkdir -p $ORG_ROOT/logs
declare -A N
files() { ls "$ORG_ROOT"/lanes/*/lane.log "$ORG_ROOT"/logs/git-sync.log "$ORG_ROOT"/logs/*.run.log 2>/dev/null; }
for f in $(files); do N[$f]=$(grep -F "$f " "$S" 2>/dev/null | tail -1 | cut -d' ' -f2); [ -z "${N[$f]}" ] && N[$f]=$(wc -l < "$f"); done
echo "lane-events watching $(date -u '+%F %H:%M')"
LASTPROBE=0
while true; do
  for f in $(files); do c=$(wc -l < "$f"); [ -z "${N[$f]}" ] && N[$f]=0
    if [ "$c" -gt "${N[$f]}" ]; then
      sed -n "$((N[$f]+1)),${c}p" "$f" | grep -E "$EVENTS" \
        | sed "s|^|$(basename "$(dirname "$f")"): |" | cut -c1-260
    fi; N[$f]=$c; done
  for f in "${!N[@]}"; do echo "$f ${N[$f]}"; done > "$S"
  if [ $(( $(date +%s) - LASTPROBE )) -ge "$PI" ]; then LASTPROBE=$(date +%s)
    pre=""; [ -n "$U" ] && pre="sudo -u $U -H"
    out=$(cd /tmp && $pre timeout 300 "$CL" -p "reply with just OK" --model sonnet 2>&1 | tail -3)
    # alert only on a REAL auth error — a slow reply on a busy box is not a failure
    if echo "$out" | grep -qiE "oauth|authenticat|expired|401|unauthorized|log ?in"; then echo "$(date -u '+%F %H:%M') WORKER AUTH FAILED: $(echo $out | cut -c1-120)"; fi
  fi
  sleep 60
done
