# No Bloat

Two rules, always on. Together they keep the codebase free of duplication and dead weight.

## 1. Search before you write (no redundant code)

Never add code that may already exist. Before writing any new symbol — function, class, type, file, endpoint, prompt, test helper — search for an existing implementation and **reuse or extend** it. Creating new is the last resort, used only after the search comes up empty.

This rule is operationalized by the **`pre-edit-scan`** skill. Run it before introducing a new symbol.

Default to modifying existing code over adding new. Forking an existing implementation requires a one-line written reason (different responsibility, different invariants).

## 2. Leave no dead code

When you supersede, replace, or remove behavior, delete — in the **same change** — the old implementation, its now-unused imports/exports/types/helpers/tests, any commented-out blocks, and unreachable branches.

After the change, grep for references to anything you removed. Zero references means clean; remaining references mean a caller is broken — fix it now.

## Why

Redundant code creates divergent paths that drift apart and multiply bugs. Dead code misleads every future reader about what the system actually does. Git is the safety net — deleted code is always recoverable, so delete confidently rather than hoarding "just in case."

## In this repo — the search order, and the tools

Before writing any new symbol, search in this order and do not stop at the first empty answer:

1. **`vault/Index.md`** — what was already decided, measured, tried or rejected (vault notes only).
2. **`node scripts/where.mjs <name> --branches`** — who already implements it: on main, on your HEAD,
   and on every unlanded work branch (content-filtered, so a hit there is real unlanded work).
3. **`git grep`** for the distinctive string (an error message, a regex, a field name).
4. **`.claude/rules/`** — prior art also lives in the laws and their cases.

`where.mjs` exits 1 when nothing matches anywhere, and 2 when its search could not run — only exit
1 is a negative. A design doc records what this search found in its "Prior art here" section.
