# Protected paths: supervisor and owner only

- **Intent:** `vault/Plan.md` · `vault/Roadmap.md` · `vault/Decisions/` · `vault/Missions/` · `vault/Vision.md` · `vault/Index.md`
- **Contracts and instructions:** `vault/AGENTS.md` · `vault/SUPERVISOR.md` · `vault/Architecture.md` · `CLAUDE.md` (every one) · `.claude/rules/` · `.claude/agents/` · `.claude/skills/` · `.claude/settings.json` · `.mcp.json`
- **Enforcement:** `scripts/gates/` · `scripts/hooks/` · `scripts/lib/protected-paths.mjs` · `scripts/lib/landing-range.mjs` · `scripts/lib/commit-trailers.mjs` · `scripts/lib/git-env.mjs` · `scripts/lib/argv.mjs` · `scripts/loop-guard.sh` · `scripts/loop-guard.count.test.sh` · `scripts/usage-hook.sh` · `scripts/gen-subject-index.py` · `scripts/vault-hubs.mjs` · `.github/workflows/`

Only the roles `supervisor` and `owner` write these; every other agent proposes with
`node scripts/propose.mjs --row <id> --kind split|reorder|add|done|challenge --why "<reason with a number>"`.
Rules and decisions record the OWNER's rulings; the plan and roadmap are the supervisor's.

Enforced twice, by layers that do not trust each other: `scripts/hooks/agent-contract.mjs` refuses
the Edit/Write tool, and `scripts/gates/plan-ownership.mjs` re-checks from git that every commit
touching one of these carries `Authority: supervisor`, `Authority: owner` or `Proposal: #<n>`. A lane never lands a change to any of these, whatever its commit message claims: a trailer is written by whoever makes the commit, so `scripts/gates/plan-ownership.mjs --lane` refuses them outright at a lane's landing. They reach main only as the owner's or overseer's own commits, or as a proposal the owner applies. The
list is declared once, in `scripts/lib/protected-paths.mjs`; `scripts/gates/protected-paths.mjs`
holds this file and the vault contracts to it.
