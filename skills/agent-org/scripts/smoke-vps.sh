#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2329  # checks are eval'd strings that use these names; generated scripts keep literal $
# Remote-mode smoke test on a REAL, DISPOSABLE Linux host (fresh Ubuntu LTS, root over SSH): the things the CI fakes
# stand in for — useradd, crontab -u, a real worker login, real tmux/flock/git — exercised once, end to end.
#
#   smoke-vps.sh <ssh-target> [--resume-from N]      e.g. smoke-vps.sh root@203.0.113.10
#
# Runs locally: ships this config (git archive HEAD) to the host, then runs steps 1–8 there over SSH, each step
# checking its named artefact. Every command's output goes to ./smoke-vps-<UTC stamp>.log (or $SMOKE_LOG).
# SMOKE_EXEC overrides the transport: a command prefix that runs its arguments as root on the target with stdin
# attached (default: ssh -o BatchMode=yes <target>). To keep a shared box untouched, run the steps in a container
# on it: SMOKE_EXEC="ssh -o BatchMode=yes root@HOST docker exec -i <container>" (see docs/smoke-vps.md).
# Exit 0: all steps passed. Exit 10: a step needs a human (the worker login) — do what it says, then re-run with
# --resume-from <step>. Any other exit: that step failed; fix, then --resume-from <step>.
#   1 phase A as root (packages, Claude Code from Anthropic's apt repo, org.json, bootstrap phase 1, the project
#     repo cloned as agent) → STOP for the worker login → phase B as agent (bootstrap phase 2 twice: no-op, probe OK)
#   2 lanes.sh start: refused as root, starts as agent (script supervisor + fake worker from here on)
#   3 one lane, two consults: pid file, MERGE + hub regeneration, LAND of a Plan.md change refused with its report,
#     git-sync pushes lane/*, a repo parked off main is left alone
#   4 restart while an agent runs: adopted; gc keeps its worktree
#   5 the hourly cron line, run by hand: gc + snapshot; the snapshot holds the allowlist only and every org.json key
#   6 build queue: 3 heavy jobs, 2 slots, the third waits; locks in ORG_ROOT/locks; no real binary → exit 127
#   7 ownership: nothing under the repo's .git or ORG_ROOT belongs to anyone but agent
#   8 lanes.sh stop core: no lane process left; git-sync still running
# The host is assumed disposable: it installs packages, creates the user `agent`, and edits root's and agent's state.
set -u
STEPS=8
if [ "${1:-}" = --remote-step ]; then MODE=remote; N=$2; else MODE=local; fi

# ─────────────────────────────────────────── local driver ───────────────────────────────────────────
if [ "$MODE" = local ]; then
  T=${1:?usage: smoke-vps.sh <ssh-target> [--resume-from N]}; FROM=1
  [ "${2:-}" = --resume-from ] && FROM=${3:?--resume-from needs a step number}
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0"); TOP=$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel)
  LOG=${SMOKE_LOG:-$PWD/smoke-vps-$(date -u +%Y%m%dT%H%M%SZ).log}
  say() { printf '%s\n' "$*" | tee -a "$LOG"; }
  read -r -a X <<< "${SMOKE_EXEC:-ssh -o BatchMode=yes -o ConnectTimeout=15 $T}"   # the transport, as words
  say "== smoke-vps $(date -u +%FT%TZ) target=$T via '${X[*]}' kit=$(git -C "$TOP" rev-parse --short HEAD) from step $FROM"
  if [ "$FROM" = 1 ]; then
    say "== shipping the config (git archive HEAD) to /opt/agent-org-config"
    # Plain words only: ssh joins its arguments into one remote command line, so anything quoted would be
    # re-parsed (and with SMOKE_EXEC through docker exec, parsed twice).
    { "${X[@]}" rm -rf /opt/agent-org-config && git -C "$TOP" archive --prefix=opt/agent-org-config/ HEAD | "${X[@]}" tar -x -C / &&
      "${X[@]}" chmod -R a+rX /opt/agent-org-config; } >> "$LOG" 2>&1 || { say "could not run as root on $T via '${X[*]}'"; exit 1; }
  fi
  for n in $(seq "$FROM" "$STEPS"); do
    say "== step $n"
    "${X[@]}" bash -s -- --remote-step "$n" < "$SELF" 2>&1 | tee -a "$LOG"; rc=${PIPESTATUS[0]}
    if [ "$rc" = 10 ]; then say "== step $n needs you (above). Then: $0 $T --resume-from $n"; exit 10; fi
    [ "$rc" = 0 ] || { say "== step $n FAILED (exit $rc). Fix it, then: $0 $T --resume-from $n   (log: $LOG)"; exit 1; }
  done
  say "== all $STEPS steps passed (log: $LOG)"; exit 0
