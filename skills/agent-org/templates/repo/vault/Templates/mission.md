---
type: mission
status: proposed
date: {{date}}
updated: {{date}}
owner: supervisor
accepted-by:
accepted:
state: paused
---

# Mission — <name>

## NOW

*Printed into every session while this mission is the one named in `ORG_MISSION`. Short, current,
in the owner's words. It is `state: paused` and unaccepted until the OWNER accepts it — an agent
never fills `accepted-by` (gate-independence law 9).*

## ---END-NOW

## Goal
The end state in one paragraph, and the NOW item on [[Home]] it serves.

## Definition of done
| # | property that must hold | gate or browser check that proves it | status |
|---|---|---|---|

## Pre-registration
Before any fix: the observation, the hypothesised cause, the gate that will go RED on the unfixed
tree, and what would falsify the hypothesis (see `.claude/rules/gate-independence.md`).

## Lanes
| lane | supervisor | branch | state |
|---|---|---|---|

## Human gates (an agent may NEVER close these)
- …

## Log
Newest first. One line per iteration: date · what was tried · verdict · evidence path.
