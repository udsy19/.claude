# Hostile audit of agent-org, 2026-10-07 (main @ e318f8b)

Four parallel auditors reviewed the code on `main`, read-only. Every finding below is **verified**: reproduced in a
sandbox with fake binaries and hostile fake workers, or, where it says so, by reading the code or the docs.
Hypothetical risks are listed separately. The scripts in `a/` `b/` `c/` `d/` are the reproductions. They're the
seed of the adversarial regression suite: each one must fail on `e318f8b` and pass after its fix.

## Critical

| ID | Finding | Where | Repro |
|---|---|---|---|
| A1 | A worker's own `Authority: owner` trailer is accepted: a protected `Plan.md` change landed on main | `gates/plan-ownership.mjs:36,83` | `a/attack.sh` (`LAND lane/t/forger ok`) |
| A2 | Gate and hook code isn't protected: one landing that neuters `plan-ownership.mjs` disables the gate for every later landing | `lib/protected-paths.mjs:14`; `gates/protected-paths.mjs:50` | `a/attack2.sh` (`LAND lane/t/planner2 ok`, no claim) |
| A4 / B-F6 | A lane can LAND any well-formed ref: another lane's unreviewed branch, or `origin/…` | `supervise.py` `valid_ref`, `land` | `a/attack2.sh`, `b/s8` |
| A5 | Workers can write their lane's `rulings.md`, `lane.json` and `org.json` (outside git and every hook); forged "owner rulings" reach the next consult | `supervise.py` `run_agent` (exports `LANE_ROOT`) | `a/attack.sh` |
| A6 | Local-mode workers inherit the loop's environment and the owner's HOME (`~/.ssh`, credentials) | `supervise.py` `claude_cmd`/`env_str` | `a/attack.sh` |
| B-F1 / C1 | Nothing runs the project's checks before MERGE/LAND, and the merged tree (main + candidate) is never verified: a lying worker's broken code lands, and two individually passing candidates break main together | `supervise.py` `land_gates`, `land`, `merge` | `c/repro.sh` (`LAND lane/t/liar ok`, then `PROJECT-TEST FAIL`); `b/s1` (`CHECK FAIL: limit*factor=16`) |
| B-F2 | Concurrent LANDs from two lane loops collide in one shared `main` checkout: false CONFLICTs, gates graded against a stale main, the wrong SHA logged | `supervise.py` `land`, `regen_hubs` | `b/race.sh` (4 of 5 trials), `b/s2` |
| B-F4c / A7 | The finish safety net runs `git add -A`, commits with `--no-verify` and pushes a killed agent's partial work, untracked secrets included, to origin; MERGE then accepts it | `supervise.py` `finish` | `b/s4` (`.env` token on origin, `MERGE … ok`); `a/attack.sh` |

## High

| ID | Finding | Where | Repro |
|---|---|---|---|
| A3 | The PR gate workflow runs the PR's own (modifiable) gate code | `templates/repo/.github/workflows/org-gates.yml` | `a/attack2.sh` |
| A9 | MERGE into the integration branch runs no gates, so a poisoned integration becomes every later worker's base | `supervise.py` main loop | `a/attack.sh` |
| A10 | The Claude supervisor (bypass mode, Read and WebFetch) isn't confined to the repo; reads outside it are blocked only by settings the kit doesn't set | `supervise.py` `consult` | documentation (permission-modes), not executed |
| B-F3 | With `push_main: false`, local main diverges from origin permanently after the first LAND; lanes keep landing on a fork | `git-sync.sh:19` | `b/s1` (`DIVERGED main +4/-1`) |
| B-F4a | A truncated pid file orphans a live agent; `gc` then deletes its worktree | `supervise.py` `write_pidfile`, `adopt_running` | `b/s3` |
| B-F4b | A crash between the LAND merge and hub regeneration leaves main red, with no record and no repair | `supervise.py` `land`/`regen_hubs` | `b/s5` |
| B-F7 | Integration branches never pick up main; workers build on stale code | `supervise.py` (no path merges main into integration) | `b/s1` |
| C2 | `vault/Missions/` and `Vision.md` aren't protected: a worker rewrote the mission (`state: paused`, which also silences loop-guard) and it landed | `lib/protected-paths.mjs:13` | `c/repro.sh` |
| C3 | Any note with `type: decision` frontmatter is listed in `Index.md`'s binding "these decide" table: a worker forged binding law | `gen-subject-index.py:87,146` | `c/repro.sh` |
| C4 / A12 | Worker report text reaches the next consult verbatim and unmarked, after the rulings; LEARN persists it | `supervise.py` `report_digest`, LEARN append | `c/repro.sh` (model compliance hypothetical) |
| C6 | `=== DONE ===` is unconditional: declared with open plan rows and a failing acceptance check | `supervise.py` main loop | `c/repro.sh` |