fi

# ─────────────────────────────────────────── on the host (root) ───────────────────────────────────────────
[ "$(id -u)" = 0 ] || { echo "run the remote steps as root"; exit 2; }
KIT=/opt/agent-org-config/skills/agent-org; ORG=/srv/org; REPO=/home/agent/demo; SM=/srv/smoke; ORIGIN=$SM/origin.git
FAIL=0
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; FAIL=1; fi; }
ag() { su - agent -c "$1"; }                      # run as the worker, with its login environment
wait_for() { local _; for _ in $(seq 1 "$2"); do eval "$1" && return 0; sleep 1; done; return 1; }
lanelog() { cat "$ORG/lanes/core/lane.log" 2>/dev/null; }
orgset() { python3 - "$ORG/org.json" "$1" <<'PY'   # orgset '<python dict literal>': merge keys into org.json in place
import ast, json, sys
p = sys.argv[1]; d = json.load(open(p)); d.update(ast.literal_eval(sys.argv[2]))
open(p, "w").write(json.dumps(d, indent=2) + "\n")     # rewritten in place: the owner (agent) is kept
PY
}

case $N in
1) echo "-- phase A (root): packages, Claude Code (apt, https://code.claude.com/docs/en/setup), org.json, bootstrap phase 1"
   export DEBIAN_FRONTEND=noninteractive
   apt-get update -qq && apt-get install -y -qq git tmux python3 rsync jq cron curl gnupg nodejs util-linux procps >/dev/null || exit 1
   if ! command -v claude >/dev/null; then
     install -d -m 0755 /etc/apt/keyrings
     curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc
     gpg --show-keys /etc/apt/keyrings/claude-code.asc | grep -q 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE || { echo "signing key fingerprint mismatch"; exit 1; }
     echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" > /etc/apt/sources.list.d/claude-code.list
     apt-get update -qq && apt-get install -y -qq claude-code >/dev/null || exit 1
   fi
   claude --version
   mkdir -p "$ORG"
   [ -f "$ORG/org.json" ] || python3 - "$ORG/org.json" "$(command -v claude)" <<'PY'
import json, sys
json.dump({"project": "smoke", "repo": "/home/agent/demo", "main_branch": "main", "runtime": "vps", "host": "",
  "worker_user": "agent", "claude_bin": sys.argv[2],
  "supervisor": {"backend": "claude", "model": "opus", "effort": "high"},
  "worker_models": {"opus": "opus"}, "default_worker_model": "opus",
  "build_queue": {"slots": 2, "wrap": ["cargo build"]}, "sync": {"push_main": False, "branch_globs": ["lane/*"], "interval_s": 60},
  "max_consults_per_day": 30, "max_agent_starts_per_day": 10, "max_agent_hours_per_day": 12},
  open(sys.argv[1], "w"), indent=2)
PY
   out=$(bash "$KIT/scripts/bootstrap-host.sh" "$ORG" 2>&1); rc=$?; echo "$out"
   ok "phase 1 exits 0 and prints the phase-2 command" "[ $rc = 0 ] && printf '%s' \"\$out\" | grep -q 'phase 1 done. Next, as agent'"
   ok "worker user agent exists" "id agent >/dev/null"
   ok "/srv/bin/build-queue and the cargo wrapper installed" "[ -x /srv/bin/build-queue ] && [ -L /srv/bin/cargo ]"
   ok "agent's crontab holds only the tagged line" "[ \"\$(crontab -u agent -l | grep -cv '^\$')\" = 1 ] && crontab -u agent -l | grep -q '# agent-org'"
   echo "-- the project repo, cloned as agent, with the vault on main"
   install -d -o agent -g agent "$SM"
   [ -d "$ORIGIN" ] || ag "git init -q --bare $ORIGIN"
   if [ ! -d "$REPO/.git" ]; then
     ag "git config --global user.name agent && git config --global user.email agent@smoke.invalid && git clone -q $ORIGIN $REPO 2>/dev/null; cd $REPO && git checkout -q -b main && echo '# demo' > README.md && mkdir -p src && echo 'console.log(1)' > src/index.js && git add -A && git commit -qm root && git push -q -u origin main" || exit 1
     ag "cd $REPO && node $KIT/scripts/init-repo.mjs --repo $REPO --vars $KIT/scripts/test-vars.json >/dev/null && git add -A && git commit -qm 'agent-org setup

