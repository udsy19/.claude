---
type: mission
status: current
date: {{DATE}}
updated: {{DATE}}
owner: supervisor
accepted-by: owner
accepted: {{DATE}}
state: running
---

# Mission — {{MISSION_TITLE}}

## NOW

**Accepted by the owner, {{DATE}}.** This mission is in force: `.claude/settings.json` names it in
`ORG_MISSION`, the SessionStart hook prints this block into every session, and
`scripts/loop-guard.sh` gates on this note's `state:`.

**The goal:** {{MISSION_GOAL}}

**The bar:** {{ACCEPTANCE_BAR}}

**What has NOT worked** (so nobody repeats it): {{NOT_WORKED}}

**First moves:** Plan rows 1–2 (`node scripts/plan-row.mjs 1`).

*Everything between `## NOW` and `## ---END-NOW` is printed at the start of every session, so keep
it short, current and in the owner's words. Rewrite it; never append history here.*

## ---END-NOW

## Goal

The end state in one paragraph, and the NOW item on [[Home]] it serves.

## Definition of done

*Owner-edited. One row per property, each with the gate or browser check that proves it.*

| # | property that must hold | gate or browser check that proves it | status |
|---|---|---|---|

## Pre-registration

Before any fix: the observation, the hypothesised cause, the gate that will go RED on the unfixed
tree, and what would falsify the hypothesis (see `.claude/rules/gate-independence.md`).

## Lanes

| lane | supervisor | branch | state |
|---|---|---|---|

## Human gates (an agent may NEVER close these)

- *Acceptance of this mission, the owner's verdict on a result, logins and spend.*

## Log

Newest first. One line per iteration: date · what was tried · verdict · evidence path.
