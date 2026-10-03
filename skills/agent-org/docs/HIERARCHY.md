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
SUPERVISOR   one per lane (codex or Claude, read-only). Plans, writes worker briefs, judges reports and
  │          screenshots, MERGEs into the lane branch, LANDs on main if allowed, ASKs the owner.
  │  (=== AGENT … === blocks → supervise.py)
WORKER       Claude Code agent: one task, own git worktree + branch, own build dir, an 8 h budget.
  │          Builds, runs the real product, takes screenshots, commits, writes a checkpointed report.
  │  (Agent tool)
SUB-AGENT    a worker's helpers: research, review, parallel exploration; report back to the worker.
```

Each level only issues **goals** downward: goal · vision · what we're building · what hasn't worked. Each
level only accepts **evidence** upward: artifacts, screenshots, paths, and plainly stated gaps.

## 2. Three memory layers (never duplicated)

| layer | answers | lives in | written by |
|---|---|---|---|
| **Auto-memory** | *Who is the owner, and how do they want work done?* Rulings, corrections and their reasons, preferences | `~/.claude/projects/<p>/memory/` (loaded every session) | the overseer, immediately |
| **Vault** | *What does the project know?* Vision, decisions, designs, research, reports, session handoffs | `vault/` (git) | everyone; agents append and write back |
| **Lane state** | *What is the live work?* Plans, consults, briefs, reports, owner Q&A, renders | `<ORG_ROOT>/lanes/*` (hourly snapshot to git) | the loops, and the overseer for owner answers |

## 3. Session handoff
- **Opening:** read Home, the newest session note and MEMORY.md, then `lanes.sh status` and the owner
  questions. Re-arm the Monitor and `/loop`.
- **During:** relay every owner answer to `owner-answers.md`; save every correction to memory with its why.
- **Closing:** write the session note (said, done, running, open, next), update Home NOW, commit and push.
  A hook can refuse to end a turn without one.

## 4. The rules, and what enforces them

Six rules, one file each, in `.claude/rules/` (all auto-loaded except **gate-independence**, which loads
when an agent touches a gate, hook, test or evidence file): **gate-independence** (the 17 laws; their
cases are `vault/Design/gate-independence-cases.md`) · **no-bloat** (search before you write — Index →
`where.mjs --branches` → `git grep` → rules; delete what you supersede) · **goals-not-tests** ·
**vault-first** · **evidence-and-honesty** · **protected-paths** (`vault/Plan.md`, `vault/Roadmap.md`,
`vault/Decisions/`, `.claude/rules/` — supervisor/owner only).

Written down is not enforced. The repo layer ships the mechanisms, and `bash scripts/gates/org-board.sh`
runs them all by exit code:

| rule | mechanism |
|---|---|
| protected paths | `scripts/hooks/agent-contract.mjs` (refuses the Edit tool, delivers `vault/AGENTS.md` on a session's first write) + `scripts/gates/plan-ownership.mjs` (re-derives from git; demands `Authority:`/`Proposal:`) + `scripts/gates/protected-paths.mjs` (every document agrees with the one declaration) |
| proposals, not decrees | `scripts/propose.mjs` → `vault/_log/proposals.jsonl` in the main checkout; `challenge` needs a number |
| plan shape | `scripts/gates/plan-integrity.mjs` (closed status vocabulary, Roadmap citations by quoted words, ticks at the end) + `scripts/gates/plan-hierarchy.mjs` (a parent is not done while a child is open) + `scripts/plan-row.mjs` |
| anti-fluff vault | `scripts/vault-hubs.mjs` (a generated hub per folder + Map), `scripts/gates/vault-reachability.mjs` (every note within 2 hops of Home; no dead links), `scripts/gen-subject-index.py` (Index of what was decided/measured/tried) |
| anti-duplicate | `scripts/where.mjs` (main vs HEAD vs unlanded branches, content-filtered), the `pre-edit-scan` skill, `scripts/gen-code-map.py` (Map-code from the graphify graph) |
| anti-sprawl | `scripts/gates/sprawl.mjs` (tree growth needs an `EVIDENCE-GROWTH:` reason; a new `evidence/<dir>/` needs a README naming a real reader) |
| laws ↔ cases joined | `scripts/gates/rules-index.mjs` |
| session trail | `scripts/loop-guard.sh` (Stop hook) + `scripts/usage-hook.sh` (SubagentStop record) + `scripts/loop-state.mjs --check` |

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
| Root-written `.git` locked the workers out | the sync re-owns `.git`; git runs as the worker user |
| A test wrote its identity into the shared `.git/config` | never run `git config` on the shared repo; tests use temp repos |
| A worktree on a detached HEAD stranded commits | the safety net pushes `HEAD:refs/heads/<branch>` |
| The worker login expired and 9 h were lost overnight | auth probe in the event feed (real auth errors only) |
| The supervisor hit its usage limit | the loop waits it out; the feed shows it |
| Owner questions sat unanswered overnight | the feed surfaces ASK_OWNER; the overseer keeps `/loop` running or says it isn't |
| A secret was pasted into chat | owners type secrets in their own terminal; rotate if leaked |
| A lane started work on stale data (an old snapshot or assumption) | handoff notes record the exact state; agents read branch tips, not memory |
| Consult prompts grew to ~30k tokens: every owner answer ever, 12k chars of each report | `rulings.md` (curated law) in full + only the newest 10 raw `owner-answers.md` entries; per report its `## TL;DR` + ~2k head + ~3k tail |
| The supervisor judged branches it could not see | each consult carries `git log` of the lane branch, its `diff --stat` vs main, and the diff of every branch it merged/landed or whose agent just finished (≤6k chars) |
| Parallel workers hand-edited the generated hubs and conflicted | the loop regenerates hubs after every MERGE/LAND (from a clean worktree, `Authority: supervisor`); a conflict ONLY in hub files is resolved by regeneration; workers never commit hubs |
| The supervisor kept looking at last week's screenshots | workers save to `renders/<agent>/`; a consult sees `renders/owner/` (pinned) + images newer than the previous consult, newest first, ≤12 |
| A consult with no parseable block did nothing, silently | `NO ACTIONABLE BLOCK` in lane.log and the event feed, and quoted back to the next consult |
| A stuck agent held a slot for its whole 8 h budget | `REPORT OVERDUE <slug>` once at 90 min with no report (feed + next prompt); `=== KILL name=… ===` stops it and commits its work |
| Merged worktrees and their build dirs filled the disk | `lanes.sh <ORG_ROOT> gc` hourly before the snapshot: merged + finished worktrees, their `target/<name>`, renders > 14 days (never `renders/owner`) |
| "Is the org getting better?" had no answer | `lane-metrics.py <ORG_ROOT> [--days N] [--json]` from lane.log (dated `YYYY-MM-DD HH:MM` lines; legacy `HH:MM` lines dated from neighbours); the weekly overseer step promotes and demotes memory |

## 6. Files
- `SKILL.md`: the one-prompt procedure. `README.md`: install and day-to-day.
- `scripts/` (the org layer, runs on the host):
  - `supervise.py`: the lane loop (rolling dispatch, LEARN memory, adoption on restart);
  - `lanes.sh`: new / start / restart / stop / status / gc;
  - `lane-metrics.py`: per-lane, per-day health from the lane logs; `test-supervise.sh`: the offline
    end-to-end test of the loop and its tooling (fake supervisor + fake worker, no network);
  - `bootstrap-host.sh`, `git-sync.sh`, `state-snapshot.sh`, `lane-events.sh` (event feed + auth probe),
    `build-queue`, `org.example.json`;
  - `init-repo.mjs`: installs `templates/repo/` into a project (merge, never overwrite).
- `templates/repo/` — **the repo layer, mirrored 1:1 into the project** (`.tmpl` marks the four protected
  entries, so an agent editing the kit is not refused by the kit's own hook):
  - `vault/`: `Home`, `AGENTS`, `SUPERVISOR`, `Architecture`, `Index`, `Map`, `Map-code`, `Plan`, `Roadmap`,
    `Vision`, `CLAUDE`, `README`; folders `Decisions/ Design/ Missions/ Reports/(audits/) Research/
    Sessions/ Templates/ Archive/ _log/`, each with a generated README hub; the Bases
    (`Design.base`, `Missions.base`, `Sessions.base`); `.obsidian/` config (no per-user workspace);
  - `.claude/`: `settings.json` (SessionStart · PreToolUse · Stop · SubagentStop), `rules/` (six),
    `agents/` (builder, reviewer, researcher, bug-fixer, troubleshooter, browser-tester, ui-designer,
    ab-evaluator), `skills/` (session-open, session-close, capture);
  - `scripts/`: the hook and its test, `lib/`, the gates and `org-board.sh`, `propose`, `plan-row`,
    `where`, `vault-hubs`, `loop-guard`, `loop-state`, `usage-hook`, the Index and code-map generators,
    and the `*.test.*` suites;
  - `evidence/README.md`, `.gitignore`.
- `pre-edit-scan`, `memory-discipline`: sibling skills in the same `skills/` folder as the kit
  (installed into `~/.claude/skills/` if missing — the rules depend on them).
- `templates/memory/`, `templates/lane/`, `templates/handoff/`, `templates/claude/CLAUDE.project-snippet.md`.
