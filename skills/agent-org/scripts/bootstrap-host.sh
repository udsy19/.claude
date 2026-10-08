#!/usr/bin/env bash
# Prepare a host to run the org.   usage: bootstrap-host.sh [ORG_ROOT]      (default ~/agent-org)
# Idempotent. Installs nothing it does not need; never handles secrets (logins are the owner's, interactive).
# ONE user runs the org (org.json "runtime"):
#   local  (macOS/Linux): you, as yourself. No worker user, no sudo, no /srv; the build queue goes in ORG_ROOT/bin.
#   remote (Linux VPS):   phase 1 as root creates worker_user, writes /srv/bin and the worker's crontab, then exits;
#                         phase 2 as worker_user sets up everything else (loop, git-sync, snapshot, builds).
# Nothing here runs sudo or re-owns a repository; the repo must belong to the user that runs the org.
set -e
ORG_ROOT=${1:-$HOME/agent-org}; KIT=$(cd "$(dirname "$0")" && pwd); CFG=$ORG_ROOT/org.json
[ -f "$CFG" ] || { echo "write $CFG first (from org.example.json)"; exit 2; }
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
U=$(j 'd.get("worker_user") or ""'); REPO=$(j 'd["repo"]'); SUPB=$(j 'd["supervisor"]["backend"]')
CL=$(j 'd.get("claude_bin") or "claude"')
PM=$(j 'd["worker_models"][d.get("default_worker_model") or next(iter(d["worker_models"]))]')
MODE=$(j '{"vps": "remote"}.get(d.get("runtime") or "local", d.get("runtime") or "local")')
case $MODE in local|remote) ;; *) echo "org.json \"runtime\" must be \"local\" or \"remote\", not \"$MODE\""; exit 2;; esac
OS=$(uname); ME=$(id -un); MYUID=$(id -u)
if [ -n "$U" ] && [ "$OS" = Darwin ]; then
  echo "worker_user is Linux-only (useradd). On macOS set \"worker_user\": \"\" and run the agents as yourself."; exit 2; fi
if [ "$MODE" = local ] && [ -n "$U" ]; then
  echo "runtime \"local\" runs the org as you: set \"worker_user\": \"\" (a worker user is for runtime \"remote\")"; exit 2; fi
if [ "$MYUID" = 0 ] && [ -z "$U" ]; then
  echo "refused: claude will not skip permissions as root; set a worker user or run as a normal user"; exit 2; fi
