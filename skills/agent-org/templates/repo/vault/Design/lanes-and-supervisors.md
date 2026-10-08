---
type: design
status: current
date: {{DATE}}
updated: {{DATE}}
owner: supervisor
---

# How the work is organised: supervised lanes

Each **lane** has a **supervisor** ({{SUPERVISOR_DESC}}). The supervisor plans, briefs, judges and
merges, and writes no code. It directs **worker agents** ({{WORKER_DESC}}), which code, build, run
the real product, take screenshots and research, and may use their own **sub-agents**. An
**overseer** (a Claude session working with the owner, `ORG_ROLE=supervisor`) keeps the organisation
running: it relays the owner's answers, audits evidence, fixes infrastructure, answers proposals
(`node scripts/propose.mjs --list`), promotes lessons into the vault, and writes handoffs. Its contract
is [[SUPERVISOR]]; a lane supervisor's is its `lanes/<lane>/supervisor-brief.md`. Who may write what is
the authority matrix in [[Architecture]].

Runtime: **{{RUNTIME}}** ({{HOST}}). Org root: `{{ORG_ROOT}}`.

## Lanes

| lane | goal | root | branches | parallel | may land on main |
|---|---|---|---|---|---|
{{LANE_TABLE}}

## Rulings every lane carries

The standing ones live in the repo's `.claude/rules/owner-rulings.md` (versioned, owner-only); a lane's own
rulings live in its `rulings.md` (the raw answers in `owner-answers.md`). Auto-memory only points at them.

## Communication — the only channels

Agents never talk to each other directly. Every message travels on one of these channels, and every
channel is a FILE or a tool call somebody can read afterwards.