Authority: owner
EVIDENCE-GROWTH: adds vault/Home.md and the vault contracts, scripts/gates/org-board.sh with the gates.' && git push -q origin main" || exit 1
   fi
   ok "repo and its .git belong to agent" "[ \"\$(stat -c %U $REPO/.git)\" = agent ]"
   ok "org-board passes in the repo (as agent)" "ag 'cd $REPO && bash scripts/gates/org-board.sh' | tail -1 | grep -q 'ORG-BOARD PASS'"
   if ! ag "claude auth status >/dev/null 2>&1"; then   # exits 1 when not logged in (CLI reference)
     echo; echo "NEEDS YOU: log the worker in on the box, interactively:"
     echo "    ssh -t <target> \"su - agent -c 'claude'\"   then /login   (or: su - agent -c 'claude setup-token' and keep the token)"
     exit 10
   fi
   echo "-- phase B (agent): bootstrap phase 2, twice"
   b1=$(ag "bash $KIT/scripts/bootstrap-host.sh $ORG" 2>&1); r1=$?; echo "$b1"
   c1=$(crontab -u agent -l)
   b2=$(ag "bash $KIT/scripts/bootstrap-host.sh $ORG" 2>&1); r2=$?; echo "$b2"
   ok "phase 2: host ready as agent, worker probe OK" "[ $r1 = 0 ] && printf '%s' \"\$b1\" | grep -q 'host ready (remote, as agent)' && printf '%s' \"\$b1\" | grep -q 'worker claude: OK'"
   ok "phase 2 re-run: exit 0, crontab unchanged" "[ $r2 = 0 ] && [ \"\$(crontab -u agent -l)\" = \"\$c1\" ]"
   ok "git-sync running as agent" "pgrep -u agent -f git-sync.sh >/dev/null"
   exit $FAIL ;;

2) echo "-- script supervisor + fake worker (no model calls from here on); lane core"
   cat > "$SM/fake-claude.sh" <<'EOF'
#!/bin/bash
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
case "$AGENT_NAME" in
  planner) echo "- planner moved a row on its own" >> vault/Plan.md; msg="planner: retune the plan";;
  sleeper) sleep 150; printf '# Sleeper\n\nslow\n' > vault/Reports/sleeper.md
           msg=$(printf 'sleeper: slow\n\nEVIDENCE-GROWTH: vault/Reports/sleeper.md keeps the slow measurement.');;
  *) printf '# %s\n\nmeasured\n' "$AGENT_NAME" > "vault/Reports/$AGENT_NAME.md"
     msg=$(printf '%s: measure\n\nEVIDENCE-GROWTH: vault/Reports/%s.md records the measurement.' "$AGENT_NAME" "$AGENT_NAME");;
esac
git add -A && git commit -qm "$msg"
printf '## TL;DR\n%s done\n\n## Vault check\nread vault/Index.md\n' "$AGENT_NAME" > "$report"
EOF
   cat > "$SM/sup.sh" <<EOF
#!/bin/bash
c=$SM/sup-count; n=\$(( \$(cat \$c 2>/dev/null || echo 0) + 1 )); echo \$n > \$c; cat > /dev/null
case \$n in
  1) printf '=== AGENT name=planner model=opus ===\nretune\n=== END AGENT ===\n=== AGENT name=alpha model=opus ===\nmeasure\n=== END AGENT ===\n=== AGENT name=sleeper model=opus ===\nslow\n=== END AGENT ===\n';;
  2) printf '=== MERGE branch=lane/core/alpha ===\n=== MERGE branch=lane/core/planner ===\n=== LAND branch=lane/core/planner ===\n';;
  *) printf '=== PLAN ===\nwaiting on sleeper\n=== END PLAN ===\n';;
