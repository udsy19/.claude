#!/usr/bin/env bash
# The headless audit (C1): every hook a lane process can meet — the global config's (repo root
# settings.json + hooks/) and the installed scaffold's (.claude/settings.json) — run as each role,
# asserting who gets the interactive layer and who may write what.
#   bash scripts/test-headless.sh          (KEEP=1 keeps the sandbox)
# Roles, by the environment supervise.py and the overseer's settings.local.json give them:
#   worker      AGENT_ORG_HEADLESS=1 AGENT_NAME=alpha ORG_LANE=core
#   supervisor  AGENT_ORG_HEADLESS=1 ORG_ROLE=supervisor            (the lane supervisor's consult)
#   overseer    ORG_ROLE=supervisor                                 (interactive, the owner's session)
#   unset       nothing                                             (any other interactive session)
# Prints one table (rows: what was checked; cells: what each role got) and fails on any cell that
# differs from the expected one.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
CONF=$(cd "$KIT/../.." && pwd)          # the .claude config repo: settings.json, hooks/, skills/
SB=$(mktemp -d /tmp/headless-test.XXXXXX)
REPO="$SB/my repo"
cleanup() { if [ "${KEEP:-}" = 1 ]; then echo "sandbox kept: $SB"; else rm -rf "$SB"; fi; }
trap cleanup EXIT
export HOME="$SB/home"; mkdir -p "$HOME"; ln -s "$CONF" "$HOME/.claude"   # a global install
export TMPDIR="$SB/tmp"; mkdir -p "$TMPDIR"                               # the contract hook's markers
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset ORG_ROLE AGENT_NAME AGENT_ORG_HEADLESS ORG_LANE ORG_MAIN_BRANCH ORG_MISSION

git init -q -b main "$REPO" && git -C "$REPO" commit -q --allow-empty -m root
node "$KIT/scripts/init-repo.mjs" --repo "$REPO" --vars "$KIT/scripts/test-vars.json" > "$SB/install.log" 2>&1 \
  || { echo "init-repo failed:"; tail -5 "$SB/install.log"; exit 2; }
# A running mission with a dispatch today and no session note: the state the loop guard fires on.
TODAY=$(date -u +%Y-%m-%d)
echo "{\"ts\":\"${TODAY}T00:00:01Z\",\"agent\":\"builder\",\"session\":\"s\"}" > "$REPO/vault/_log/agents.jsonl"

ROLES="worker supervisor overseer unset"
role_env() { case $1 in
  worker) echo "AGENT_ORG_HEADLESS=1 AGENT_NAME=alpha ORG_LANE=core" ;;
  supervisor) echo "AGENT_ORG_HEADLESS=1 ORG_ROLE=supervisor" ;;
  overseer) echo "ORG_ROLE=supervisor" ;;
  unset) echo "" ;; esac; }
