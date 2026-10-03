---
name: session-close
description: Close a work session — finish the session note with commits, evidence paths, verified checks and board lines, update status fields and the NOW / Next / Lines tables on vault/Home.md, retire the registry declaration, regenerate the hubs and the Index, and leave one clear next move. Use when the user says "wrap up", "close the session", "/session-close", or before ending a long autonomous run.
---

# /session-close

The vault contract (`vault/CLAUDE.md`) lets a session write its own session note, status fields,
reports and research, and the Home tables. Do those, and nothing else.

1. **Session note** (`vault/Sessions/<today>-<slug>.md`): fill every section of the template.
   - *Vault check*: what you read, reused, and found stale.
   - *What changed*: every commit hash with a one-line why; files touched.
   - *Verified*: the path driven, the port, the build token asserted after a forced reload, and the
     evidence paths under `evidence/`. If nothing was verified in the product, write "not verified" —
     do not omit the section.
   - *Gates*: paste the board's own final line (`bash scripts/gates/org-board.sh`) and any product
     board, derived from exit codes — never a grep of a summary.
   - Set `outcome:` to one of `done | partial | blocked | abandoned`.
2. **Status fields**: a design/decision/mission note whose reality changed gets `status` and `updated`
   corrected (protected paths excepted — propose those). A doc you found wrong gets `status: outdated`
   plus a one-line reason at the top; you do not rewrite it.
3. **Home.md**: tick or reword *Next 3 moves*, update the *Lines in flight* row for your line, add a
   blocker if one appeared. Keep NOW in the owner's words.
4. **Registry**: mark your declaration `FINISHED` with the closing state in
   `vault/Reports/audits/SESSION-REGISTRY.md`. Never edit another session's entry.
5. **Regenerate**: `node scripts/vault-hubs.mjs` and `python3 scripts/gen-subject-index.py`, then
   `node scripts/gates/vault-reachability.mjs` (exit 0).
6. Commit the vault changes on your branch (`vault: session <slug> closed`), and tell the user the
   single next move and every open question that needs them.
