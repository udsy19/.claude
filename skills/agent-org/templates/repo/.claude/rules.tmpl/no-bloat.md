# No bloat (this repo)

Two rules: **search before you write** — reuse or extend existing code; new is the last resort — and
**leave no dead code** — what your change supersedes (old implementation, now-unused imports, helpers,
tests, commented-out blocks) is deleted in the same change, then grep that nothing still references it.
The `pre-edit-scan` skill is the operational form. A global copy of this rule may also be loaded from
`~/.claude/rules/no-bloat.md`; this file adds what is specific to this repo.

## In this repo — the search order, and the tools

Before writing any new symbol, search in this order and do not stop at the first empty answer:

1. **`vault/Index.md`** — what was already decided, measured, tried or rejected (vault notes only).
2. **`node scripts/where.mjs <name> --branches`** — who already implements it: on main, on your HEAD,
   and on every unlanded work branch (content-filtered, so a hit there is real unlanded work).
3. **`git grep`** for the distinctive string (an error message, a regex, a field name).
4. **`.claude/rules/`** — prior art also lives in the laws and their cases.

`where.mjs` exits 1 when nothing matches anywhere, and 2 when its search could not run — only exit
1 is a negative. A design doc records what this search found in its "Prior art here" section.
