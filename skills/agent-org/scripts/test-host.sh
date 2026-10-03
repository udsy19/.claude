#!/usr/bin/env bash
# Offline test of the host scripts (bootstrap-host.sh, lanes.sh, git-sync.sh, state-snapshot.sh, build-queue) in a
# throw-away sandbox: a temp HOME, a temp ORG_ROOT, a repo with a bare origin, and fakes for uname, id, useradd,
# chown, crontab, launchctl, systemctl, tmux, timeout, flock, claude, codex and cargo. PATH holds ONLY those fakes
# plus links to a fixed list of real tools, so the real crontab, launchctl, systemctl, sudo and useradd are
# unreachable: nothing here touches the machine (no cron, users, launch agents, logins or real pushes).
#   bash scripts/test-host.sh          (KEEP=1 keeps the sandbox for inspection)
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd); SC=$KIT/scripts
SB=$(mktemp -d "${TMPDIR:-/tmp}/host-test.XXXXXX"); SB=$(cd "$SB" && pwd -P)
FAKES=$SB/fakes; REAL=$SB/real; LOG=$SB/calls.log
PASS=0; FAIL=0
cleanup() { [ "${KEEP:-}" = 1 ] && echo "sandbox kept: $SB" || rm -rf "$SB"; }
trap cleanup EXIT
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_NOSYSTEM=1 SB LOG
echo "== sandbox $SB"

# ── real tools the scripts may use (linked one by one), and the fakes ──
mkdir -p "$REAL" "$FAKES" "$SB/users"
for t in bash sh env git python3 rsync mkdir cp chmod ln install cat grep sed awk head tail tr cut sort uniq xargs \
         basename dirname date mktemp rm mv ls touch seq sleep du find wc ps pgrep kill cksum tee readlink pwd true false; do
  p=$(command -v "$t") && ln -s "$p" "$REAL/$t"
done
fake() { printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n%s\n' "$1" "$2" > "$FAKES/$1"; chmod +x "$FAKES/$1"; }
fake uname     'echo "${FAKE_OS:-Linux}"'
fake id        'case "$1" in -u) echo "${FAKE_UID:-1000}";; -un) echo "${FAKE_USER:-tester}";; *) [ -f "$SB/users/$1" ];; esac'
fake useradd   'for a; do n=$a; done; touch "$SB/users/$n"'
fake chown     'exit 0'
fake crontab   'u=${FAKE_USER:-tester}; [ "$1" = -u ] && { u=$2; shift 2; }
case "$1" in -l) [ -f "$SB/cron.$u" ] && cat "$SB/cron.$u" || { echo "crontab: no crontab for $u" >&2; exit 1; };;
  -) cat > "$SB/cron.$u.tmp" && mv "$SB/cron.$u.tmp" "$SB/cron.$u";; esac'
