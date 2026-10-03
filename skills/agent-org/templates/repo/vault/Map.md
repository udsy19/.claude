---
type: dashboard
status: current
date: {{DATE}}
updated: {{DATE}}
---

# Map of this vault

Every note in `vault/`, grouped by the folder it lives in. This file exists so that no
note is more than **two hops** from [[Home]]: Home links here, and this links everything.
`scripts/gates/vault-reachability.mjs` re-derives that claim from the filesystem and the
bytes of each note, and fails if it stops being true.

> [!note] Signpost only.
> This file adds no vision, decision or scope — it lists what is already here so the
> next reader can find it. Delete it and nothing but navigation is lost; regenerate it
> with `node scripts/vault-hubs.mjs`.

Measured {{DATE}}: **31 notes** over 10 folders.


## Start here — the vault root

- [[AGENTS|AGENTS — read this before you touch anything]]
- [[Architecture|Architecture — what governs the {{PROJECT}} fleet]]
- [[CLAUDE|The vault contract]]
- [[Home|{{PROJECT}} — mission control]]
- [[Index|Index — what has already been decided, measured or tried]]
- [[Map-code|Map of this codebase]]
- [[Plan|Plan of record — the ordered work]]
- [[README|vault/ — mission control]]
- [[Roadmap|{{PROJECT}} — Roadmap & Delivery Checklist]]
- [[SUPERVISOR|SUPERVISOR — the contract for the agent that assigns work]]
- [[Vision|{{PROJECT}} — Vision]]

## `Archive/`

Notes kept for the record only. A note arrives here by being SUPERSEDED, never by being wrong, and only once nothing current links to it (vault/CLAUDE.md). Read one when you need to know what a current decision replaced.

Folder README: [[Archive/README]]

- [[Archive/README|Archive/]]

## `Decisions/`

Decision records, one decision per numbered note. Read before changing anything a decision governs. A decision is law until superseded; only the owner or the supervisor writes here — everyone else files a proposal (scripts/propose.mjs).

Folder README: [[Decisions/README]]

- [[Decisions/0001-vault-is-mission-control|D-0001 — The vault lives in the repo and is mission control]]
- [[Decisions/README|Decisions/]]

## `Design/`

Design specs — how a thing should behave, written before it is built. Read by whoever implements the subsystem the note names.

Folder README: [[Design/README]]

- [[Design/README|Design/]]
- [[Design/gate-independence-cases|Gate independence — the worked cases]]
- [[Design/lanes-and-supervisors|How the work is organised: supervised lanes]]

## `Missions/`

One note per mission: scope, the lanes serving it, and a definition of done that is OWNER-EDITED. Its `## NOW` block is printed into every session. Read the mission you are serving at session open, after Home and the newest session note.

Folder README: [[Missions/README]]

- [[Missions/README|Missions/]]
- [[Missions/{{MISSION}}|Mission — {{MISSION_TITLE}}]]

## `Reports/`

Mission reports, audits and post-mortems — what a lane measured and what it delivered, written after the work. A number in one of these names the gate or session that produced it, or it is a claim.

Folder README: [[Reports/README]]

- [[Reports/README|Reports/]]

## `Reports/audits/`

Standing registers rather than one-off reports. `SESSION-REGISTRY.md` declares which lines are live: read it before taking a branch, write your declaration into it.

Folder README: [[Reports/audits/README]]

- [[Reports/audits/README|Reports/audits/]]
- [[Reports/audits/SESSION-REGISTRY|Session registry — one writer per branch]]

## `Research/`

What exists outside this repo — competitor teardowns, library evaluations and captures. Read before building something that may already exist.

Folder README: [[Research/README]]

- [[Research/README|Research/]]

## `Sessions/`

One note per work session, from `Templates/session.md`: what changed, with commits and evidence paths. The NEWEST note here is read at every session open (vault/CLAUDE.md).

Folder README: [[Sessions/README]]

- [[Sessions/README|Sessions/]]

## `Templates/`

The note shapes an agent fills in. Wikilinks in these files carry deliberate blanks (`D-XXXX-...`, `Design/...`) — they are the form, not broken links, and scripts/gates/vault-reachability.mjs classifies them as TEMPLATE_PLACEHOLDER.

Folder README: [[Templates/README]]

- [[Templates/README|Templates/]]
- [[Templates/capture|<title>]]
- [[Templates/decision|D-XXXX — <title>]]
- [[Templates/design-doc|<title>]]
- [[Templates/mission|Mission — <name>]]
- [[Templates/session|{{date}} — <slug>]]

---

Back to [[Home]]. The vault's own contract is [[CLAUDE]].
