# `.claude/` — what Claude Code loads in this repo

- `rules/` — the laws every agent is held to: no-bloat, goals-not-tests, vault-first,
  evidence-and-honesty and protected-paths load into every session; gate-independence loads when an
  agent reads or edits a gate, hook, test or evidence file (its `paths:` frontmatter), and
  evidence-and-honesty carries its core always. Normative, not
  advisory; owner-only (`vault/CLAUDE.md`).
- `agents/` — the sub-agent role cards and their tool allowlists. Each carries the contract's
  load-bearing lines inline, because a pointer is not a delivery
  (`scripts/hooks/agent-contract.test.mjs` holds them there).
- `skills/` — session-open, session-close, capture.
- `settings.json` — the four hooks: SessionStart prints `vault/AGENTS.md` and the mission's NOW
  block; PreToolUse runs the contract hook; Stop runs the loop guard; SubagentStop records each
  dispatch. `ORG_MISSION` names the mission in force.
