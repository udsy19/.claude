## How work is organised (agent-org)

- **Start of every interactive session** (not lane workers — their report is their trail): `/session-open` — read `vault/Home.md`, the newest `vault/Sessions/` note
  and the mission in force. The vault is mission control: its contract is `vault/CLAUDE.md`, its routing
  table for every agent is `vault/AGENTS.md`, the overseer's contract is `vault/SUPERVISOR.md`, and who
  may write what is the authority matrix in `vault/Architecture.md`.
- **Lanes:** work runs in supervised lanes — one supervisor per lane plans and judges, worker agents build,
  workers may use sub-agents. See `vault/Design/lanes-and-supervisors.md`. Org root `{{ORG_ROOT}}` on
  {{HOST}}.
- **Rules** (`.claude/rules/`, auto-loaded; gate-independence only when touching gates, hooks or tests):
  gate-independence · no-bloat · goals-not-tests · vault-first · evidence-and-honesty · protected-paths.
- **Protected (supervisor/owner only, enforced by hook + landing gate):** `vault/Plan.md`,
  `vault/Roadmap.md`, `vault/Decisions/`, `.claude/rules/`. Everyone else: `node scripts/propose.mjs`.
- **Before writing a new symbol:** the search order in `.claude/rules/no-bloat.md`. Delete what you
  supersede in the same change.
- **The org's board:** `bash scripts/gates/org-board.sh` (0 green · 1 red · skips named, never passes).
- **End of every interactive session:** `/session-close` — the session note (`vault/Templates/session.md`), Home NOW,
  `node scripts/vault-hubs.mjs` and `python3 scripts/gen-subject-index.py`.
