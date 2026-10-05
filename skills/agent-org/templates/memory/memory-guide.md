# Memory: what goes where (never duplicated)

| layer | holds | lifetime | who writes |
|---|---|---|---|
| **Claude auto-memory** (`~/.claude/projects/<proj>/memory/`) | WHO the owner is and HOW they want work done: corrections and their reasons, preferences that hold across projects, where things live and why — and a pointer to the rulings file, never a copy of it | across all sessions | the overseer, the moment the owner corrects something |
| **Owner rulings** (`<repo>/.claude/rules/owner-rulings.md`) | the owner's standing rulings for this project | the project's life (in git, protected) | the overseer in the owner's words, `Authority: owner` |
| **Vault** (`vault/`) | WHAT the project knows: vision, decisions, designs, reports, research, session handoffs | the project's life (in git) | every agent: reports, session notes, write-backs |
| **Lane state** (`<ORG_ROOT>/lanes/*`) | the live working set: supervisor plan, consult outputs, worker reports, owner Q&A, renders | the current push, snapshotted hourly to git | the loops, plus the overseer appending owner answers |

## Memory file format
```markdown
---
name: kebab-slug
description: one line used to decide relevance
metadata:
  type: user | feedback | project | reference
---
The fact. For feedback/project, add **Why:** and **How to apply:** lines. Link related memories with [[name]].
```

The supervisor's own lane-local memory is a fourth, narrower store: `lanes/<lane>/lane-memory.md`, its
append-only LEARN journal (see `vault/Design/lanes-and-supervisors.md` § Persistent supervisor memory).
Lessons that hold beyond the lane are promoted by the overseer into `vault/Index.md`.

## Rules
- **Auto-memory is the overseer's alone.** Workers and sub-agents write no memory of any kind (native
  auto-memory, `memory:` frontmatter, `.claude/agent-memory/`): per-branch copies of a memory store
  conflict on merge and fork the truth, and a worker's auto-memory would load into every later session.
  Their durable knowledge goes in their report and the vault.
- **Check first:** before saving, look for an existing memory that covers it, and update that instead of
  duplicating.
- **Don't save what's already recorded:** anything the repo or vault already records (code structure, git
  history) stays out of memory.
- **Convert relative dates to absolute** ("Thursday" → 2026-10-08).
- **Fix wrong memories:** when a memory proves wrong, fix or delete it. Recalled memories are point-in-time;
  verify any file or flag they name before acting on it.
- **Every owner correction becomes a feedback memory, with its why.** That is how the next session doesn't
  repeat the mistake.
