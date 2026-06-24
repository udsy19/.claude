#!/bin/bash
# agent-skills session start hook
# Injects the using-agent-skills meta-skill into every new session

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$(dirname "$SCRIPT_DIR")/skills"
META_SKILL="$SKILLS_DIR/using-agent-skills/SKILL.md"

if ! command -v jq >/dev/null 2>&1; then
  echo '{"priority": "INFO", "message": "agent-skills: jq is required for the session-start hook but was not found on PATH. Install jq (e.g. `brew install jq` or `apt-get install jq`) to enable meta-skill injection. Skills remain available individually."}'
  exit 0
fi

if [ -f "$META_SKILL" ]; then
  # Inject everything except the reference-only tail (Lifecycle Sequence +
  # Quick Reference). Those duplicate the flowchart and each skill's
  # description — both already in context — so injecting them every session is
  # wasted, redundant context. They remain in the skill body, loadable on
  # demand. If the heading ever changes, sed no-ops and the full file is sent.
  CONTENT=$(sed '/^## Lifecycle Sequence/,$d' "$META_SKILL")
  # Use jq to properly escape and construct valid JSON
  jq -cn \
    --arg message "agent-skills is active for this session. Treat the following as standing operating procedure, not background reference:

• Before acting on any non-trivial request, match it to a skill using the discovery flowchart below, then follow that skill's process. Skills are workflows, not suggestions.
• Multiple skills chain — when several apply, run them in lifecycle order.
• A [skill-router] hint is injected on each prompt as a first routing pass; confirm it against the flowchart, then proceed.
• Anti-hallucination (anti-hallucination skill): never state a checkable fact, API, signature, flag, version, config key, or citation from memory — verify it against the source (the code in front of you, the installed package, official docs) before asserting. Research the current best approach before implementing in an unfamiliar project. Mark uncertainty as uncertainty; say \"I don't know\" rather than guessing.
• No bloat (.claude/rules/no-bloat.md): before writing any new symbol (function, type, file, endpoint, prompt), run pre-edit-scan to find existing code and reuse/extend instead of duplicating. When you supersede code, delete the now-dead code — old implementation, unused imports/exports, commented-out blocks — in the same change.
• Version control is continuous (autonomous-git-workflow): after each working, verified unit of change, commit it with a simple structured message — a ≤10-bullet summary of the difference from the last commit, flagging anything explicit. Parallelize multiple features with git worktrees; create a new branch only for a large or genuinely different effort, and ask first.
• Memory (memory-discipline): persist durable, future-useful learnings to native memory — keep MEMORY.md a concise index with detail in topic files; record gotchas, decisions, conventions, and user preferences. A standing human instruction belongs in CLAUDE.md, not auto-memory. Never store secrets, transient state, or anything re-derivable from code. Treat recalled memory as possibly stale — re-verify named files/flags before acting on them.

$CONTENT" \
    '{priority: "IMPORTANT", message: $message}'
else
  echo '{"priority": "INFO", "message": "agent-skills: using-agent-skills meta-skill not found. Skills may still be available individually."}'
fi
