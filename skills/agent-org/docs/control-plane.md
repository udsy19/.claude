# The vault control plane (design, for review — not implemented)

Status: proposed, 2026-10-07. Not migrated. Code references are to `main` @ `e318f8b`. This document answers the
owner's "vault as the authoritative control plane" brief and the 2026-10-07 hostile audit
(`docs/audit-2026-10/`, branch `audit-2026-10-07`).

## 0. The invariant and the guarantee

> **Invariant.** Anything that can influence what an agent does next exists as a record in the control plane, with
> provenance (who, from which process identity), authority (who may change it), and a lifecycle (which transitions
> are legal). Nothing else is organizational state: not a conversation, not auto-memory, not a prompt, not a process's
> memory, not an untracked file.

> **Guarantee (acceptance test for this design).** A brand-new machine, with zero Claude context and no access to the
> original processes, given only the git remote (code + the `state/journal` branch) and the owner's credentials,
> reconstructs the organization — every goal, task, dependency, assignment, attempt, finding, decision, ruling,
> verification, promotion, release and the next eligible actions — and resumes it, and the rebuilt state's head hash
> equals the original's.

## 1. Canonical store

### 1.1 Decision

**One SQLite database per org is the only writable truth**: `ORG_ROOT/state/org.db` (WAL, `synchronous=FULL`,
`foreign_keys=ON`). It holds an append-only, hash-chained `events` table and entity tables that are updated **in the
same transaction** as the event that changes them. Events are the truth; entity tables are a materialized index that
can be rebuilt from events (and the rebuild is checked in CI).

Everything else is derived:

| Representation | Role | Writable? |
|---|---|---|
| `ORG_ROOT/state/org.db` | canonical state + event log | **yes — only through `orgstate.py`, only by trusted processes** |
| branch `state/journal` on origin | append-only JSONL export of `events` (+ evidence artifacts) — off-host durability, audit, new-machine rebuild source | no: written only by the exporter; every segment carries its first/last seq and hash |
| `vault/**/*.md` projections (Home, Map, Index, Tasks/, Roadmap, …) | human/Obsidian/agent-readable views | no: generated; drift = gate failure |
| git (code branches, main) | external facts: commits, trees | by agents/coordinator as today; *referenced* by SHA from records |
| CI / test logs / process state | external facts | referenced by immutable id/hash |

### 1.2 Why (evaluated alternatives)

