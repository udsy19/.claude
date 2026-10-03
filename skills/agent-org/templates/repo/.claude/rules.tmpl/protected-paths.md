# Protected paths: supervisor and owner only

`vault/Plan.md` · `vault/Roadmap.md` · `vault/Decisions/` · `.claude/rules/` · `.claude/settings.json`

Only the roles `supervisor` and `owner` write these; every other agent proposes with
`node scripts/propose.mjs --row <id> --kind split|reorder|add|done|challenge --why "<reason with a number>"`.
Rules and decisions record the OWNER's rulings; the plan and roadmap are the supervisor's.

Enforced twice, by layers that do not trust each other: `scripts/hooks/agent-contract.mjs` refuses
the Edit/Write tool, and `scripts/gates/plan-ownership.mjs` re-checks from git that every commit
touching one of these carries `Authority: supervisor`, `Authority: owner` or `Proposal: #<n>`. The
list is declared once, in `scripts/lib/protected-paths.mjs`; `scripts/gates/protected-paths.mjs`
holds this file and the vault contracts to it.
