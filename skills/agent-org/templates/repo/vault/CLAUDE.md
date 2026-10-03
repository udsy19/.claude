# The vault contract

This folder is an Obsidian vault and the project's mission control. It is read by humans in
Obsidian and by Claude Code sessions in the repo. The repo's `CLAUDE.md` governs code; this file
governs the vault.

## Reading order for a session

1. `Home.md` — vision, NOW, next moves, blockers, lines in flight.
2. The newest note in `Sessions/` — what the last session did and left open.
3. The mission you are serving in `Missions/` (its `## NOW` block is also printed at session start).
Then the specific design/decision notes those link to. A long register (a ledger, an audit log)
is SEARCHED, never read end to end.

## What an agent may write without being asked

- **A session note** (interactive sessions; a lane worker writes its report instead) in
  `Sessions/YYYY-MM-DD-<slug>.md` from `Templates/session.md`: goal, what
  changed (with commits and evidence paths), what was verified, what is next, open questions for
  the owner. One note per session; append to your own note, never edit another's.
- **Status fields** (`status`, `updated`) in the frontmatter of notes outside the four protected
  paths below, and the NOW / Next / Lines tables on `Home.md`, when the facts changed.
- **Reports and research** under `Reports/` and `Research/` (including `Research/captures/` when
  the owner sent a link), each linked from its folder hub in the same change.

## What an agent may NOT write, and this is ENFORCED

`vault/Plan.md` · `vault/Roadmap.md` · `vault/Decisions/` · `.claude/rules/` · `.claude/settings.json`

Declared once in `scripts/lib/protected-paths.mjs`; refused at the tool by
`scripts/hooks/agent-contract.mjs` and graded again at the landing boundary by
`scripts/gates/plan-ownership.mjs`. `scripts/gates/protected-paths.mjs` holds this page, [[AGENTS]],
[[SUPERVISOR]] and `.claude/rules/protected-paths.md` to that one declaration, so no document can
grant away what the hook refuses.

To change any of them you **propose**, and the supervisor decides:

```bash
node scripts/propose.mjs --row <id> --kind split|reorder|add|done|challenge \
  --why "<what you found, with the measurement that shows it>"
```

Everything else — new vision text, design specs, mission scope — is proposed in the session
note and becomes law only when the owner confirms. A mission's *definition of done* is
owner-edited. Full contract for a subagent: [[AGENTS]]; for the supervisor: [[SUPERVISOR]].

## Conventions

- **Wikilinks** for anything in the vault: `[[Design/lanes-and-supervisors]]`, `[[Decisions/0001-vault-is-mission-control#Decision]]`.
  Paths outside the vault are code paths in backticks, repo-relative: `scripts/where.mjs`.
- **Frontmatter on every note** (properties drive the Bases and the Index):
  ```yaml
  type: session | decision | design | mission | report | research | capture | dashboard | plan | roadmap | vision | spec
  status: proposed | current | in-progress | done | outdated | superseded | archived
  date: YYYY-MM-DD          # created
  updated: YYYY-MM-DD
  supersedes: "[[...]]"      # optional
  superseded_by: "[[...]]"   # optional
  source: <url>              # captures only
  ```
  A mission also carries `state: running | paused | blocked-on-human | done` — the GATING field
  `scripts/loop-guard.sh` reads — plus `accepted-by: owner` and `accepted: <date>` once the owner
  accepts it. At most one mission is `state: running`.
- **Headings.** One `#` H1 per note — it is the note's title everywhere it is listed. Sections are
  `##`. A mission's live block is fenced `## NOW` … `## ---END-NOW`; the SessionStart hook prints
  exactly that span, so nothing outside it briefs the fleet.
- **A new note is LINKED FROM ITS FOLDER HUB IN THE SAME CHANGE that creates it, and a gate
  enforces it.** Every folder has a `README.md` hub saying what it is for and listing its notes;
  [[Map]] lists every note in the vault and is linked from [[Home]]. Run
  `node scripts/vault-hubs.mjs` after adding a note and commit the hub edit beside it (`--check`
  says whether a hub is stale without writing). `node scripts/gates/vault-reachability.mjs`
  re-derives the graph from the filesystem and the bytes of each note, BFSes from `Home.md`, and
  **exits 1 unless every note is reachable within TWO hops**. Two hops rather than "reachable at
  all", because reachability is satisfied by a chain and a chain is not navigation. A note nobody
  can reach is a note the next agent rebuilds.
- **Wikilinks inside backticks are DEAD.** Obsidian does not parse a link inside a code span or a
  fence, so `` `[[Design/x]]` `` renders as text and creates no edge. Write a link as a link. The
  exception is when you are *quoting the syntax* — as this sentence does — and that is exactly why
  the gate strips code before it looks for links.
- **A stale doc is marked, not deleted.** `status: outdated` with a one-line reason at the top;
  `status: superseded` + `superseded_by`. Move to `Archive/` only when nothing current links to it.
- **Numbers carry provenance.** A KPI or count in a note names the gate, script or session that
  produced it, and the commit it was measured on, or it is a claim.
- **Evidence is a path.** Screenshots, logs and captures live in `evidence/` (repo root, outside the
  vault) and are linked by path; a session note without evidence paths did not verify anything.
- **Anti-fluff.** A note says what was decided, measured or built, and where the proof is. No
  restating another note — link it. No emoji in note bodies. Callouts (`> [!note]`) for asides.
- **[[Index]] is generated** (`python3 scripts/gen-subject-index.py`), and so are [[Map]] and the
  folder hubs. Never hand-edit them; regenerate.

## What is NOT here

Machine-read fixtures the gates depend on, and `evidence/`. They stay outside so a vault
reorganisation can never break a gate. Rules Claude loads live in `.claude/rules/`.
