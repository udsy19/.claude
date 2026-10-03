#!/usr/bin/env bash
# Prepare a host (local Mac/Linux or a VPS) to run the org.   usage: bootstrap-host.sh <ORG_ROOT>
# Idempotent. Installs nothing it does not need; never handles secrets (logins are the owner's, interactive).
set -e
ORG_ROOT=${1:?ORG_ROOT}; KIT=$(cd "$(dirname "$0")" && pwd); CFG=$ORG_ROOT/org.json
[ -f "$CFG" ] || { echo "write $CFG first (from org.example.json)"; exit 2; }
j() { python3 -c "import json,sys;d=json.load(open('$CFG'));print(eval(sys.argv[1]))" "$1"; }
U=$(j 'd.get("worker_user") or ""'); REPO=$(j 'd["repo"]'); SUPB=$(j 'd["supervisor"]["backend"]')
need() { command -v "$1" >/dev/null || { echo "MISSING: $1 — $2"; MISSING=1; }; }
need git "install git"; need tmux "install tmux"; need python3 "install python3"; need flock "util-linux (Linux) / brew install flock (mac)"
need rsync "install rsync"; need claude "npm i -g @anthropic-ai/claude-code   (then log in: claude → /login)"
[ "$SUPB" = codex ] && need codex "npm i -g @openai/codex   (then: codex login --device-auth)"
[ -n "$MISSING" ] && { echo "install the missing tools, then re-run"; exit 3; }
if [ -n "$U" ] && ! id "$U" >/dev/null 2>&1; then useradd -m -s /bin/bash "$U"; echo "created worker user $U (claude refuses --dangerously-skip-permissions as root)"; fi
mkdir -p "$ORG_ROOT"/{lanes,logs} /srv/bin 2>/dev/null || mkdir -p "$ORG_ROOT"/{lanes,logs}
cp "$KIT"/{supervise.py,lane-metrics.py,git-sync.sh,state-snapshot.sh,lane-events.sh,lanes.sh} "$ORG_ROOT/"; chmod +x "$ORG_ROOT"/*.sh
if [ -w /srv/bin ]; then install -m 755 "$KIT/build-queue" /srv/bin/build-queue
  python3 - "$CFG" <<'PY'
import json,sys,os
d=json.load(open(sys.argv[1])); tools={w.split()[0] for w in d.get("build_queue",{}).get("wrap",[])}
for t in tools:
    p=f"/srv/bin/{t}"
    if not os.path.exists(p): os.symlink("/srv/bin/build-queue",p)
print("build queue wraps:", ", ".join(sorted(tools)) or "nothing")
PY
fi
[ -n "$U" ] && chown -R "$U:$U" "$ORG_ROOT" "$REPO/.git" 2>/dev/null
# continuous services
tmux has-session -t gitsync 2>/dev/null || tmux new-session -d -s gitsync "$ORG_ROOT/git-sync.sh $ORG_ROOT"
# hourly: disk GC (merged, finished worktrees + old renders), then the lane-state snapshot
( crontab -l 2>/dev/null | grep -v state-snapshot; echo "7 * * * * $ORG_ROOT/lanes.sh $ORG_ROOT gc >> $ORG_ROOT/logs/gc.log 2>&1; $ORG_ROOT/state-snapshot.sh $ORG_ROOT >> $ORG_ROOT/logs/state-snapshot.log 2>&1" ) | crontab -
# login checks (report, never perform)
pre=""; [ -n "$U" ] && pre="sudo -u $U -H"
echo "worker claude: $(cd /tmp && $pre timeout 120 claude -p 'reply with just OK' --model sonnet 2>&1 | tail -1)"
[ "$SUPB" = codex ] && echo "codex: $(codex login status 2>&1 | head -1)"
echo "host ready. Next: lanes.sh $ORG_ROOT new <lane> \"<goal>\" …  then  lanes.sh $ORG_ROOT start"
