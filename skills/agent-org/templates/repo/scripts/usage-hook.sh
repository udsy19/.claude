#!/usr/bin/env bash
# scripts/usage-hook.sh — the SubagentStop hook body (.claude/settings.json).
#
# READS: only its own stdin (the hook payload Claude Code pipes in on every subagent stop)
# and the ORG_LANE / CLAUDE_PROJECT_DIR env vars. It never reads the logs it writes — it only
# appends, so it cannot be told by the ledger that it is fine.
# WRITES: one line to vault/_log/agents.jsonl (the independent dispatch record
# scripts/loop-guard.sh counts) and one line to vault/_log/usage.jsonl. Both are gitignored.
#
# The payload's shape is not guaranteed across Claude Code versions, so every field is read
# with a jq `//` fallback chain. NOTE: jq's `//` falls through on null/false but NOT on "",
# so an `"agent":""` line means the key was present and empty — loop-guard.sh counts those
# as UNATTRIBUTED stops rather than dropping them. An absent usage total becomes
# `tokens: null`, never a fabricated zero.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
mkdir -p "$ROOT/vault/_log"
IN="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "usage-hook: jq not installed — no dispatch recorded" >> "$ROOT/vault/_log/usage-hook.err"; exit 0; }

printf '%s' "$IN" | jq -c '{ts:(now|todate), agent:(.agent_type // .subagent_type // "unknown"), session:.session_id}' \
  >> "$ROOT/vault/_log/agents.jsonl" 2>/dev/null

printf '%s' "$IN" | jq -c --arg lane "${ORG_LANE:-unknown}" '
  ((.usage.output_tokens? // 0) + (.usage.input_tokens? // 0)
    + (.usage.cache_creation_input_tokens? // 0) + (.usage.cache_read_input_tokens? // 0)) as $sum
  | {
      ts: (now | todate),
      lane: $lane,
      role: (.subagent_type // .agent_type // "unknown"),
      model: (.model // null),
      tokens: (if (.usage? != null and $sum > 0) then $sum else null end),
      duration_ms: (.duration_ms // null),
      session: .session_id,
      source: "hook"
    }' >> "$ROOT/vault/_log/usage.jsonl" 2>/dev/null

# RATE-LIMIT WATCH: a sub-agent that died on a usage limit ends with the API's message in
# its stop payload. Record it, so the supervisor stops fanning out until the reset instead
# of burning the next window on agents that will die the same way.
if printf '%s' "$IN" | grep -qiE "session limit|rate_limit|rate limit|usage limit|HTTP 429"; then
  MSG="$(printf '%s' "$IN" | grep -oiE "[^\"]{0,40}(session limit|rate_limit|rate limit|usage limit|HTTP 429)[^\"]{0,120}" | head -1)"
  jq -cn --arg lane "${ORG_LANE:-unknown}" --arg seen "$MSG" '{ts:(now|todate), lane:$lane, seen:$seen}' \
    >> "$ROOT/vault/_log/ratelimit.jsonl" 2>/dev/null
fi
exit 0