esac
EOF
   chown agent:agent "$SM"/fake-claude.sh "$SM"/sup.sh; chmod +x "$SM"/fake-claude.sh "$SM"/sup.sh; rm -f "$SM/sup-count"
   orgset "{'claude_bin': '$SM/fake-claude.sh', 'supervisor': {'backend': 'script', 'command': '$SM/sup.sh'}, 'poll_interval_s': 2, 'idle_wait_s': 20, 'report_overdue_s': 600}"
   [ -d "$ORG/lanes/core" ] || ag "bash $ORG/lanes.sh $ORG new core 'core goal' 3 true" || exit 1
   ag "python3 -c \"import re,sys
for p in sys.argv[1:]:
    t = re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}', 'filled', open(p).read()); open(p, 'w').write(t)\" $ORG/lanes/core/context.md $ORG/lanes/core/supervisor-brief.md"
   r=$(bash "$ORG/lanes.sh" "$ORG" start 2>&1); rc=$?; echo "$r"
   ok "start as root: refused up front, names su - agent -c" "[ $rc = 2 ] && printf '%s' \"\$r\" | grep -q 'su - agent -c' && ! ag 'tmux has-session -t lane-core' 2>/dev/null"
   ag "bash $ORG/lanes.sh $ORG start" 2>&1
   ok "start as agent: the lane session runs" "wait_for \"ag 'tmux has-session -t lane-core' 2>/dev/null\" 10"
   exit $FAIL ;;

3) echo "-- one lane, two consults"
   ok "workers started, pid file written" "wait_for \"lanelog | grep -q 'agent sleeper (opus) start' && ls $ORG/lanes/core/pids/*.json >/dev/null 2>&1\" 60"
   ok "MERGE into integration" "wait_for \"lanelog | grep -q 'MERGE lane/core/alpha ok'\" 120"
   ok "hub regeneration after the merge" "lanelog | grep -q 'hubs regenerated after MERGE'"
   ok "LAND of the Plan.md change refused, report written" "wait_for \"lanelog | grep -q 'LAND lane/core/planner REFUSED'\" 120 && ls $ORG/lanes/core/reports/*zz-land-refused-lane-core-planner.md >/dev/null"
   ok "main did not move" "[ \"\$(ag 'git -C $REPO rev-parse main')\" = \"\$(git -C $ORIGIN rev-parse main)\" ]"
   ok "git-sync pushed lane/* to origin within one interval" "wait_for \"git -C $ORIGIN for-each-ref --format='%(refname)' refs/heads/lane | grep -q lane/core/\" 90"
   echo "-- park the repo off main; a new commit lands on origin main from elsewhere"
   ag "git -C $REPO checkout -q -b parked && rm -rf $SM/other && git clone -q $ORIGIN $SM/other && cd $SM/other && echo x >> README.md && git commit -qam 'from elsewhere' && git push -q origin main"
   want=$(git -C "$ORIGIN" rev-parse main)
   main_synced() { [ "$(ag "git -C $REPO rev-parse main")" = "$want" ]; }
   ok "git-sync fast-forwarded local main without touching the parked HEAD" "wait_for main_synced 90 && [ \"\$(ag 'git -C $REPO symbolic-ref --short HEAD')\" = parked ]"
   ag "git -C $REPO checkout -q main"
   exit $FAIL ;;

4) echo "-- restart with a live agent, then gc"
   ok "sleeper still running (pid file names a live process)" "ag 'bash $ORG/lanes.sh $ORG status' | grep -q 'running: core/sleeper'"
   ag "bash $ORG/lanes.sh $ORG restart core" 2>&1
   ok "restarted loop adopted the running agent" "wait_for \"lanelog | grep -i adopt | grep -q sleeper\" 30"
   g=$(ag "bash $ORG/lanes.sh $ORG gc core" 2>&1); echo "$g"
   ok "gc kept the running agent's worktree" "printf '%s' \"\$g\" | grep -q 'keep wt/sleeper' && [ -d $ORG/lanes/core/wt/sleeper ]"
   exit $FAIL ;;