| Criterion | SQLite journal + projections (chosen) | Serialized git-backed records, one writer | Hybrid "JSONL file + flock" |
|---|---|---|---|
| Atomic multi-entity transition (claim + lease + event) | yes, one transaction | no: a commit spans files but the index/worktree are not transactional; a crash leaves partial working-tree state | append is atomic per line; multi-record needs a commit protocol |
| Writer serialization across processes | `BEGIN IMMEDIATE` — built in. Measured: 4 concurrent writers, 2 000 hash-chained txs, ~7 000 tx/s, chain intact | needs an external lock; measured ~5.6 commits/s | needs flock |
| Crash safety | measured: `kill -9` mid-stream → 28 612 rows, chain intact, `integrity_check ok` | partial commits / dirty index after kill (audit B-F4b, F4d show this class today) | torn last line, recoverable |
| Queries (eligible work, unverified criteria, claims) | SQL | parse Markdown each time | load everything |
| Two writable truths? | no: DB only; journal/projections are one-way exports with hashes | no, but multi-host pushes fork history (two truths after a partition) | no |
| Multi-host | one authoritative host per org (today's model); others read the journal | merges of concurrent histories | same as SQLite |
| Portability / dependencies | `sqlite3` is in python3's stdlib (macOS, Linux) | git only | none |
| Obsidian | via generated Markdown | native | via generated Markdown |
| Backup / restore | export after every promotion + hourly; restore = replay | push | push |
| Auditability | hash chain, actor + auth per event | git log (author is forgeable text — audit A1, A11) | hash chain possible |

Measurements above come from a throwaway 20-line prototype (not shipped): 4 processes × 500 `BEGIN IMMEDIATE`
hash-chained transactions, then `kill -9` during a 1M-row stream; macOS, Python 3.13, `sqlite3` stdlib.

### 1.3 Consistency, crash, multi-host, backup and Git-sync semantics

- **Consistency.** Every state change is one transaction: `INSERT INTO events …; UPDATE <entity tables> …;`. Entity
  tables are a pure function of the event sequence (`orgstate.py rebuild` replays into an empty DB and compares).
- **Crash recovery.** SQLite WAL gives atomic commit. Operations with external side effects (a git ref update, a
  process start) use **intent → effect → outcome** events, with reconciliation at start-up against the external
  fact (§8). Nothing is replayed blindly.
- **Multi-host.** One authoritative host per org owns `org.db`. Other hosts are read-only: they fetch
  `state/journal` and rebuild a local read replica. Running lanes on several hosts against one org needs a network
  writer (a small state service); out of scope for v1 and explicitly *not* emulated with git merges.
- **Durability off host.** `orgstate.py export` appends JSONL segments `journal/<first_seq>-<last_seq>.jsonl` and
  new artifacts to branch `state/journal` and pushes. It runs after every promotion and hourly (replacing the role
  of today's `state-snapshot.sh` for org state). Loss window = events since the last export (bounded to one hour;
  zero for promotions). Export is append-only: a segment is never rewritten; a gap or hash mismatch stops export and
  raises an incident.
- **Git sync.** The journal branch is written only by the exporter (fast-forward only); git-sync never touches it.
  Code branches keep their existing flow.
- **Backup verification.** CI and the hourly job run `orgstate.py verify-journal` (chain, contiguity) against origin.

## 2. Event envelope

```sql
CREATE TABLE events (
  seq         INTEGER PRIMARY KEY,          -- gapless, DB-assigned
  id          TEXT NOT NULL UNIQUE,         -- ULID, 'evt_…'
  ts          TEXT NOT NULL,                -- UTC ISO-8601
  type        TEXT NOT NULL,                -- '<entity>.<verb>', e.g. 'promotion.requested'
  schema      INTEGER NOT NULL,             -- envelope + payload schema version
  entity      TEXT NOT NULL,                -- the entity id this event changes
  actor       TEXT NOT NULL,                -- 'owner' | 'overseer' | 'supervisor:<lane>' | 'worker:<lane>/<agent>'
                                            -- | 'coordinator' | 'verifier' | 'scheduler' | 'system'
  auth        TEXT NOT NULL,                -- how authority was established, from process identity, never from text:
                                            -- 'proc:coordinator@<os-user>', 'os-user:<name>', later 'sig:<fpr>'
  causation   TEXT,                         -- id of the event that caused this one
  correlation TEXT,                         -- run / promotion id grouping a flow
  payload     TEXT NOT NULL,                -- canonical JSON (sorted keys, no whitespace)
  prev_hash   TEXT NOT NULL,
  hash        TEXT NOT NULL                 -- sha256(prev_hash || canonical_json(envelope without hash))
);
```

Rules: workers and supervisors never write events directly — their output arrives as *requests* parsed by trusted
processes, which write events with `actor` set to the requester and `auth` set to the trusted process. A payload
field that came from agent text is stored under `claim.*` and is never interpreted as authority.

## 3. Entity catalogue

IDs are `<PREFIX>-<n>` (zero-padded per type, allocated in the transaction), except content-addressed evidence
(`EVD-n` ↔ sha256) and lanes (`LANE-<name>`). Every entity row carries `created_seq`, `updated_seq`, `state`.

| Entity | Prefix | Key fields | Authoritative writer per field |
|---|---|---|---|
| Goal | GOAL | title, why, success measure, state | owner (overseer records the owner's words, `auth=os-user:<owner>`) |
| Milestone | MIL | goal, title, target, state | owner |
| Mission | MIS | slug, title, NOW, state (running/paused/done), acceptance: [AC] | owner; `state=done` only by the **acceptance evaluator** (§5) |
| Acceptance criterion | AC | mission/task, text, check {cmd, cwd} or `manual`, required (bool), state (unverified/passing/failing) | text & check: owner; state: **verifier only** |
| Task | TASK | title, goal/milestone/mission, lane, impact 1–5, effort 1–5, done_when (→ AC ids), depends_on [TASK], claimed_paths [glob], state, attempt n | definition: owner/overseer/supervisor (proposal → accepted); state: see §4 |
| Dependency | (edge) | from TASK → to TASK, kind (blocks / informs) | owner/supervisor |
| Lane | LANE | name, goal, max_parallel, may_land, base branch, budgets | owner |
| Agent | AGT | kind (worker/supervisor), model, lane | scheduler |
| Assignment / lease | LEASE | task, run, holder, fencing_token, expires_at, state | scheduler (grant/renew/expire) |
| Dispatch / run | RUN | task, lane, agent, base_sha, branch, worktree, brief (context bundle id), pid/launch token, deadline, exit, report EVD | scheduler/coordinator; never the worker |
| Attempt | ATT | task, run, approach (keywords), hypothesis, outcome (worked/failed/rejected/blocked), evidence [EVD], lesson | system from the run's Outcome block (as `claim.*`) + verifier outcome |
| Finding | FIND | text, source (run/report/url), trust (observation/verified), supersedes | worker claims; trust upgrade only by verifier/owner |
| Decision (ADR) | DEC | context, decision, consequences, state | owner / overseer with `Authority: owner` |
| Ruling | RUL | scope (org/lane), text, effective_from, supersedes | owner only |
| Owner question | Q | from (supervisor/lane), text, state (open/answered), answer, answered_by | supervisor asks; owner answers (RUL created if standing) |
| Handoff | HO | task, from run, to run?, objective, done/verified, attempts, broken, next, unverified assumptions (each linked) | system (generated from records at run end, incl. abnormal end) |
| Verification run | VER | subject (PROM/TASK/AC), kind (gate/check/acceptance), cmd, tree_sha, started, ended, exit, env {host, os, tools}, log EVD | **verifier/coordinator only** |
| Evidence artifact | EVD | sha256, bytes, media, produced_by VER/RUN, path `state/artifacts/<sha256>` (0444) | system |
| Promotion | PROM | lane, requested_ref, candidate_sha, target, base_sha, merged_tree_sha, state, target_before, target_after, reason | **coordinator only** |
| Release | REL | target sha, tag, PROMs included, AC states at release, notes | coordinator on owner's instruction |
| Incident | INC | kind (crash, gate bypass attempt, divergence, export gap), detail, state | system / overseer |

## 4. Lifecycles

Task (agents may never set `verified` or `done`):

```
draft ──accept(owner/overseer)──► ready ──claim(scheduler)──► claimed ──start(scheduler)──► running
running ──report(system, from RUN)──► implemented ──verify pass(verifier)──► verified ──accept(evaluator)──► done
running/implemented ──verify fail──► ready (attempt+1) | failed (attempts exhausted)
any open ──block(supervisor/system, reason Q/TASK)──► blocked ──unblock──► ready
any ──supersede(owner/overseer, by TASK)──► superseded
claimed/running ──lease expired / run lost (scheduler)──► ready (attempt+1, handoff HO written)
```

| Transition | Allowed actor | Precondition (checked in the transaction) |
|---|---|---|
| draft→ready | owner, overseer, supervisor (supervisor-created tasks need an accepted proposal) | every AC referenced exists; depends_on acyclic |
| ready→claimed | scheduler | deps all `done`; no live LEASE overlaps `claimed_paths`; lane under budget |
| claimed→running | scheduler | RUN started, launch token recorded |
| running→implemented | system (on RUN finish with an Outcome block and commits on the run's branch) | commits exist on branch; report EVD stored |
| implemented→verified | verifier | every `done_when` AC has a passing VER whose `tree_sha` = the candidate's merged tree |
| verified→done | acceptance evaluator | the task's change is on the target (PROM promoted) and its ACs pass on the target tip |
| mission running→done | acceptance evaluator | **every required AC** of the mission has a passing `acceptance` VER with `tree_sha` = current target tip; open tasks are not a criterion by themselves |

Promotion: `requested → verifying → promoted | refused | aborted` (coordinator only).
Lease: `granted → renewed* → released | expired` (scheduler only). Question: `open → answered`.

## 5. Verification, evidence and completion

- The **verifier** is a deterministic process (not a model), run by the coordinator as the org user, outside any
  worker sandbox, using **the target's** copy of gates and checks (audit A2, A3). For each promotion it builds
  `target + candidate` in a temporary worktree and records one VER per gate, project check and acceptance check
  against that exact `merged_tree_sha`. Logs are stored as EVD (sha256, 0444) and exported with the journal.
- Agent-written text ("all tests pass") is stored only as a claim (`claim.*`, ATT/FIND with `trust=observation`)
  and never moves a state.
- **Completion is derived, never asserted.** `DONE` from a supervisor becomes a *request*; the acceptance evaluator
  answers it from the AC/VER tables. A green suite is necessary, not sufficient: a mission is done only when each
  required AC has its own passing VER at the current target tip.
- Acceptance criteria are owner-authored and protected; changing one is an owner event that resets its state to
  `unverified` and re-opens dependent tasks (audit C2 closes the file-level hole today).

## 6. Scheduling and claims

- **Eligible work** (a view): tasks in `ready` whose `depends_on` are all `done`, whose lane is under budget, and whose
  `claimed_paths` overlap no live lease — ordered by `impact/effort` desc, then age.
- **Claim** = one transaction: insert LEASE {task, fencing_token = next monotonically increasing int, expires_at},
  move task to `claimed`, record path claims. Two lanes cannot both claim overlapping paths: the overlap check and
  the insert are in the same `BEGIN IMMEDIATE`.
- **Fencing.** Every later write on behalf of a run carries its fencing token; the writer refuses a token lower than
  the task's current one. An expired worker that comes back cannot overwrite its replacement's state, and its
  branch is never promoted (the PROM records the RUN and token it was built from).
- **Supervisors** keep judgment: they propose task decomposition, dispatch choices among eligible work, and
  promotions — as requests. They no longer own a private plan (`lanes/<lane>/plan.md`, `supervise.py:711-713`).

## 7. Context assembly (dispatch and handoff)

The brief for a RUN is a **context bundle** built by the system and stored as an EVD (so it survives and can be
audited): objective and ACs (authoritative), relevant rulings and decisions (authoritative), the task's prior
attempts and handoffs (linked), findings ranked by relevance to the task's paths/keywords (marked by trust level),
the lane rulings, and the supervisor's free-text instructions — **fenced as untrusted** — with a byte budget per
section and newest-first truncation. Every statement links its record id. Untrusted content (reports, research,
web text, supervisor free text) is delimited, has block markers neutralized, and comes before the authoritative
sections so authority is last (audit C4, A12). Handoffs are generated the same way at the end of every RUN,
including a lost RUN (from its records, not from the worker).

## 8. Reconciliation with external facts

At start-up and every cycle, the coordinator/scheduler reconciles records with external facts, each bound to an
immutable id:

| Record says | External fact | Resolution |
|---|---|---|
| PROM `verifying`, merged commit M | target ref == M | write `promotion.promoted (reconciled)` |
| PROM `verifying` | target ref != M | write `promotion.aborted (reconciled)`; clean temp worktree |
| RUN `running`, launch token T | process with env T alive | keep, re-arm deadline |
| RUN `running` | no such process | `run.lost`; task → `ready` (attempt+1); generate HO; salvage diff to quarantine EVD (never to the branch) |
| LEASE expired | — | `lease.expired`; fencing token bumped |
| target branch diverged from origin | `git rev-list` counts | INC `divergence`; promotions refused until resolved (audit B-F3) |
| projection file differs from regeneration | file hash | gate failure + regenerate (never read back) |

## 9. Projections

Generated by `orgstate.py project` from the DB, never edited, checked by a gate (`--check` exits 1 on drift):
`vault/Home.md` (counts by state, active runs, needs-attention), `vault/Map.md` (typed graph of goals → tasks →
runs → evidence → releases), `vault/Index.md` (decisions only from `DEC`/`RUL` records — never from frontmatter,
audit C3), `vault/Tasks/TASK-n.md` (one page per task with its full linked history), `vault/Roadmap.md`,
`vault/Releases/`. Obsidian sees Markdown with wikilinks and frontmatter mirroring the record (read-only by
convention, enforced by the drift gate). Bases (`*.base`) keep working on that frontmatter.

## 10. Security model

| Actor | Can write | Cannot |
|---|---|---|
| owner | anything, via `orgstate` commands as `os-user:<owner>` (later signed) | — |
| overseer | records the owner's words (RUL, DEC, GOAL…) with the owner's auth; operational fixes | set `verified`/`done` |
| supervisor (read-only model) | nothing directly; its blocks become requests (task proposals, dispatch, promotion, question, learn) | write files, the DB, or authority |
| worker (sandboxed) | its worktree, its report file, its build dir | the DB, `ORG_ROOT`, other worktrees, host credentials, gate/hook code on target (A2), any `verified` state |
| coordinator / verifier / scheduler (org user, outside sandboxes) | PROM, VER, EVD, LEASE, RUN, state transitions per §4 | change ACs, rulings, decisions |

P0 maps in directly: forged trailers grant nothing because authority is `auth` from process identity (A1, A11);
gate code is taken from the target (A2, A3); promotions are scoped to the lane's own runs (A4, F6); workers can't
reach `ORG_ROOT` (A5, A6, A10 via the sandbox); safety-net work is a quarantine EVD (A7, F4c); one serialized
promotion path over the merged tree (F1, F2, F4b, F4d, F7, C1); untrusted content is fenced (C4, A12); `DONE` is
derived (C6). Memory poisoning: findings and lessons carry `trust`; only verifier/owner can upgrade them; nothing
from `claim.*` is ever rendered into an authoritative section.

## 11. Recovery on a new machine

```
1. git clone <origin>; git fetch origin state/journal
2. bootstrap-host.sh <ORG_ROOT>           # host, users, sandbox, timers (as today)
3. orgstate.py restore --journal origin/state/journal --to ORG_ROOT/state/org.db
       replays every segment, verifies the chain and contiguity, rebuilds entity tables,
       prints the head seq and hash (must equal the journal's last hash)
4. owner re-adds secrets and logs workers in      # the only manual step
5. orgstate.py reconcile                    # §8 against git + (no) processes: every RUN running → lost → ready,
                                            #   leases expired, promotions reconciled
6. lanes.sh start                           # the scheduler picks eligible work from the DB
```

Required to pass: no organizational state outside the DB (§12 migration retires every such place); exports after
every promotion; artifacts exported with the journal (size-capped; larger artifacts referenced by hash and kept on
origin LFS or noted as lost with an INC).

## 12. Migration from today (auditor D's inventory → future home)

| Today (file:line) | Future |
|---|---|
| `vault/Plan.md` rows + statuses (`plan-integrity.mjs:200-205`, `plan-row.mjs:50`) | TASK + AC records; `Plan.md` becomes a projection. Import: one TASK per row (id kept as alias), status → state (`done:<sha>` → done with a reconciled PROM) |
| lane `plan.md` (`supervise.py:711-713`) | retired: supervisor PLAN blocks become task proposals/notes on TASKs |
| `lane-memory*.md` LEARN (`supervise.py:714-722`) | FIND/ATT records (`trust=observation`, source = consult); consolidation becomes ranking |
| `owner-questions.md`, `owner-answers.md`, lane `rulings.md`, `.claude/rules/owner-rulings.md` | Q and RUL records; `owner-rulings.md` and lane rulings become projections |
| `reports/`, `prompts/`, `rounds/` (not snapshotted today) | EVD artifacts (report, context bundle, supervisor output) bound to RUN/consult |
| `lane.log`, consult counter (`lanes.sh next_round`) | events; counter = max consult seq |
| process-local `pending`, `candidates`, `FINISHED` (`supervise.py:153, 663-739`) | LEASE/RUN/PROM rows |
| `pids/*.json` (`supervise.py:451-479`) | RUN {launch token, pid, deadline} |
| `loop-state.json` budgets (`supervise.py:156-212`) | events + views |
| `proposals.jsonl` (uncommitted, `propose.mjs:42-52`) | TASK/RUL/DEC proposal records |
| `vault/_log/agents.jsonl` (`usage-hook.sh:22`) | RUN sub-agent events via the hook → coordinator socket (later) |
| Mission frontmatter / NOW, Vision, acceptance bar copies | MIS + AC records; Vision/Mission pages become projections |
| `vault/Decisions/` ADRs | DEC records (ADR text kept as the record body) |
| lanes table in `Design/lanes-and-supervisors.md` | projection of LANE |
| `setup.json`, `settings.local.json` ORG_ROLE, auto-memory pointer | host config (not org state); documented as such |

Steps, each a PR with its test:
1. `orgstate.py` + P0 entities (MIS, AC, PROM, VER, EVD) — written by W2's coordinator now. Test: chain verify,
   rebuild-equals, crash-kill during a promotion → reconcile.
2. Journal export/restore + `verify-journal` in CI. Test: new-machine restore head-hash equality.
3. TASK/LEASE/RUN + scheduler; import `Plan.md`; retire lane `plan.md` and in-memory queues. Test: two lanes,
   overlapping paths → one claim; expired lease + returning worker → fenced.
4. Q/RUL/DEC/FIND/ATT/HO; retire LEARN files, owner-answers, rulings files (→ projections). Test: poisoned report →
   FIND `observation`, never in authoritative context.
5. Projections (Home, Map, Index, Tasks/) + drift gate; delete hand-maintained copies. Test: corrupted projection →
   gate red, regenerated.
6. The full guarantee demo (§13).

## 13. Test plan for the guarantee

Deterministic, script backend + fake workers, both OSes in CI:
- lost worker mid-run (kill -9) → RUN lost, task ready, HO written, salvage quarantined;
- supervisor/loop restart at every transition boundary → no duplicate promotion, no lost event;
- coordinator crash after ref update before outcome event → reconciled promoted; before ref update → aborted;
- conflicting claims from two lanes; stale lease with a returning worker (fencing);
- corrupted projection; truncated journal segment; hash-chain tamper → detected, export halted, INC;
- incomplete verification (one AC failing) → mission not done; DONE request refused;
- malicious inputs: forged trailer, injected `=== LAND` in a report, `type: decision` frontmatter, worker writing
  outside its sandbox → no state change, INC recorded;
- **new-machine demo:** run a two-lane mission partway, kill every process, delete `ORG_ROOT` and the clone, restore
  on a fresh sandbox from origin, assert equal head hash, then resume: the scheduler dispatches exactly the next
  eligible tasks, and the mission completes only with all ACs verified.

## 14. The 16 questions → query or projection

| Question | Answered by |
|---|---|
| What are we building and why? | GOAL/MIS records → `Home.md`, `Vision` projection |
| What is implemented? | tasks in `implemented`/`verified`/`done` + their PROM target SHAs |
| What is independently verified? | AC/TASK with passing VER at tree = target tip |
| What remains unfinished? | tasks not in `done`/`superseded` |
| What is blocked and why? | tasks in `blocked` + blocking Q/TASK |
| Which agent owns each active task? | live LEASE → RUN → AGT |
| What should every idle agent work on next? | the eligible-work view per lane |
| Which tasks depend on others? | dependency edges |
| Which components/files does a change affect? | TASK `claimed_paths` + RUN diffs (EVD) + path claims |
| What has been attempted before? | ATT by task / keywords |
| Why was a decision made? | DEC record and its causation chain |
| What was learned across sessions? | FIND/ATT ranked by trust and recency |
| Which requirements remain unverified? | AC state ≠ passing at target tip |
| What is currently released? | latest REL + its AC states |
| What failed in the last run? | last RUN outcome + its VER/ATT |
| How can interrupted work resume? | §8 reconciliation + eligible-work view + HO records |

## 15. Open decisions for the owner

1. Single authoritative host per org in v1 (multi-host needs a network state service later) — accept?
2. Artifacts in the journal branch: size cap (proposed 1 MB per artifact; larger kept by hash only) — accept?
3. Owner authority: OS identity now, signed owner commands (`ssh-keygen -Y sign`) later — or signatures in v1?
4. Supervisor-created tasks: auto-accepted within the lane's goal, or every new task needs the overseer's accept?
5. Export cadence: after every promotion + hourly (loss window ≤ 1 h for non-promotion events) — or after every event?

## 16. Risks

- The DB is a single file on one host: disk loss between exports loses up to an hour of non-promotion events
  (mitigation: export cadence; option 5).
- Projections must never be read back as truth; a careless script that parses `Plan.md` would recreate two truths
  (mitigation: the drift gate + a lint that forbids reading projection paths from scripts).
- The verifier is only as good as the owner's acceptance checks; vague ACs give vacuous verification
  (mitigation: AC must name a check or be `manual` with an owner sign-off event).
- Migration of existing vaults is lossy where today's state was never recorded (reports, rounds); the import marks
  those as `INC` gaps rather than inventing history.
