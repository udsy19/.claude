#!/usr/bin/env bash
# Prepare a host (local Mac/Linux or a VPS) to run the org.   usage: bootstrap-host.sh <ORG_ROOT>
# Idempotent. Installs nothing it does not need; never handles secrets (logins are the owner's, interactive).
set -e
ORG_ROOT=${1:?ORG_ROOT}; KIT=$(cd "$(dirname "$0")" && pwd); CFG=$ORG_ROOT/org.json
[ -f "$CFG" ] || { echo "write $CFG first (from org.example.json)"; exit 2; }
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
U=$(j 'd.get("worker_user") or ""'); REPO=$(j 'd["repo"]'); SUPB=$(j 'd["supervisor"]["backend"]')
CL=$(j 'd.get("claude_bin") or "claude"')
PM=$(j 'd["worker_models"][d.get("default_worker_model") or next(iter(d["worker_models"]))]')
if [ -n "$U" ] && [ "$(uname)" = Darwin ]; then
  echo "worker_user is Linux-only (useradd). On macOS set \"worker_user\": \"\" and run the agents as yourself."; exit 2; fi
need() { command -v "$1" >/dev/null || { echo "MISSING: $1 — $2"; MISSING=1; }; }
need git "install git"; need tmux "install tmux"; need python3 "install python3"; need rsync "install rsync"
need timeout "coreutils (Linux) / brew install coreutils (mac)"
need "$CL" "npm i -g @anthropic-ai/claude-code   (then log in: claude → /login); or fix claude_bin in org.json"
[ "$SUPB" = codex ] && need codex "npm i -g @openai/codex   (then: codex login --device-auth)"
[ -n "$MISSING" ] && { echo "install the missing tools, then re-run"; exit 3; }
case $CL in /*) ;; *) echo "NOTE: claude_bin \"$CL\" is not absolute; set it to $(command -v "$CL") in org.json (workers run with worker_env.PATH, which may not find it)";; esac
if [ -n "$U" ] && ! id "$U" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$U" || { echo "could not create worker user $U (run as root)"; exit 2; }
  echo "created worker user $U (claude refuses --dangerously-skip-permissions as root)"; fi
mkdir -p "$ORG_ROOT"/{lanes,logs,templates} /srv/bin 2>/dev/null || mkdir -p "$ORG_ROOT"/{lanes,logs,templates}
cp "$KIT"/{supervise.py,lane-metrics.py,git-sync.sh,state-snapshot.sh,lane-events.sh,lanes.sh} "$ORG_ROOT/"; chmod +x "$ORG_ROOT"/*.sh
cp -R "$KIT/../templates/lane" "$ORG_ROOT/templates/"          # lanes.sh in ORG_ROOT fills new lanes from these
if [ -w /srv/bin ]; then
  command -v flock >/dev/null || { echo "MISSING: flock (the build queue needs it) — util-linux (Linux) / brew install flock (mac)"; exit 3; }
  install -m 755 "$KIT/build-queue" /srv/bin/build-queue
  python3 - "$CFG" <<'PY'
import json,sys,os
d=json.load(open(sys.argv[1])); tools={w.split()[0] for w in d.get("build_queue",{}).get("wrap",[])}
for t in tools:
    p=f"/srv/bin/{t}"
    if not os.path.exists(p): os.symlink("/srv/bin/build-queue",p)
print("build queue wraps:", ", ".join(sorted(tools)) or "nothing")
PY
fi
if [ -n "$U" ]; then
  chown -R "$U:$U" "$ORG_ROOT" "$REPO/.git" || echo "WARN: could not chown $ORG_ROOT and $REPO/.git to $U — agents may be locked out"
  # the project rules require these two skills; the worker user's ~/.claude has none of the owner's config
  UH=$(getent passwd "$U" 2>/dev/null | cut -d: -f6); [ -n "$UH" ] || UH=$(eval echo "~$U")
  case $UH in /*) ;; *) echo "WARN: no home directory for $U — install pre-edit-scan and memory-discipline into its ~/.claude/skills by hand"; UH="";; esac
  [ -n "$UH" ] && for s in pre-edit-scan memory-discipline; do
    src="$KIT/../../$s/SKILL.md"; dst="$UH/.claude/skills/$s"
    if [ -e "$dst" ]; then continue; fi
    if [ -f "$src" ]; then mkdir -p "$dst" && cp "$src" "$dst/" && chown -R "$U:$U" "$UH/.claude" && echo "installed skill $s for $U"
    else echo "WARN: skill $s not found beside the kit ($src) — install it into $dst by hand"; fi
  done
fi
# continuous services
tmux has-session -t gitsync 2>/dev/null || tmux new-session -d -s gitsync "$(printf '%q ' "$ORG_ROOT/git-sync.sh" "$ORG_ROOT")"
# hourly: disk GC (merged, finished worktrees + old renders), then the lane-state snapshot
O=$(printf '%q' "$ORG_ROOT")
( crontab -l 2>/dev/null | grep -v state-snapshot || true
  echo "7 * * * * $O/lanes.sh $O gc >> $O/logs/gc.log 2>&1; $O/state-snapshot.sh $O >> $O/logs/state-snapshot.log 2>&1" ) | crontab -
crontab -l 2>/dev/null | grep -q state-snapshot || { echo "the hourly cron line did not land — check crontab -l"; exit 4; }
# login checks (report, never perform)
pre=""; [ -n "$U" ] && pre="sudo -u $U -H"
echo "worker claude: $(cd /tmp && $pre timeout 120 "$CL" -p 'reply with just OK' --model "$PM" 2>&1 | tail -1)"
[ "$SUPB" = codex ] && echo "codex: $(codex login status 2>&1 | head -1)"
echo "host ready. Next: lanes.sh $ORG_ROOT new <lane> \"<goal>\" …  then  lanes.sh $ORG_ROOT start"