fake launchctl 'exit 0'
fake systemctl '[ "$*" = "--user show-environment" ] && exit "${FAKE_SYSTEMD_RC:-0}"; exit 0'
fake tmux      'case "$1" in has-session) [ -f "$SB/tmux.$3" ];; new-session) touch "$SB/tmux.$4";; esac'
fake timeout   'shift; exec "$@"'
fake flock     'exit 0'
fake claude    'case "$*" in *"reply with just OK"*) echo OK;; esac'
fake codex     'echo "Logged in (fake)"'
# PATH = the fakes (minus any named) + the real-tool links. Nothing else.
path_without() { local d=$SB/path-$(echo "x $*" | cksum | cut -d' ' -f1); mkdir -p "$d"
  for f in "$FAKES"/*; do case " $* " in *" $(basename "$f") "*) ;; *) ln -sf "$f" "$d/";; esac; done; echo "$d:$REAL"; }
export PATH; PATH=$(path_without)

# ── a project repo with a bare origin ──
export HOME=$SB/home; mkdir -p "$HOME"
git init -q --bare "$SB/origin.git"
git init -q -b main "$SB/repo" && cd "$SB/repo" || exit 2
mkdir -p vault && printf '# Agents\n' > vault/AGENTS.md && git add -A && git commit -qm init
git remote add origin "$SB/origin.git" && git push -q origin main

# org.json for one case: base values, then a python dict literal of overrides
ORG=$SB/org
mkorg() { rm -rf "$ORG" "$SB"/cron.* "$SB"/tmux.* "$SB/srvbin" "$HOME/.claude" "$HOME/Library" "$HOME/.config"; : > "$LOG"
  local over=${1:-}; [ -n "$over" ] || over='{}'
  mkdir -p "$ORG"; python3 - "$ORG/org.json" "$SB" "$over" <<'PY'
import json,sys
o,sb,over=sys.argv[1:]
d={"project":"T","repo":f"{sb}/repo","main_branch":"main","runtime":"local","worker_user":"",
   "claude_bin":"claude","supervisor":{"backend":"claude","model":"opus"},
   "worker_models":{"opus":"opus"},"default_worker_model":"opus",
   "build_queue":{"slots":2,"wrap":["cargo build","cargo test"]},"sync":{"branch_globs":["lane/*"],"interval_s":1}}
d.update(eval(over)); json.dump(d,open(o,"w"),indent=1)
PY
}
boot() { : > "$LOG"; (cd "$SB" && env "$@" bash "$SC/bootstrap-host.sh" "$ORG") > "$SB/boot.out" 2>&1; echo $? > "$SB/boot.rc"; }
rc() { cat "$SB/boot.rc"; }

echo "== B1 runtime modes: one user per mode, no sudo, no re-owning"
check "no sudo, no recursive chown, no \$USER in the host scripts" \
  "! grep -nE '^[^#]*(sudo |chown -R|\\\$USER)' '$SC/bootstrap-host.sh' '$SC/lanes.sh' '$SC/git-sync.sh' '$SC/state-snapshot.sh' '$SC/build-queue'"

mkorg; boot FAKE_OS=Darwin FAKE_UID=501 FAKE_USER=tester
check "local macOS as me: host ready, exit 0" "[ $(rc) = 0 ] && has '$SB/boot.out' 'host ready (local, as tester)'"
check "local: build queue in ORG_ROOT/bin, nothing under /srv" "[ -x '$ORG/bin/build-queue' ] && [ -L '$ORG/bin/cargo' ] && ! has '$SB/boot.out' /srv"
check "local: the two skills land in my own ~/.claude/skills" "[ -f '$HOME/.claude/skills/pre-edit-scan/SKILL.md' ] && [ -f '$HOME/.claude/skills/memory-discipline/SKILL.md' ]"
check "local: only those two skills (no global config copied)" "[ \$(ls '$HOME/.claude/skills' | wc -l) -eq 2 ] && [ ! -e '$HOME/.claude/settings.json' ]"
check "local: no useradd, no chown" "! grep -qE '^(useradd|chown) ' '$LOG'"
check "local: git-sync started as me in tmux" "has '$LOG' 'tmux new-session -d -s gitsync'"
check "no safe.directory anywhere" "! git config --global --get-all safe.directory >/dev/null"

mkorg "{'worker_user':'agent'}"; boot FAKE_OS=Darwin FAKE_UID=501
check "macOS + worker_user: refused with the Linux-only message" "[ $(rc) = 2 ] && has '$SB/boot.out' 'worker_user is Linux-only'"
mkorg "{'worker_user':'agent'}"; boot FAKE_OS=Linux FAKE_UID=1000
check "local + worker_user: refused (local runs as you)" "[ $(rc) = 2 ] && has '$SB/boot.out' 'runtime \"local\" runs the org as you'"
mkorg; boot FAKE_OS=Linux FAKE_UID=0 FAKE_USER=root
check "Linux root + runtime local: refused, names the fix" \
  "[ $(rc) = 2 ] && has '$SB/boot.out' 'claude will not skip permissions as root; set a worker user or run as a normal user'"
mkorg "{'runtime':'mars'}"; boot
check "unknown runtime: refused" "[ $(rc) = 2 ] && has '$SB/boot.out' 'must be \"local\" or \"remote\"'"

mkorg "{'runtime':'remote','worker_user':'agent','bin_dir':'$SB/srvbin'}"; boot FAKE_UID=0 FAKE_USER=root
check "remote phase 1 (root): creates the worker user" "[ $(rc) = 0 ] && has '$LOG' 'useradd -m -s /bin/bash agent'"
check "remote phase 1: writes the bin dir" "[ -x '$SB/srvbin/build-queue' ] && [ -L '$SB/srvbin/cargo' ]"
check "remote phase 1: installs the WORKER's crontab" "has '$SB/cron.agent' 'state-snapshot.sh' && [ ! -f '$SB/cron.root' ]"
check "remote phase 1: hands ORG_ROOT to the worker, not recursively, never .git" \
  "has '$LOG' 'chown agent:agent $ORG $ORG/org.json' && ! grep -q -- '-R' '$LOG' && ! grep '^chown' '$LOG' | grep -q '\.git'"
check "remote phase 1: stops there and says what to run as the worker" \
  "has '$SB/boot.out' 'phase 1 done. Next, as agent' && ! has '$LOG' 'tmux new-session'"
boot FAKE_UID=1001 FAKE_USER=agent
check "remote phase 2 (as agent): host ready" "[ $(rc) = 0 ] && has '$SB/boot.out' 'host ready (remote, as agent)'"
check "remote phase 2: no useradd/chown, git-sync started as agent" "! grep -qE '^(useradd|chown) ' '$LOG' && has '$LOG' 'tmux new-session -d -s gitsync'"
check "remote phase 2: worker gets exactly the two skills" "[ \$(ls '$HOME/.claude/skills' | wc -l) -eq 2 ]"
boot FAKE_UID=1002 FAKE_USER=bob
check "remote as another non-root user: refused" "[ $(rc) = 2 ] && has '$SB/boot.out' 'runs the org as agent, not bob'"

mkorg "{'supervisor':{'backend':'codex','model':'x'}}"; PATH=$(path_without codex) boot
check "codex supervisor without codex: stops at need, names the install" "[ $(rc) = 3 ] && has '$SB/boot.out' 'MISSING: codex — npm i -g @openai/codex'"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
