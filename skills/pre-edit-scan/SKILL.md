---
name: pre-edit-scan
description: Searches for existing equivalent code BEFORE writing anything new, so you reuse or extend instead of duplicating — and ensures superseded code is deleted, never left dead. Surfaces existing helpers, types, prompts, routes, and tests the new code might duplicate. Use proactively whenever the task adds a function, class, type, prompt, file, or endpoint. The operational form of .claude/rules/no-bloat.md.
when_to_use: "Trigger when the user asks to add/create/implement/build X — and before any new Write or Edit that introduces a new symbol. Also on phrases: 'add a helper', 'create a util', 'new endpoint', 'add a prompt', 'extract this into', 'wrap this in a function'."
allowed-tools: Bash(rg:*), Bash(ls:*), Bash(find:*), Bash(ast-grep:*), Bash(git:*), Read, Grep, Glob
---

# Pre-Edit Scan (Anti-Bloat)

## Overview

Two things bloat a codebase: **redundant code** (a second implementation of something that already exists) and **dead code** (implementations nothing calls anymore). This skill prevents both. Before writing, prove the code doesn't already exist — and reuse it if it does. After changing, prove you left nothing orphaned. The default is always **reuse/extend over create**, and **delete-on-supersede over leave-behind**.

This is the operational form of `.claude/rules/no-bloat.md`.

## When to Use

Run the **scan (Part A)** before adding any of:

- a function, class, method, or component
- a type, interface, or schema
- a new file
- an API endpoint or route
- a prompt or tool schema
- a test helper or fixture

Run the **dead-code check (Part B)** after any change that replaces, supersedes, or removes behavior.

Skip it for: trivial edits inside one function, renames, or pure deletions.

## Process

### Part A — Search before you write

**1. Frame the search** (one line each):

1. **Concept** — what it does, e.g. "redact emails from transcript text"
2. **3–5 plausible names** an existing version might have, e.g. `redactEmails`, `scrubPii`, `sanitizeText`, `cleanTranscript`
3. **A distinctive string** the existing code would contain — a regex literal, an error message, a field name
4. **The likely directory**

**2. Locate the source roots** (portable — run as-is to learn the layout):

```bash
git rev-parse --show-toplevel 2>/dev/null
find . -maxdepth 2 -type d \( -name src -o -name lib -o -name app -o -name packages \
  -o -name internal -o -name pkg -o -name core -o -name tests \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
```

**3. Name search** (substitute *your* candidate names, then run):

```bash
for term in NAME1 NAME2 NAME3; do
  echo "--- $term ---"
  rg -i -n "$term" -g '!**/{node_modules,dist,build,.git,vendor,target}/**' . | head -5
done
```

**4. Behavior search** — grep the distinctive string across the repo:

```bash
rg -n 'DISTINCTIVE_STRING' -g '!**/{node_modules,dist,build,vendor}/**' . | head -10
```

**5. Structural search** (optional — when the task is a *shape*, not a name):

```bash
command -v ast-grep >/dev/null \
  && ast-grep --lang LANG -p 'PATTERN' . | head -20 \
  || echo "(ast-grep not installed — skip)"
```

**6. Neighbor read** — list the target directory and read one existing file before writing, so you match local patterns:

```bash
ls TARGET_DIR/
```

**Decide** — classify into exactly one outcome and state it in one line *before* any Write/Edit:

| Outcome | Action |
|---|---|
| **Exact match exists** | Use it. Write nothing new. |
| **Close match exists** | Extend it — add a parameter, broaden a type, add a variant in the same file. Update existing callers in the same change. |
| **Related concept nearby** | Put the new code in that file/directory and match its patterns. |
| **Nothing similar** | Write new. Say so explicitly: _"No existing implementation. Creating new at `<path>`."_ |

```
Scan result: <exact|close|related|none>. Action: <reuse X | extend X | add to <file> | create new at <path>>.
```

The default answer is "modify the existing one." Forking an existing implementation requires a written reason (different responsibility, different invariants). That reason becomes a comment if the divergence is non-obvious.

### Part B — Leave no dead code

When your change replaces or supersedes existing code, in the **same change**:

1. Delete the old implementation — never leave it beside the new one.
2. Remove now-unused imports, exports, types, helpers, and tests.
3. Leave no commented-out code, unreachable branches, or unused parameters.

Then prove nothing is orphaned:

```bash
# Anything still referencing the symbol you removed or renamed?
rg -n 'REMOVED_SYMBOL' -g '!**/{node_modules,dist,build,vendor}/**' .

# If the project ships a dead-code / unused-export detector, run it:
#   JS/TS : npx knip   |  npx ts-prune   |  eslint (no-unused-vars)
#   Python: vulture .  |  ruff (F401/F841)
#   Go    : deadcode ./...  |  staticcheck
```

Zero remaining references to a removed symbol means clean. Remaining references mean you broke a caller — fix it now, in this change.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Faster to just write a new one." | Faster now, two divergent code paths forever. The scan takes ~10 seconds. |
| "Mine is slightly different." | Add a parameter or relax a type. Forking needs a written reason. |
| "I'll delete the old code later." | Later never comes. Delete it in the same change. |
| "I'll comment it out in case." | Git *is* the "in case." Delete it. |
| "The unused export might be needed by someone." | If nothing references it, it's dead. Remove it — git restores it if you were wrong. |

## Red Flags

- Writing a new helper without having grepped its candidate names.
- Two functions doing the same thing under different names.
- Old and new implementations of the same behavior coexisting after a change.
- Commented-out blocks, unreachable code, or unused imports/params left behind.
- "I'll search after I write it."

## Verification

- ☐ Ran name + behavior search before writing
- ☐ Read at least one neighbor file in the target directory
- ☐ Stated the scan result + action in one line before the edit
- ☐ After superseding code, grep shows zero references to the removed symbol
- ☐ No commented-out code, unused imports/exports, or unreachable branches introduced