# hook <settings.json> <event> <matcher-or-empty> <role> <stdin> → prints "rc<TAB>stdout+stderr"
hook() {
  local cmds; cmds=$(jq -r --arg e "$2" --arg m "$3" '.hooks[$e][]? | select(($m == "") or ((.matcher // "") | test($m))) | .hooks[].command' "$1")
  local out="" rc=0 c o r
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # shellcheck disable=SC2046  # role_env prints NAME=VALUE words for env; splitting them is the point
    o=$(printf '%s' "$5" | env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" CLAUDE_PROJECT_DIR="$REPO" $(role_env "$4") sh -c "$c" 2>&1); r=$?
    out="$out$o"; [ $r -gt $rc ] && rc=$r
  done <<< "$cmds"
  printf '%s\t%s' "$rc" "$out"
}
G="$CONF/settings.json"; P="$REPO/.claude/settings.json"
write() {   # write <role> <path>: the contract hook's verdict on a write, after the once-per-session delivery
  local s="s$RANDOM$RANDOM"
  j() { printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$s" "$1"; }
  hook "$P" PreToolUse Write "$1" "$(j "$REPO/src/warmup.js")" > /dev/null
  local r; r=$(hook "$P" PreToolUse Write "$1" "$(j "$2")"); [ "${r%%	*}" = 2 ] && echo REFUSED || echo ok
}

PASS=0; FAIL=0; TABLE=""
row() {   # row <label> <expected per role, space-separated> <function producing a cell for a role>
  local label="$1" fn="$3" line i=0 got cell want; read -ra want <<< "$2"
  line=$(printf '| %-46s' "$label")
  for r in $ROLES; do
    got=$($fn "$r"); cell="$got"
    if [ "$got" = "${want[$i]}" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); cell="${got}!=${want[$i]}"; fi
    line="$line| $(printf '%-13s' "$cell")"; i=$((i+1))
  done
  TABLE="$TABLE$line|"$'\n'
}
c_sop()     { local r; r=$(hook "$G" SessionStart "" "$1" '{"source":"startup"}'); printf '%s' "${r#*	}" | grep -q 'agent-skills is active' && echo SOP || echo none; }
c_router()  { local r; r=$(hook "$G" UserPromptSubmit "" "$1" '{"prompt":"fix this bug in the parser"}'); printf '%s' "${r#*	}" | grep -q 'skill-router' && echo hint || echo none; }
c_gtools()  { local a b c; a=$(hook "$G" PreToolUse WebFetch "$1" '{"tool_name":"WebFetch","tool_input":{"url":"https://example.invalid/"}}'); \
              b=$(hook "$G" PostToolUse Edit "$1" '{"tool_name":"Edit","tool_input":{"file_path":"/dev/null"}}'); c=$(hook "$G" Stop "" "$1" '{}'); \
              [ "${a%%	*}${b%%	*}${c%%	*}" = 000 ] && echo exit0 || echo "exit${a%%	*}${b%%	*}${c%%	*}"; }
c_agents()  { local r; r=$(hook "$P" SessionStart startup "$1" '{"source":"startup"}'); printf '%s' "${r#*	}" | grep -q 'AGENTS' && echo contract || echo none; }
c_guard()   { rm -f "$REPO/vault/.loop-blocks"; local r; r=$(hook "$P" Stop "" "$1" '{}'); [ "${r%%	*}" = 2 ] && echo BLOCK || echo silent; }
c_code()    { write "$1" "$REPO/src/feature.js"; }
c_plan()    { write "$1" "$REPO/vault/Plan.md"; }
c_session() { write "$1" "$REPO/vault/Sessions/$TODAY-note.md"; }
c_home()    { write "$1" "$REPO/vault/Home.md"; }
c_memory()  { write "$1" "$HOME/.claude/projects/-repo/memory/feedback.md"; }
c_usage()   { local r; r=$(hook "$P" SubagentStop "" "$1" '{"agent_type":"builder","session_id":"x"}'); echo "exit${r%%	*}"; }

row "global: standing procedure (SessionStart)" "none none SOP SOP"               c_sop
row "global: skill-router hint (UserPromptSubmit)" "none none hint hint"          c_router
row "global: cache/simplify hooks (tool, Stop)" "exit0 exit0 exit0 exit0"  c_gtools
row "scaffold: AGENTS.md contract (SessionStart)" "contract none none contract"   c_agents
row "scaffold: loop guard (Stop), mission running" "silent silent BLOCK BLOCK" c_guard
row "scaffold: write product code" "ok REFUSED ok ok"                       c_code
row "scaffold: write vault/Plan.md (protected)" "REFUSED REFUSED ok REFUSED" c_plan
row "scaffold: write a session note" "REFUSED REFUSED ok ok"                c_session
row "scaffold: write vault/Home.md" "REFUSED REFUSED ok ok"                 c_home
row "scaffold: write auto-memory" "REFUSED REFUSED ok ok"                   c_memory
row "scaffold: dispatch log (SubagentStop)" "exit0 exit0 exit0 exit0"       c_usage

printf '| %-46s| %-13s| %-13s| %-13s| %-13s|\n' "hook / action" worker supervisor overseer unset
printf '%s' "$TABLE"
echo "(lane supervisor: its --tools allowlist in supervise.py gives it no write tool at all; the REFUSED cells"
echo " above are the hook's second layer, for the case where that allowlist changes.)"
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
