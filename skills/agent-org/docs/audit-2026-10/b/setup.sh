#!/usr/bin/env bash
# usage: setup.sh <sandbox-dir>   — repo with the agent-org layer, bare origin, org with lanes a and b (script backend)
set -u
KIT=/private/tmp/claude-501/-Users-udsy-Desktop-Design-Files-foldermemory-hierarchy/8bd330f8-0e6e-45a1-a5b9-fce8770f4483/scratchpad/audit-b/skills/agent-org
SB=$1; rm -rf "$SB"; mkdir -p "$SB/home"; export HOME=$SB/home
ORG=$SB/org; REPO=$SB/repo
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@x.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@x.invalid
git init -q --bare "$SB/origin.git"; git init -q -b main "$REPO"; cd "$REPO" || exit 2
git commit -q --allow-empty -m root
cat > "$SB/vars.json" <<'JSON'
{"PROJECT": "Sandbox", "MAIN_BRANCH": "main", "MISSION": "first-mission", "MISSION_TITLE": "First mission",
 "MISSION_GOAL": "Ship", "VISION_ONE_LINER": "A sandbox", "USERS": "t", "ACCEPTANCE_BAR": "works",
 "OWNER_WORDS": "w", "NOT_WORKED": "n", "NEXT_MOVE": "s", "FIRST_TRACK": "core",
 "FIRST_TRACK_ITEM": "s", "SOURCE_AREAS": "| `src/` | code | src/index.js |", "SUPERVISOR_DESC": "c",
 "WORKER_DESC": "f", "RUNTIME": "local", "HOST": "localhost", "ORG_ROOT": "/tmp/org", "STATE_BRANCH": "backup/lane-state",
 "LANE_TABLE": "| a | x | a | lane/a/* | 2 | yes |", "EXTRA_RULINGS": "- (none yet)"}
JSON
node "$KIT/scripts/init-repo.mjs" --repo "$REPO" --vars "$SB/vars.json" > "$SB/init-repo.out" 2>&1 || { tail -5 "$SB/init-repo.out"; exit 2; }
mkdir -p src; printf 'limit=5\n' > src/a.conf; printf 'factor=1\n' > src/b.conf
# a product check the LAND gates never run: limit*factor must stay <= 10
printf '#!/bin/sh\nl=$(sed -n "s/limit=//p" src/a.conf); f=$(sed -n "s/factor=//p" src/b.conf); [ $((l*f)) -le 10 ] || { echo "CHECK FAIL: limit*factor=$((l*f))"; exit 1; }; echo "check ok: $((l*f))"\n' > src/check.sh; chmod +x src/check.sh
node scripts/vault-hubs.mjs >/dev/null
git add -A && git commit -q -m "setup

Authority: owner
EVIDENCE-GROWTH: vault/Home.md, scripts/gates/org-board.sh, src/a.conf, src/b.conf and src/check.sh arrive with the
repo layer and the product so the landing gates have a real project to grade." && git remote add origin "$SB/origin.git" && git push -q origin main
cat > "$SB/fake-claude.sh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
[ -f "$LANE_ROOT/../../worker-$AGENT_NAME.sh" ] && . "$LANE_ROOT/../../worker-$AGENT_NAME.sh"
printf '## TL;DR\n%s done\n' "$AGENT_NAME" > "$report"
EOF
cat > "$SB/sup.sh" <<EOF
#!/usr/bin/env bash
lane=\$(basename "\$(dirname "\$PWD")"); c=$SB/count-\$lane; n=\$(( \$(cat \$c 2>/dev/null || echo 0) + 1 )); echo \$n > \$c
cat > $SB/seen-\$lane-\$n.txt
f=$SB/script-\$lane-\$n.txt; if [ -f "\$f" ]; then cat "\$f"; else printf '=== DONE ===\n'; fi
EOF
chmod +x "$SB"/fake-claude.sh "$SB"/sup.sh
mkdir -p "$ORG"; cp "$KIT"/scripts/{supervise.py,lanes.sh,git-sync.sh,lane-events.sh} "$ORG/"; mkdir -p "$ORG/templates"; cp -R "$KIT/templates/lane" "$ORG/templates/"
cat > "$ORG/org.json" <<EOF
{ "project": "sb", "repo": "$REPO", "main_branch": "main", "worker_user": "", "claude_bin": "$SB/fake-claude.sh",
  "supervisor": { "backend": "script", "command": "$SB/sup.sh" }, "worker_models": { "opus": "fake" }, "default_worker_model": "opus",
  "agent_timeout_s": 300, "report_overdue_s": 600, "poll_interval_s": 1, "idle_wait_s": 1, "consult_timeout_s": 60,
  "sync": {"interval_s": 1, "branch_globs": ["lane/*"]} }
EOF
for k in a b; do bash "$ORG/lanes.sh" "$ORG" new $k "goal $k" 2 true >/dev/null || exit 3
  python3 -c "import re,sys
for p in sys.argv[1:]:
    t=re.sub(r'\{\{[A-Z][A-Z0-9_]*\}\}','filled',open(p).read()); open(p,'w').write(t)" "$ORG/lanes/$k/context.md" "$ORG/lanes/$k/supervisor-brief.md"; done
echo "setup ok: $SB"
