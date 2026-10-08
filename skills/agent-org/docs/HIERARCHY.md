# The folder-memory hierarchy: how the organisation works, and why

Distilled from running a real product organisation for weeks: five lanes, a codex supervisor per lane, Claude
Opus workers, a VPS. Every guard below exists because its failure actually happened.

## 1. The chain of command

```
OWNER        vision · rulings · spend/access · judges by looking
  │  (chat)
OVERSEER     one Claude session with the owner. Runs no product code. Relays answers, audits evidence,
  │          fixes infrastructure, keeps memory + vault + handoff current, watches the event feed.
  │  (owner-answers.md, briefs, restarts)
SUPERVISOR   one per lane, read-only (codex --sandbox read-only, or Claude with only Read, Grep, Glob,
  │          WebSearch, WebFetch, inside the sandbox). Plans, writes worker briefs, judges reports and
  │          screenshots, REQUESTS merges and landings (the coordinator decides), ASKs the owner.
  │  (=== AGENT … === blocks → supervise.py)
WORKER       Claude Code agent inside the sandbox runtime: one task, own clone + branch, own build dir, an
  │          8 h budget. Builds, runs the real product, takes screenshots, commits, writes a checkpointed report.
  │  (Agent tool)
SUB-AGENT    a worker's helpers: research, review, parallel exploration; report back to the worker.

COORDINATOR  promote.py — not an agent: the one process that moves a lane's integration branch or main,
             after verifying main + the request as one tree. Owns the canonical state (state/org.db).
```

Each level only issues **goals** downward: goal · vision · what we're building · what hasn't worked. Each
level only accepts **evidence** upward: artifacts, screenshots, paths, and plainly stated gaps.

## 2. Three memory layers (never duplicated)

| layer | answers | lives in | written by |
|---|---|---|---|
| **Auto-memory** | *How does the owner want work done?* Corrections and their reasons, preferences across projects, and a pointer to the rulings | `~/.claude/projects/<p>/memory/` (loaded every session) | the overseer, immediately |
| **Vault + rules** | *What does the project know, and what is its law?* Vision, decisions, designs, research, reports, session handoffs; the owner's standing rulings in `.claude/rules/owner-rulings.md` | `vault/`, `.claude/rules/` (git) | everyone appends to the vault; rulings only with `Authority: owner` |
| **Lane state** | *What is the live work?* Plans, consults, briefs, reports, owner Q&A, renders | `<ORG_ROOT>/lanes/*` (hourly, the recovery subset is snapshotted to a branch pushed to origin) | the loops, and the overseer for owner answers |

## 3. Session handoff
- **Opening:** read Home, the newest session note and MEMORY.md, then `lanes.sh status` and the owner
  questions. Re-arm the Monitor and `/loop`.
- **During:** relay every owner answer to `owner-answers.md`; write a standing ruling into
  `.claude/rules/owner-rulings.md` (`Authority: owner`); save every correction to memory with its why.
- **Closing:** write the session note (said, done, running, open, next), update Home NOW, commit and push.
  A hook can refuse to end a turn without one.

## 4. The rules, and what enforces them