BIN=$(j 'd.get("bin_dir") or ""'); [ -n "$BIN" ] || { if [ "$MODE" = remote ]; then BIN=/srv/bin; else BIN=$ORG_ROOT/bin; fi; }
need() { command -v "$1" >/dev/null || { echo "MISSING: $1 — $2"; MISSING=1; }; }
install_bin() {   # the build queue wrapper + one symlink per wrapped tool (org.json build_queue.wrap)
  tools=$(j '" ".join(sorted({w.split()[0] for w in d.get("build_queue",{}).get("wrap",[])}))')
  [ -n "$tools" ] || return 0
  command -v flock >/dev/null || { echo "MISSING: flock (the build queue needs it) — util-linux (Linux) / brew install flock (mac)"; exit 3; }
  mkdir -p "$BIN"; install -m 755 "$KIT/build-queue" "$BIN/build-queue"
  for t in $tools; do [ -e "$BIN/$t" ] || ln -s "$BIN/build-queue" "$BIN/$t"; done
  echo "build queue in $BIN wraps: $tools"
}
O=$(printf '%q' "$ORG_ROOT")
TICK="$O/lanes.sh $O gc >> $O/logs/gc.log 2>&1; $O/state-snapshot.sh $O >> $O/logs/state-snapshot.log 2>&1"
TAG="# agent-org $ORG_ROOT"   # hourly: disk GC (merged, finished worktrees + old renders), then the lane-state snapshot
LABEL=agent-org.$(printf %s "$ORG_ROOT" | cksum | cut -d' ' -f1)
cron_edit() {     # cron_edit add|drop [-u user]: replace/remove ONLY this org's kit lines (tagged, or the untagged one
  local mode=$1; shift  #                     older kits wrote for this ORG_ROOT); every other line is kept as is
  local cur; cur=$(crontab "$@" -l 2>/dev/null) || cur=""   # "no crontab" is not an error here
  local new; new=$(printf '%s\n' "$cur" | python3 -c 'import sys
tag, legacy, mode, tick = sys.argv[1:]
for l in sys.stdin.read().splitlines():
    if not (l.endswith(tag) or ("# agent-org" not in l and legacy in l)): print(l)
if mode == "add": print("7 * * * * " + tick + " " + tag)' "$TAG" "$O/state-snapshot.sh $O " "$mode" "$TICK")
  [ "$new" = "$cur" ] && return 0
  printf '%s\n' "$new" | crontab "$@" -
  [ "$mode" = drop ] || crontab "$@" -l 2>/dev/null | grep -qF -- "$TAG" || { echo "the hourly cron line did not land — check crontab $* -l"; exit 4; }
}
schedule() {      # the hourly job, run by the org's own user
  if [ "$OS" = Darwin ]; then   # launchd.plist(5): unlike cron, a job missed while asleep runs on wake (laptops)
    local p=$HOME/Library/LaunchAgents/$LABEL.plist; mkdir -p "$(dirname "$p")"
    python3 -c 'import plistlib,sys
plistlib.dump({"Label": sys.argv[2], "ProgramArguments": ["/bin/bash", "-c", sys.argv[3]],
  "EnvironmentVariables": {"PATH": sys.argv[4]}, "StartCalendarInterval": {"Minute": 7}}, open(sys.argv[1], "wb"))' \
      "$p" "$LABEL" "$TICK" "$PATH"
    launchctl bootout "gui/$MYUID/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$MYUID" "$p" || { echo "launchctl bootstrap failed for $p"; exit 4; }
    command -v crontab >/dev/null && cron_edit drop          # an older kit's cron line would run the job twice
    echo "hourly job: launchd agent $LABEL"
  elif command -v crontab >/dev/null; then cron_edit add; echo "hourly job: crontab"
  elif command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
    local d=$HOME/.config/systemd/user; mkdir -p "$d"   # systemd.timer(5): Persistent= catches up missed runs
    local x; x=$(printf '%s' "$TICK" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/$$/g' -e 's/%/%%/g')
    printf '[Unit]\nDescription=agent-org hourly gc + lane-state snapshot (%s)\n[Service]\nType=oneshot\nEnvironment="PATH=%s"\nExecStart=/bin/bash -c "%s"\n' \
      "$(printf %s "$ORG_ROOT" | sed 's/%/%%/g')" "$PATH" "$x" > "$d/$LABEL.service"
    printf '[Unit]\nDescription=agent-org hourly (%s)\n[Timer]\nOnCalendar=*-*-* *:07:00\nPersistent=true\n[Install]\nWantedBy=timers.target\n' \
      "$(printf %s "$ORG_ROOT" | sed 's/%/%%/g')" > "$d/$LABEL.timer"
    if ! { systemctl --user daemon-reload && systemctl --user enable --now "$LABEL.timer"; }; then echo "systemctl --user enable failed"; exit 4; fi
    echo "hourly job: systemd --user timer $LABEL"
  else
    tmux has-session -t "$LABEL" 2>/dev/null || tmux new-session -d -s "$LABEL" "while :; do bash -c $(printf %q "$TICK"); sleep 3600; done"
    echo "hourly job: tmux loop $LABEL (WARN: no crontab, launchd or systemd --user; it stops at reboot — re-run this script)"
  fi
}

if [ "$MYUID" = 0 ]; then   # ── remote, phase 1 (root): the user, its bin dir, its crontab. Then hand over. ──
  [ "$MODE" = remote ] || { echo "refused: claude will not skip permissions as root; set a worker user or run as a normal user"; exit 2; }
  if ! id "$U" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$U" || { echo "could not create worker user $U"; exit 2; }
    echo "created worker user $U (claude refuses --dangerously-skip-permissions as root)"; fi
  mkdir -p "$ORG_ROOT" && chown "$U:$U" "$ORG_ROOT" "$CFG"    # the org root is the worker's; nothing recursive
  install_bin
  if command -v crontab >/dev/null; then cron_edit add -u "$U"
  else echo "no crontab: phase 2 will install a systemd --user timer (or a tmux loop)"
    command -v loginctl >/dev/null && loginctl enable-linger "$U"; fi   # user timers run without a login session
  if [ -d "$REPO/.git" ]; then
    own=$(python3 -c 'import os,pwd,sys;print(pwd.getpwuid(os.stat(sys.argv[1]).st_uid).pw_name)' "$REPO/.git")
    [ "$own" = "$U" ] || echo "WARN: $REPO belongs to $own, not $U — clone it as $U (the org never re-owns a repository)"
  fi
  echo "phase 1 done. Next, as $U (not root):  su - $U -c 'bash $(printf %q "$KIT/bootstrap-host.sh") $(printf %q "$ORG_ROOT")'"
  echo "then log $U in yourself:  su - $U -c claude  → /login"
  exit 0
fi
if [ "$MODE" = remote ] && [ -n "$U" ] && [ "$ME" != "$U" ]; then
  echo "refused: runtime \"remote\" runs the org as $U, not $ME — run phase 1 as root, then this script as $U"; exit 2; fi

# ── local, or remote phase 2: everything below runs as the one user that runs the org ──
need git "install git"; need tmux "install tmux"; need python3 "install python3"; need rsync "install rsync"
need "$CL" "npm i -g @anthropic-ai/claude-code   (then log in: claude → /login); or fix claude_bin in org.json"
[ "$SUPB" = codex ] && need codex "npm i -g @openai/codex   (then: codex login --device-auth)"
[ -n "$MISSING" ] && { echo "install the missing tools, then re-run"; exit 3; }
case $CL in /*) ;; *) echo "NOTE: claude_bin \"$CL\" is not absolute; set it to $(command -v "$CL") in org.json (workers run with worker_env.PATH, which may not find it)";; esac
# isolation (docs/isolation.md): agents run inside the sandbox runtime; supervise.py refuses to start without it
ISO=$(j '(d.get("isolation") or {}).get("mode", "srt")')
if [ "$ISO" = srt ]; then
  SRTB=$(j '(d.get("isolation") or {}).get("srt_bin", "srt")')
  command -v "$SRTB" >/dev/null || echo "WARN: isolation: the sandbox runtime ($SRTB) is not installed — lanes refuse to start until it is: npm i -g @anthropic-ai/sandbox-runtime"
  if [ "$OS" = Linux ]; then
    for t in bwrap socat rg; do command -v "$t" >/dev/null || echo "WARN: isolation: $t is missing — apt-get install bubblewrap socat ripgrep"; done
    [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ] && \
      echo "WARN: isolation: this kernel blocks bubblewrap's user namespaces (Ubuntu 24.04+) — as root, add the bwrap AppArmor profile in docs/isolation.md"
  fi
else
  echo "WARN: isolation.mode is \"$ISO\": agents run UNSANDBOXED, with everything $ME can read and write (docs/isolation.md)"
fi
TOK=$(j '(d.get("isolation") or {}).get("auth_token_file") or ""'); [ -n "$TOK" ] || TOK=$ORG_ROOT/secrets/claude-oauth-token
mkdir -p "$(dirname "$TOK")" && chmod 700 "$(dirname "$TOK")"
[ -s "$TOK" ] || echo "NOTE: worker auth: agents get their own HOME, so they authenticate with a token: run \`claude setup-token\` and save the token to $TOK (chmod 600)"
mkdir -p "$ORG_ROOT"/{lanes,logs,templates,locks}
cp "$KIT"/{supervise.py,lane-metrics.py,git-sync.sh,state-snapshot.sh,lane-events.sh,lanes.sh} "$ORG_ROOT/"; chmod +x "$ORG_ROOT"/*.sh
cp -R "$KIT/../templates/lane" "$ORG_ROOT/templates/"          # lanes.sh in ORG_ROOT fills new lanes from these
if [ "$MODE" = local ] || [ -w "$BIN" ]; then install_bin; fi   # remote: root installed it in phase 1
# the project rules require these two skills; nothing else of the owner's global config is installed here
for s in pre-edit-scan memory-discipline; do
  src="$KIT/../../$s/SKILL.md"; dst="$HOME/.claude/skills/$s"
  if [ -e "$dst" ]; then continue; fi
  if [ -f "$src" ]; then mkdir -p "$dst" && cp "$src" "$dst/" && echo "installed skill $s for $ME"
  else echo "WARN: skill $s not found beside the kit ($src) — install it into $dst by hand"; fi
done
# continuous services
tmux has-session -t gitsync 2>/dev/null || tmux new-session -d -s gitsync "$(printf '%q ' "$ORG_ROOT/git-sync.sh" "$ORG_ROOT")"
if [ "$MODE" = remote ] && command -v crontab >/dev/null; then   # phase 1 (root) wrote it
  crontab -l 2>/dev/null | grep -qF -- "$TAG" || { echo "no hourly line for $ORG_ROOT in $ME's crontab — re-run phase 1 as root"; exit 4; }
else schedule; fi
# login checks (report, never perform); timed in python: stock macOS has no GNU timeout
to() { python3 -c 'import subprocess,sys
try: sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)
except subprocess.TimeoutExpired: print("no answer in %ss" % sys.argv[1]); sys.exit(124)' "$@"; }
echo "worker claude: $(cd /tmp && to 120 "$CL" -p 'reply with just OK' --model "$PM" 2>&1 | tail -1)"
[ "$SUPB" = codex ] && echo "codex: $(codex login status 2>&1 | head -1)"
echo "host ready ($MODE, as $ME). Next: lanes.sh $ORG_ROOT new <lane> \"<goal>\" …  then  lanes.sh $ORG_ROOT start"
