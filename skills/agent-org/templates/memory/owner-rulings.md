---
name: owner-rulings
description: Where this project's standing owner rulings live — a pointer, never a copy
metadata:
  type: reference
---
The owner's standing rulings for {{PROJECT}} live in the repo, in `.claude/rules/owner-rulings.md`: versioned,
owner-only (a protected path), and loaded into every Claude Code session there. A lane's own rulings live in
`lanes/<lane>/rulings.md` under `{{ORG_ROOT}}`.

**Why:** a ruling kept in one person's auto-memory is invisible to the lanes, unreviewable, and lost with the
machine; the repo file is what every agent actually reads.
**How to apply:** when the owner rules, write it into that file in their words and commit with
`Authority: owner`; never copy the rulings into memory. Memory holds corrections about how to work and
preferences that hold across projects. Related: [[org-architecture]].
