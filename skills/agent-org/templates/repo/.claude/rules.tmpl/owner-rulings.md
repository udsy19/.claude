# Owner rulings: the standing law of this project

The owner's rulings that bind every session, lane and agent in this repo. This file is the one
standing source: it is versioned, reviewable, and loaded into every Claude Code session here.

- **Goals, not tests.** Every task is framed by goal, vision, what we are building and what has not
  worked.
- **The owner judges by looking.** Evidence is screenshots, rendered output and videos from the real
  product path, not counts, scores or claims.
- **Vault first.** Know what the project already knows, and write findings back.
- **Settings, not questions.** Anything the product can expose as a user setting is a setting with
  sensible defaults, never an owner question.
{{EXTRA_RULINGS}}

Who writes it: the owner, or the overseer recording the owner's words, in a commit carrying
`Authority: owner` (a protected path; `scripts/gates/plan-ownership.mjs` checks the trailer). One line
per ruling; replace a ruling the owner supersedes rather than appending a contradiction. A ruling that
binds one lane only goes in that lane's `rulings.md` on the org host instead.
