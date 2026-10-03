---
type: dashboard
status: current
date: {{DATE}}
updated: {{DATE}}
---

# Map of this codebase

Which code is where — [[Map]] does this for the vault's notes, this does it for the source. It is
a STRUCTURE map: areas, entry points, and the most-connected symbols. It does not answer *"who
already implements X?"* — that is `node scripts/where.mjs <name> --branches` ([[AGENTS]] §1).

**How a worker or sub-agent finds code without grepping the world:** open this page for the AREA
and the file to start at; run `where.mjs` for a SYMBOL (main, your HEAD, and unlanded branches,
content-filtered); read only the files those two route you to.

**How this page stays true — two modes, one rule:**
- **Generated** (preferred): once `/graphify` has built `graphify-out/graph.json` (a gitignored,
  per-machine cache), `python3 scripts/gen-code-map.py` rewrites this page from the AST graph —
  areas, the most-connected symbols, files by reach, clusters — and `--check` is a board row (exit
  77, a named skip, when the graph is absent or older than the source). Re-run `/graphify --update`
  then the generator after a change that adds, moves or retires an area. `where.mjs` reads the
  same graph.
- **Hand-kept** (until a graph exists): the table below. Update its row **in the same change** that
  adds, moves or retires an area — a code map that drifts is how the next agent learns to grep.

> [!note] Signpost only.
> Adds no decision or scope. It says where things are so the next reader does not re-derive it.

## Areas — the top level

| area | what lives here | open first |
|---|---|---|
| `scripts/` | the org's tooling: `propose.mjs`, `plan-row.mjs`, `where.mjs`, `vault-hubs.mjs`, `loop-state.mjs`, `gen-subject-index.py` | `scripts/where.mjs` |
| `scripts/gates/` | the org's board — vault, plan, ownership, anti-sprawl gates; `org-board.sh` runs them all | `scripts/gates/org-board.sh` |
| `scripts/hooks/` | the PreToolUse contract hook and its falsification suite | `scripts/hooks/agent-contract.mjs` |
| `scripts/lib/` | one owner per shared derivation: the protected list, the landing range, commit trailers, argv refusal, git env | `scripts/lib/protected-paths.mjs` |
| `vault/` | mission control (this vault) | [[Home]] |
| `evidence/` | captures of record, linked by path from session notes and reports | `evidence/README.md` |
| {{SOURCE_AREAS}} | *one row per product area: what it is, and the file to open first* | |

## Core abstractions — the most connected symbols

*A change to one of these reaches furthest. One row each: symbol · defined in · why it matters.*

| symbol | defined in | why it matters |
|---|---|---|

## Entry points

*Where execution starts: the CLI, the server, the build, the test command.*