5) echo "-- the hourly job, by hand, as agent"
   line=$(crontab -u agent -l | grep '# agent-org'); echo "$line"
   cmd=$(printf '%s' "$line" | sed -E 's/^([^ ]+ +){5}//; s/ *# agent-org.*$//')
   ag "$cmd"; rc=$?
   ok "the cron line's command exits 0" "[ $rc = 0 ]"
   br=$(python3 -c "import json;print(json.load(open('$ORG/org.json')).get('state_backup_branch','backup/lane-state'))")
   tree=$(git -C "$ORIGIN" ls-tree -r --name-only "$br"); echo "$tree"
   ok "snapshot on origin holds the lane's recovery files" "printf '%s' \"\$tree\" | grep -qx lanes/core/lane.json && printf '%s' \"\$tree\" | grep -qx lanes/core/supervisor-brief.md"
   ok "snapshot holds nothing outside the allowlist" "! printf '%s' \"\$tree\" | grep -qE '/(prompts|rounds|reports|wt|logs|pids)/|owner-answers.md|agent-rules.md|supervise.out|lane.log'"
   ok "snapshot org.json keeps every key of the live org.json" "git -C $ORIGIN show $br:org.json | python3 -c 'import json,sys;a=set(json.load(open(\"$ORG/org.json\")));b=set(json.load(sys.stdin));sys.exit(not a<=b)'"
   ok "hourly job is cron here (no systemd timer needed)" "command -v crontab >/dev/null"
   exit $FAIL ;;

6) echo "-- build queue under contention"
   printf '#!/bin/bash\necho "start $$ $(date +%%s.%%N)" >> %s/cargo.log; sleep 6; echo "end $$ $(date +%%s.%%N)" >> %s/cargo.log\n' "$SM" "$SM" > "$SM/fake-cargo"
   chmod +x "$SM/fake-cargo"; chown agent:agent "$SM/fake-cargo"; rm -f "$SM/cargo.log"
   ag "cd $SM && for i in 1 2 3; do ORG_ROOT=$ORG REAL_cargo=$SM/fake-cargo BUILD_QUEUE_SLOTS=2 BUILD_QUEUE_HEAVY=build /srv/bin/cargo build & sleep 0.3; done; wait"
   cat "$SM/cargo.log"
   ok "two ran at once, the third waited for a slot" "python3 - $SM/cargo.log <<'PY'
import sys
ev = sorted((float(t), k) for k, _, t in (l.split() for l in open(sys.argv[1])))
starts = [t for t, k in ev if k == 'start']; ends = [t for t, k in ev if k == 'end']
sys.exit(not (len(starts) == 3 and starts[1] < ends[0] and starts[2] >= ends[0]))
PY"
   ok "slot locks live in ORG_ROOT/locks" "ls $ORG/locks/cargo.* >/dev/null 2>&1"
   r=$(ag "cd $SM && env -u REAL_cargo ORG_ROOT=$ORG /srv/bin/cargo build" 2>&1); rc=$?; echo "$r"
   ok "no real cargo: exit 127 with the one-line reason" "[ $rc = 127 ] && printf '%s' \"\$r\" | grep -q 'build-queue: no real cargo'"
   exit $FAIL ;;

7) echo "-- ownership"
   bad=$(find "$REPO/.git" "$ORG" ! -user agent 2>/dev/null); printf '%s\n' "$bad" | head -20
   ok "nothing under the repo's .git or ORG_ROOT belongs to anyone but agent" "[ -z \"\$bad\" ]"
   exit $FAIL ;;

8) echo "-- stop"
   ag "bash $ORG/lanes.sh $ORG stop core"
   ok "the lane loop exits" "wait_for \"! pgrep -u agent -f 'supervise.py $ORG/lanes/core' >/dev/null\" 120"
   ok "its agents have finished" "wait_for \"! ag 'bash $ORG/lanes.sh $ORG status' | grep -q 'running:'\" 240"
   ps -u agent -o pid=,args= | tee /dev/stderr >/dev/null
   ok "no lane process left (loop, agents, fake worker)" "! ps -u agent -o args= | grep -E 'supervise.py|fake-claude|lanes/core' | grep -v grep | grep -q ."
   ok "git-sync still running" "pgrep -u agent -f git-sync.sh >/dev/null"
   exit $FAIL ;;
*) echo "no step $N (1-$STEPS)"; exit 2 ;;
esac