| from → to | channel | written by |
|---|---|---|
| supervisor → worker | the `=== AGENT ===` brief, prefixed with `agent-rules.md` and `context.md`, given to the worker on stdin (no prompt argument, so no size limit) | `supervise.py` from the consult |
| worker → supervisor | the report file (written in the worker's outbox, copied by the loop to `reports/<round>-<name>.md`; checkpointed; opens with `## TL;DR`), images in `renders/<agent>/`, and the worker's branch (its clone's commits, collected at finish) | the worker |
| worker ↔ sub-agent | the Agent tool's prompt and its return value; findings are folded into the WORKER's report | the worker |
| supervisor → owner | `=== ASK_OWNER ===` → `owner-questions.md` (surfaced by the event feed); a daily spend cap reached is asked the same way | `supervise.py` |
| owner → supervisor | `owner-answers.md` (raw, appended verbatim and dated) and `rulings.md` (the law in force, curated) | the overseer |
| lane ↔ lane | never direct: through `owner-answers.md` notes or the vault | the overseer / the vault |
| anyone → a protected doc | `node scripts/propose.mjs` → `vault/_log/proposals.jsonl`, answered by the supervisor | the proposer |

**Memory flows strictly upward:** sub-agent → worker report → supervisor `LEARN` → overseer →
[[Index]]. Nothing flows sideways, and nothing is remembered only in a context window.

## Where research findings go

```
sub-agent finding ──▶ worker report (reports/<round>-<name>.md)
                          │
          ┌───────────────┴────────────────────┐
          ▼                                    ▼
 vault/Research/<topic>.md              vault/Reports/<topic>.md
 (what exists outside: cited sources)   (what WE measured: command, exit code, evidence path)
          │   both linked from their folder hub (node scripts/vault-hubs.mjs)
          ▼
 lane-local lesson ──▶ supervisor === LEARN === ──▶ lanes/<lane>/lane-memory.md
                                                        │ overseer promotes what holds beyond the lane
                                                        ▼
                               vault/Index.md "Promoted lessons" (one line, with the evidence path)
```

A finding that should BIND becomes a decision: the supervisor or owner writes it to `Decisions/`.

## Persistent supervisor memory

- **`lanes/<lane>/lane-memory.md`** — the supervisor's own append-only `LEARN` journal: durable
  lessons, constraints discovered, owner preferences inferred. Its tail (≤ 15 KB,
  `lane_memory_tail_bytes`) is injected into every consult. Every ~25 consults
  (`lane_memory_consolidate_every`) the supervisor emits a `MEMORY_CONSOLIDATED` rewrite and the raw
  journal is archived as `lane-memory.archive-<stamp>.md`, never lost. `state-snapshot.sh` backs it up
  hourly with the rest of the lane state.
- **What a consult carries (the prompt budget).** The project's `.claude/rules/owner-rulings.md` and the
  lane's `rulings.md` in full, plus the newest 10 raw
  `owner-answers.md` entries (a lane without `rulings.md` gets the whole log); per report its `## TL;DR`,
  first ~2k and last ~3k characters, fenced as `UNTRUSTED WORKER REPORT` with any `===` block markers
  neutralised; the lane branch's `git log -15`, its `diff --stat` against main and
  that of each branch just merged, landed or finished (≤ 6k chars); and up to 12 images: `renders/owner/`
  (and a legacy `renders/latest/`) always, then worker images newer than the previous consult.
- **Weekly, the overseer compounds it:** durable LEARN entries go to the lane's `context.md` "What has
  NOT worked" and the [[Index]] PROMOTED block; entries older than ~90 days move to a linked
  `lane-memory.archive-*.md`; `lane-metrics.py` shows whether the lanes are getting better.
- **[[Index]]** (generated, with the overseer's promoted-lessons block carried verbatim) is injected
  into every consult too, so a supervisor sees what the whole project has decided, measured, tried
  and rejected.
- **Claude auto-memory** (`~/.claude/projects/<project>/memory/`) is the OVERSEER's alone: corrections,
  cross-project preferences, and a pointer to `.claude/rules/owner-rulings.md` (the rulings themselves
  live there). Workers and sub-agents write no memory of any kind (native auto-memory, `memory:`
  frontmatter, `.claude/agent-memory/`) — per-branch copies of a memory store conflict on merge and fork
  the truth; the contract hook refuses a worker's writes to auto-memory and `.claude/agent-memory/`.
  A worker's durable knowledge goes in its report and the vault.
- **Sub-agent depth:** verify that your Claude Code version lets a worker's sub-agent spawn further
  agents before relying on it; if nested Agent-tool calls are not allowed, the worker does all the
  fan-out itself.

## The machinery

| file | role |
|---|---|
| `{{ORG_ROOT}}/supervise.py <lane-root>` | One loop per lane, run by the org's one user. **Rolling:** the supervisor is consulted whenever any worker finishes. Each worker runs inside the sandbox runtime (`docs/isolation.md` in the kit) in its own clone, its own process group, with a deadline and a launch token in `pids/<name>.json`; a restarted loop adopts running workers whose token matches. Directives: `PLAN`, `AGENT`, `KILL`, `ASK_OWNER`, `LEARN`, `DONE`; `MERGE` and `LAND` are *requests* the loop passes to the coordinator. Worker reports reach the supervisor fenced as untrusted data. |
| `{{ORG_ROOT}}/promote.py` | The org's one promotion coordinator: the only process that moves a lane's integration branch or main, under one lock. MERGE: only a branch this lane dispatched; LAND: only `lane/<lane>/integration`, refused while main is behind or diverged from origin. It builds target + request in a throw-away worktree, regenerates hubs and Index inside it, runs the landing gates with main's code and every org.json `verify` command on that exact tree, and moves the ref by compare-and-swap. Every request, verification (log stored content-addressed) and outcome is an event in `{{ORG_ROOT}}/state/org.db`; an interrupted promotion is reconciled on the next start. `done` derives mission DONE from the Definition-of-done table on main; `accept <key>` is the owner accepting a manual criterion. No `verify` configured = every MERGE and LAND refused. |
| `lanes/<lane>/context.md`, `supervisor-brief.md`, `agent-rules.md`, `owner-answers.md`, `rulings.md`, `lane.json` | The lane's brief and settings. The owner's answers are appended to `owner-answers.md`; the ones in force are curated into `rulings.md`. |
| `lanes/<lane>/lane-memory.md` | The supervisor's LEARN journal (above). |
| `lanes/<lane>/reports/`, `renders/<agent>/`, `renders/owner/`, `plan.md`, `loop-state.json` | Worker reports (`<round>-<name>.md`, zero-padded so they sort; `## TL;DR` first; checkpoint within 1 h, updated every 2 h), worker images and the owner's pinned references, the supervisor's plan, and the loop's own state (last consult time, overdue warnings, notices for the next prompt). |
| `lanes.sh` | Lane management: `new`, `start`, `restart` (keeps workers alive), `stop`, `status`, `gc` (hourly — launchd, crontab, a systemd user timer or tmux: merged, finished agent workspaces + build dirs, renders > 14 days; never a workspace a live process uses). `start` resumes a stopped lane. |
| `lane-metrics.py` | Per-lane, per-day consults, dispatches, finishes, missing reports, timeouts, merges (ok / refused / of them conflicts), lands (ok / refused), KILLs, NO ACTIONABLE BLOCKs, reconciled promotions, DONE verified / not verified, median dispatch→finish and dispatch→merge. |
| `git-sync.sh` | Every 5 min: hands `main` to `promote.py sync-main` (under the promotion lock: fast-forward from origin if behind, push only if `sync.push_main`, default false; never force; if both moved, DIVERGED is logged and LAND is refused until reconciled), and pushes every work branch. |
| `state-snapshot.sh` | Hourly: copies each lane's recovery state (`plan.md`, `lane-memory*.md`, `rulings.md`, `owner-questions.md`, `lane.json`, `loop-state.json`, the lane's goal in `context.md` and `supervisor-brief.md`, `renders/owner` and `renders/latest`, plus anything in `state_backup.include`) and `org.json` reduced to an allowlist of known-safe keys (any other key is named in the snapshot log) to branch `{{STATE_BRANCH}}`, and pushes it to origin — anyone who can read origin can read it. |
| `lane-events.sh` | The overseer's event feed: dispatches, finishes, merges, landings and every `REFUSED`, `RECONCILED` promotions, `DONE` claimed / verified / NOT verified, `RECOVERED` leftovers, `PIDFILE UNREADABLE`, `UNISOLATED` agents, owner questions, usage limits, `BUDGET`/`TOTAL`, `UNFILLED`, `SUPERVISOR ERROR`, and a worker-auth probe. |
| `build-queue` | Machine-wide slots for heavy builds, so parallel workers don't starve the box. |

## Failure modes this design already guards against

Each one happened in practice.
- **Hidden regressions:** a loop optimised one test at a time and moved counts, not the product.
  Guard: goals, not tests; judge by screenshots.
- **Builds nobody switched on:** about 10k lines sat behind flags. Guard: work must reach the button
  the user presses.
- **Overload:** 11 agents on a throttled box all timed out. Guards: the build queue, a parallel cap,
  an 8 h timeout and checkpoint reports.
- **The slowest agent blocked the lane:** guard: rolling dispatch.
- **Host loss:** guards: everything pushed every 5 min, hourly lane-state backup, a bootstrap kit.
- **Root-owned `.git`:** guard: one user runs the whole org and owns the repo; nothing runs `sudo` or
  re-owns a repository.
- **A test polluted the shared `.git/config`:** guard: each worker works in its own clone, inside the sandbox.
- **Half-done work and secrets reaching origin:** guard: no safety-net commit; an agent's uncommitted files become a local `recovered/` patch nobody merges, and only its commits are collected onto its branch.
- **Unverified work landing:** guard: only the coordinator promotes, verifying main + candidate with the org's own `verify` commands.
- **Worker login expired overnight:** guard: an auth probe in the event feed.
- **Supervisor usage limit:** guard: the loop waits it out, and the feed shows it.
- **Owner questions missed overnight:** guard: the feed shows ASK_OWNER, and the overseer must run its
  tracking loop or say it isn't.
- **Bloated prompts, blind merges, stale images, silent no-op consults, stuck agents, full disks:**
  guards: the prompt budget above, the code view, image freshness, `NO ACTIONABLE BLOCK`,
  `REPORT OVERDUE` + `KILL`, and `lanes.sh gc` (table: the kit's `docs/HIERARCHY.md` §5).
- **The same fix rediscovered five times:** guards: [[Index]] (with promoted lessons), `where.mjs`,
  the LEARN journal, and the vault-first report opening.

## Recovery

1. Clone the repo, as the user that will run the org.
2. Restore `{{ORG_ROOT}}/lanes/*` from branch `{{STATE_BRANCH}}`, and `org.json` from it with the keys
   the snapshot log names as not backed up (secrets among them) re-added.
   Rebuild the canonical state from the repo's `state/journal` branch:
   `git -C <repo> fetch origin state/journal && mkdir -p {{ORG_ROOT}}/state && git -C <repo> archive FETCH_HEAD journal | tar -x -C {{ORG_ROOT}}/state`,
   then `python3 {{ORG_ROOT}}/orgstate.py {{ORG_ROOT}} rebuild {{ORG_ROOT}}/state/org.db` (it prints the head;
   `orgstate.py … verify` checks the chain). Evidence log files (`state/artifacts/`) are not in the journal:
   the records and their hashes survive a host loss, the log files do not.
3. Run `bootstrap-host.sh` (remote: phase 1 as root, then phase 2 as the worker).
4. The snapshot does not carry the integration worktree: run
   `lanes.sh new <lane> "<goal>" <parallel> <may_land>` for each lane with the values in its restored
   `lane.json` (it rewrites `lane.json`, re-creates `int/`, and refills only missing or empty files, so the
   restored `context.md` and `supervisor-brief.md` are kept).
5. The owner re-does the logins.
6. Run `lanes.sh start`.
