---
type: decision
status: current
date: {{DATE}}
updated: {{DATE}}
---

# D-0001 — The vault lives in the repo and is mission control

## Context
Agents run in parallel, in worktrees, across sessions and machines, and none of them remembers the
last session. Knowledge that lives in a chat, a context window or one machine's home directory is
rebuilt by the next agent — the "fifth rediscovery" failure.

## Options considered
| option | cost | risk | what it unlocks |
|---|---|---|---|
| knowledge in chat / auto-memory only | none | lost per session, per machine, per branch | nothing durable |
| a wiki outside the repo | a second system | drifts from the code; not in diffs; agents cannot be gated on it | human reading |
| **an Obsidian vault in the repo, gated** | the gates below | none measured | diffs, review, gates, every agent and human reads one source |

## Decision
`vault/` in the repo is the project's mission control, read by humans in Obsidian and by every
agent session. Its contract is [[CLAUDE]]; its routing table is [[AGENTS]]. The plan, roadmap,
decisions and rules are protected (owner and supervisor only, enforced by a hook and a landing
gate). Every note is reachable from [[Home]] within two hops, every folder has a generated hub, and
[[Index]] answers "has this been done before?" in one page. Machine-read fixtures and `evidence/`
stay outside the vault, so a vault reorganisation can never break a gate.

## Consequences
- Every session opens on Home → the newest session note → the mission, and closes with a session note.
- A new note is hub-linked in the same change (`scripts/vault-hubs.mjs`), or the board goes red.
- Changing the plan, roadmap, decisions or rules takes a proposal (`scripts/propose.mjs`) or a
  commit that claims its authority.

## Falsification
If agents are measured rebuilding something the vault records as built, tried or rejected, the
routing failed: check whether [[Index]] listed it and whether the agent's report opened with a
Vault check. `scripts/gates/vault-reachability.mjs` catches a note nobody can reach.