## Medium and low

| ID | Finding | Where |
|---|---|---|
| A8 | The PreToolUse hook covers Edit/Write only and runs from the worker's own worktree; it's advisory, not a boundary | `.claude/settings.json`, `agent-contract.mjs` |
| A11 | `EVIDENCE-GROWTH` and trailers are forgeable text | `lib/commit-trailers.mjs`, `gates/sprawl.mjs` |
| B-F4d | A leftover half-merge from a crash is silently discarded by the next LAND | `supervise.py` `land` (`b/s6`) |
| B-F5 | The adoption guard matches a command-line substring; a foreign process can be adopted, then killed | `supervise.py` `adopt_running` (`b/s7`) |
| C5 | The loop never regenerates `Index.md`; its own LAND leaves the board red | `supervise.py` `regen_hubs` |
| C7 | Safety-net commits look like real work; STOP kills running agents, contrary to the docs | `supervise.py` `finish`, `main` |
| C8 | Two rulings stores with no precedence stated in the prompt; the report contract isn't checked | `supervise.py` `owner_block` |
| C9 | No token or cost accounting; only about 39% of the consult prompt is a stable prefix; metrics measure activity only | `lane-metrics.py`, `supervise.py` |
| C10 | No benchmark comparing agent-org with a single Claude Code agent | — |

## State inventory (auditor D, `d/sim.sh`)

- **Two writable plans:** `vault/Plan.md`, whose statuses are kept by hand, and the lane `plan.md`, which is the only one the loop reads. Nothing links them.
- **Lost by a full restart from git plus the snapshot:** every report, `lane.log` (consult numbers restart), every brief and prompt, every supervisor decision (`rounds/`), the raw owner answers, uncommitted proposals, and the in-memory queue of pending dispatches and candidates.
- **Of the 16 acceptance questions:** only 1 (what are we building and why) can be fully answered from persistent state; 11 only partially. Four can't be answered at all: what's verified, who owns each task, what's next, what's unverified.

## Hypothetical (not reproduced)

- A cross-lane `git merge --abort` cancelling another lane's in-flight merge.
- git-sync's `fetch main:main` contending for the ref lock during a LAND.
- Non-atomic writes truncating `plan.md` or the lane memory on a crash.
- A model obeying instructions injected into a report.
- Supervisor exfiltration through WebFetch (it needs the real CLI to demonstrate).

## Where the external critique was wrong or overstated (for this code)

- **"Restricting Edit/Write doesn't prevent writes":** LAND does re-derive protected-path changes from git, and refused an unclaimed Bash-written plan edit. The holes are that the check is forgeable (A1) and self-modifiable (A2).
- **"Loop state can corrupt":** `save_state` writes to a temp file and renames it. The real gaps are pid files and `plan.md` (B-F4a).
- **"Alive but unresponsive":** deadlines kill the whole process group.
- **"A restart may replay an operation":** the opposite. Interrupted operations are lost or misreported (B-F4b, B-F4d).
- **"The supervisor can redefine acceptance":** the supervisor can't write files; the worker can, because missions are unprotected (C2).