Seven rules, one file each, in `.claude/rules/` (all auto-loaded except **gate-independence**, which loads
when an agent touches a gate, hook, test or evidence file): **gate-independence** (the 17 laws; their
cases are `vault/Design/gate-independence-cases.md`) · **no-bloat** (search before you write — Index →
`where.mjs --branches` → `git grep` → rules; delete what you supersede) · **goals-not-tests** ·
**vault-first** · **evidence-and-honesty** · **protected-paths** (`scripts/lib/protected-paths.mjs`: the plan,
roadmap, decisions, missions, vision, `vault/Index.md`, the contracts, `.claude/`, `.mcp.json`, gates, hooks,
their libraries and CI workflows — the owner's and overseer's; a lane never lands a change to them) ·
**owner-rulings** (the owner's standing law, the one copy).

Written down is not enforced. The repo layer ships the mechanisms, and `bash scripts/gates/org-board.sh`
runs them all by exit code:

| rule | mechanism |
|---|---|
| protected paths | boundary: `scripts/gates/plan-ownership.mjs --lane`, run by the coordinator with main's gate code, refuses any lane landing that touches one, whatever its trailers (`--trusted-commits` skips only the coordinator's own commits, by SHA from the org store); on main, owner/overseer commits carry `Authority:`/`Proposal:`. Advisory: `scripts/hooks/agent-contract.mjs` (refuses the Edit tool, delivers `vault/AGENTS.md` on a session's first write; not a boundary). Sync: `scripts/gates/protected-paths.mjs` (every document agrees with the one declaration, which a real import must use) |
| proposals, not decrees | `scripts/propose.mjs` → `vault/_log/proposals.jsonl` in the main checkout (interactive sessions; a sandboxed worker puts its proposal in its report); `challenge` needs a number |
| plan shape | `scripts/gates/plan-integrity.mjs` (closed status vocabulary, Roadmap citations by quoted words, ticks at the end) + `scripts/gates/plan-hierarchy.mjs` (a parent is not done while a child is open) + `scripts/plan-row.mjs` |
| anti-fluff vault | `scripts/vault-hubs.mjs` (a generated hub per folder + Map), `scripts/gates/vault-reachability.mjs` (every note within 2 hops of Home; no dead links), `scripts/gen-subject-index.py` (Index of what was decided/measured/tried) |
| anti-duplicate | `scripts/where.mjs` (main vs HEAD vs unlanded branches, content-filtered), the `pre-edit-scan` skill, `scripts/gen-code-map.py` (Map-code from the graphify graph) |
| anti-sprawl | `scripts/gates/sprawl.mjs` (tree growth needs an `EVIDENCE-GROWTH:` reason; a new `evidence/<dir>/` needs a README naming a real reader) |
| laws ↔ cases joined | `scripts/gates/rules-index.mjs` |
| session trail | `scripts/loop-guard.sh` (Stop hook; stands down for lane workers and headless supervisors) + `scripts/usage-hook.sh` (SubagentStop record) + `scripts/loop-state.mjs --check` |
| headless roles | `agent-contract.mjs` refuses every write from a headless lane supervisor, and a lane worker's writes to the session trail and memory (`vault/Sessions/`, `vault/Home.md`, the session registry, auto-memory; `WORKER_OFF_LIMITS` in `scripts/lib/protected-paths.mjs`) |
| promotion | `promote.py`, the only process that moves integration or main, under one lock: MERGE only a branch this lane dispatched, LAND only `lane/<lane>/integration` (never another lane's ref, `origin/*` or `recovered/*`), refused while main is behind or diverged; it builds main + the request in a throw-away worktree, regenerates hubs and Index there, runs the landing gates (main's code) and every org.json `verify` command on that exact tree, records each result with its log as immutable evidence, and moves the ref by compare-and-swap. No `verify` = refused. A refusal is `reports/NNNN-zz-<merge|land>-refused-<branch>.md` and a `REFUSED` line in the feed. On GitHub, `.github/workflows/org-gates.yml` runs the base branch's gate code on every PR |
| completion | `=== DONE ===` is a claim: `promote.py done` passes only when every row of the mission's Definition-of-done table has a passing acceptance verification of main's current tree (manual rows: the owner's `promote.py accept`); otherwise the lane halts and the owner is asked |
| state | `orgstate.py`: `<ORG_ROOT>/state/org.db` (SQLite, append-only hash-chained events + entity tables in one transaction), content-addressed evidence in `state/artifacts/`, exported to the repo's `state/journal` branch after every promotion; a crash-interrupted promotion is reconciled against the ref on the next start; `orgstate.py rebuild` replays the journal into a fresh db |
| containment | every worker and a Claude supervisor run inside the sandbox runtime (`docs/isolation.md`): own clone, writes only to its workspace / outbox / renders / HOME / build dir, no reads of the owner's HOME, `ORG_ROOT` or the main repo, network only to Claude and `isolation.allowed_domains`, scrubbed environment, hooks run from main's scripts extracted to `ORG_ROOT/trusted/<sha>/`; leftovers become a local `recovered/` patch, never a commit; reports reach the supervisor fenced as untrusted |
| supervisor output | names in `AGENT`/`KILL` must match `^[a-z0-9][a-z0-9-]{0,40}$`; refs in `MERGE`/`LAND`/`base=` must pass `git check-ref-format --branch` and not start with `-`; anything else is refused back to the supervisor |
| spend | per lane per UTC day: `max_consults_per_day`, `max_agent_starts_per_day`, `max_agent_hours_per_day` (defaults 100, 40, 48); a breach is logged (`BUDGET`), asked of the owner, and the lane idles until midnight UTC or `STOP`; a `TOTAL` line keeps the running count |

**Where the org's contracts live (one place each — read them there, not here):**
- *Code map for workers and sub-agents* — `templates/repo/vault/Map-code.md` (format, and how it is
  generated or kept) and `scripts/where.mjs` ("who already implements X").
- *Authority matrix* (owner / overseer / supervisor / worker / sub-agent × what they may write, and what
  enforces it) — `templates/repo/vault/Architecture.md` § The authority matrix.
- *Agent-to-agent communication*, *where research findings go*, and *persistent supervisor memory* (the
  `lane-memory.md` LEARN journal written by `supervise.py`) — `templates/repo/vault/Design/lanes-and-supervisors.md`.

**Recommended add-on (not built):** a read-only search CLI over `vault/`, `lanes/*/reports/` and
`lanes/*/lane-memory.md`, in the style of `where.mjs` (named sources, exit 1 on nothing found, exit 2
on a failed search), so a supervisor can ask "did any lane already learn X?" in one command.

## 5. Failure modes already designed out (keep these guards)

| happened | guard |
|---|---|
| A test-driven loop: 3 tests turned green and 7 turned red, and the product didn't change | goals not tests; judge screenshots of the real path |
| 10k lines built behind flags nobody turned on | work must reach the button the user presses |
| 11 parallel agents on a throttled box all timed out | build-queue slots, parallel caps, 8 h timeout, checkpoint reports |
| One slow agent blocked finished work for 7 h | rolling dispatch: re-consult on every finish |
| The host was reinstalled | push every 5 min; hourly lane-state branch; bootstrap kit |
| Root-written `.git` locked the workers out | one user runs the whole org (local: the owner; remote: `worker_user`); nothing runs `sudo` or re-owns a repository |
| A test wrote its identity into the shared `.git/config` | each worker works in its own clone, inside the sandbox; tests use temp repos |
| The safety net committed and pushed a killed agent's half-done work, an untracked `.env` with it (audit 2026-10) | no safety-net commit: leftovers become a local `recovered/` patch nobody merges; only an agent's own commits are collected onto its branch |
| A worker's own `Authority: owner` trailer landed a plan edit, and a landed edit neutered the gates (audit 2026-10) | lanes never land protected changes; the gates and hooks are protected, and the coordinator runs main's copy of them |
| A lying worker's broken code landed, and two passing branches broke main together (audit 2026-10) | the coordinator verifies main + candidate with the org's own `verify` commands before moving any ref |
| The worker login expired and 9 h were lost overnight | auth probe in the event feed (real auth errors only) |
| The supervisor hit its usage limit | the loop waits it out (`usage_limit_wait_s`, read from stderr or a failed exit only, so a reply that mentions "quota" is not a limit); the feed shows it |
| Owner questions sat unanswered overnight | the feed surfaces ASK_OWNER; the overseer keeps `/loop` running or says it isn't |
| A secret was pasted into chat | owners type secrets in their own terminal; rotate if leaked |
| A lane started work on stale data (an old snapshot or assumption) | handoff notes record the exact state; agents read branch tips, not memory |
| Consult prompts grew to ~30k tokens: every owner answer ever, 12k chars of each report | `rulings.md` (curated law) in full + only the newest 10 raw `owner-answers.md` entries; per report its `## TL;DR` + ~2k head + ~3k tail |
| The supervisor judged branches it could not see | each consult carries `git log` of the lane branch, its `diff --stat` vs main, and the diff of every branch it merged/landed or whose agent just finished (≤6k chars) |
| Parallel workers hand-edited the generated hubs and conflicted | the coordinator regenerates hubs and Index inside every MERGE/LAND candidate (its own commit, trusted by SHA); a conflict ONLY in hub files is resolved by regeneration; workers never commit hubs |
| The supervisor kept looking at last week's screenshots | workers save to `renders/<agent>/`; a consult sees `renders/owner/` (pinned) + images newer than the previous consult, newest first, ≤12 |
| A consult with no parseable block did nothing, silently | `NO ACTIONABLE BLOCK` in lane.log and the event feed, and quoted back to the next consult |
| A stuck agent held a slot for its whole 8 h budget | `REPORT OVERDUE <slug>` once at 90 min with no report (feed + next prompt); `=== KILL name=… ===` stops it; its commits are kept, the rest quarantined |
| Merged workspaces and their build dirs filled the disk | `lanes.sh <ORG_ROOT> gc` hourly before the snapshot: merged + finished agent workspaces, their `target/<name>`, renders > 14 days (never `renders/owner`, never a workspace a live process uses) |
| "Is the org getting better?" had no answer | `lane-metrics.py <ORG_ROOT> [--days N] [--json]` from lane.log (dated `YYYY-MM-DD HH:MM` lines; legacy `HH:MM` lines dated from neighbours); the weekly overseer step promotes and demotes memory |

## 6. Files
- `SKILL.md`: the one-prompt procedure (`/setup`'s tier 3). `README.md`: install and day-to-day.
- `scripts/` (the org layer, runs on the host):
  - `supervise.py`: the lane loop (rolling dispatch, LEARN memory, prompts on stdin, sandboxed agents,
    MERGE/LAND/DONE as requests to the coordinator, daily caps, pid files with launch tokens in
    `<lane>/pids/` so a restart adopts its own running agents);
  - `promote.py`: the promotion coordinator; `orgstate.py`: the canonical state store (`verify`, `rebuild`,
    `head`);
  - `lanes.sh`: new / start / restart / stop / status (running agents from their pid files) / gc;
  - `lane-metrics.py`: per-lane, per-day health from the lane logs;
  - `bootstrap-host.sh` (local, or remote phase 1 as root then phase 2 as the worker), `git-sync.sh`,
    `state-snapshot.sh`, `lane-events.sh` (event feed + auth probe), `build-queue`, `org.example.json`;
  - `setup.mjs`: the engine behind `/setup` (base config, vault, org; remembers answers in
    `~/.claude/setup.json` and `org.json`); `init-repo.mjs`: installs `templates/repo/` into a project
    (merge, never overwrite);
  - the offline suites (fakes only, no network): `test-supervise.sh` (the loop), `test-host.sh` (host
    scripts, runtime modes, timers, snapshot), `test-init-repo.sh` (install, rulings, PR gate),
    `test-headless.sh` (every hook per role), `test-setup-matrix.sh` (the `/setup` permutations), `test-local-e2e.sh` (a local org end to end:
    setup, two lanes, refused LANDs, adoption, the hourly job's snapshot, STOP); the adversarial suites,
    each red on the pre-P0 kit and run by CI with a control step: `test-adv-authority.sh` (forged
    authority, neutered gates, base-gate PRs, Index forgery), `test-adv-promotion.sh` (scope, merged-tree
    verification, concurrent landings, crash reconciliation, DONE, the state chain),
    `test-adv-isolation.sh` (a hostile worker and supervisor inside the real sandbox; `REQUIRE_SANDBOX=1`
    makes a missing sandbox a failure); `smoke-vps.sh` (remote mode on a real, disposable host;
    `docs/smoke-vps.md`, on its own branch until it has run); `test-vars.json` is their shared vars file.
- `templates/repo/` — **the repo layer, mirrored 1:1 into the project** (`.tmpl` marks the four protected
  entries, so an agent editing the kit is not refused by the kit's own hook):
  - `vault/`: `Home`, `AGENTS`, `SUPERVISOR`, `Architecture`, `Index`, `Map`, `Map-code`, `Plan`, `Roadmap`,
    `Vision`, `CLAUDE`, `README`; folders `Decisions/ Design/ Missions/ Reports/(audits/) Research/
    Sessions/ Templates/ Archive/ _log/`, each with a generated README hub; the Bases
    (`Design.base`, `Missions.base`, `Sessions.base`); `.obsidian/` config (no per-user workspace);
  - `.claude/`: `settings.json` (SessionStart · PreToolUse · Stop · SubagentStop), `rules/` (seven,
    including `owner-rulings.md`),
    `agents/` (builder, reviewer, researcher, bug-fixer, troubleshooter, browser-tester, ui-designer,
    ab-evaluator), `skills/` (session-open, session-close, capture);
  - `scripts/`: the hook and its test, `lib/`, the gates and `org-board.sh`, `propose`, `plan-row`,
    `where`, `vault-hubs`, `loop-guard`, `loop-state`, `usage-hook`, the Index and code-map generators,
    and the `*.test.*` suites;
  - `.github/workflows/org-gates.yml` (the PR gate), `evidence/README.md`, `.gitignore`.
- `pre-edit-scan`, `memory-discipline`: sibling skills in the same `skills/` folder as the kit
  (installed into `~/.claude/skills/` of the user that runs the org if missing — the rules depend on
  them). Beside the kit in the same config: `commands/setup.md` (`/setup`) and `hooks/vault-gate.sh`
  (nudges `/setup` once per session in a git repo without a vault).
- `templates/memory/`, `templates/lane/`, `templates/handoff/`, `templates/claude/CLAUDE.project-snippet.md`.
- `docs/isolation.md` (the sandbox: layers, setup, what remains), `docs/audit-2026-10/` (on branch
  `audit-2026-10-07`: the hostile audit this P0 work answers); `docs/control-plane.md` (on branch
  `p0-design`, under review: the vault control plane the state store seeds).
