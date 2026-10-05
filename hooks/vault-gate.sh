#!/bin/bash
# vault-gate.sh — PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit). It nudges; it never installs.
#
# In a git repository with no agent-org vault (vault/AGENTS.md), the FIRST write of each session is
# blocked once (exit 2: the tool call is refused and stderr goes to Claude) with "run `/setup` here".
# The next write in the same session goes through. Silent: outside git, in a repo with a vault, for
# headless org processes (AGENT_ORG_HEADLESS / AGENT_NAME), and where the owner opted out with
# ORG_VAULT=off or a .claude/no-vault marker (that opt-out is logged once per session).
# Docs: https://code.claude.com/docs/en/hooks (PreToolUse input: session_id, cwd; exit 2 blocks).
#
# State: one marker per session and repo under ${CLAUDE_VAULT_GATE_DIR:-$TMPDIR/claude-vault-gate-<uid>}.
# Dependencies: jq, git (degrades to a silent no-op without either).

set -uo pipefail
[ -n "${AGENT_ORG_HEADLESS:-}${AGENT_NAME:-}" ] && exit 0
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TOP=$(git -C "${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$TOP/vault/AGENTS.md" ] && exit 0

STATE=${CLAUDE_VAULT_GATE_DIR:-${TMPDIR:-/tmp}/claude-vault-gate-$(id -u)}
mkdir -p "$STATE" 2>/dev/null || exit 0
KEY=$(printf '%s|%s' "${SID:-nosession}" "$TOP" | cksum | cut -d' ' -f1)

if [ "${ORG_VAULT:-}" = off ] || [ -e "$TOP/.claude/no-vault" ]; then
  if [ ! -e "$STATE/$KEY.off" ]; then
    : > "$STATE/$KEY.off"
    why=$([ "${ORG_VAULT:-}" = off ] && echo "ORG_VAULT=off" || echo ".claude/no-vault")
    printf '%s vault gate off (%s) for %s, session %s\n' "$(date -u +%FT%TZ)" "$why" "$TOP" "${SID:-?}" >> "$STATE/vault-gate.log"
  fi
  exit 0
fi

[ -e "$STATE/$KEY" ] && exit 0
: > "$STATE/$KEY"
echo "This git repo has no agent-org vault (vault/AGENTS.md): run \`/setup\` here to add one. To work without it, create .claude/no-vault (or set ORG_VAULT=off). This reminder blocks once per session; retry the edit to continue." >&2
exit 2
