Track the {{PROJECT}} lanes on {{HOST}} and keep them healthy. Org root {{ORG_ROOT}}.

Each tick:
1. **Read new events:** `lane-events.sh` (via the armed Monitor) or each lane's `lane.log` tail. Look at
   dispatches, finishes (rc, report present?), MERGE/LAND, REFUSED blocks and landings (the refusal file
   is `reports/NNNN-zz-land-refused-<branch>.md`), ASK_OWNER, BUDGET caps, usage limits, UNFILLED,
   SUPERVISOR ERROR and WORKER AUTH FAILED.
2. **Check each finished worker.** Read its report, check the evidence (screenshots, commits), and confirm
   the report opens with a Vault check.
3. **New ASK_OWNER:** answer it from the standing rulings (`.claude/rules/owner-rulings.md`, then the lane's
   `rulings.md`) if they cover it. Otherwise tell the owner in one
   or two plain sentences, with images, and append the answer to the lane's `owner-answers.md` when it
   comes (its own `## <date> · <question>` section). Then record the ruling: a project-wide one in `.claude/rules/owner-rulings.md` (`Authority: owner`), a
   lane-only one in the lane's `rulings.md`; replace any ruling it supersedes. Consults show `rulings.md` in full but only the newest 10 raw
   answers, so a ruling missing from `rulings.md` is eventually forgotten.
4. **Health:** load and CPU steal, orphan processes (parent PID 1, finished owner), workers timing out with
   no report (`REPORT OVERDUE`), `NO ACTIONABLE BLOCK` twice in a row (the supervisor's output format or
   login is broken), `KILLED` agents, a loop silent for over 2 h, git-sync DIVERGED or refused pushes,
   repo ownership (the org's one user must own it), disk (`logs/gc.log`; `lanes.sh <ORG_ROOT> gc` by hand), worker and supervisor logins, and the deploy after any LAND. Fix what is safe; report the rest.
5. **Promote memory.** New LEARN entries in `lanes/*/lane-memory.md` that hold beyond the lane (tried and
   rejected, measured, decided) get one line each in `vault/Index.md`, written INSIDE the `INDEX:PROMOTED-BEGIN` …
   `INDEX:PROMOTED-END` markers (the rest of Index.md is generated and is overwritten on regeneration),
   linked to the evidence, appended (never rewrite an earlier line). Commit it (`Authority: supervisor`); push to main only if the
   owner allowed landings on main. Workers' vault notes on unmerged branches never reach main, so this is how that knowledge
   survives.
6. **WEEKLY (Mondays, or the first tick of a new week), compound the memory:**
   - Promote each LEARN entry in `lanes/*/lane-memory.md` that has held for a week (a rejected approach,
     a measured limit, a constraint) into that lane's `context.md` § "What has NOT worked" (one line,
     evidence path), and, if it holds beyond the lane, into the `vault/Index.md` PROMOTED block.
   - Demote entries older than ~90 days that no longer steer decisions: move them from `lane-memory.md`
     and `context.md` into `lanes/<lane>/lane-memory.archive-<YYYYMMDD>.md`, and leave one line linking the
     archive. Prune `rulings.md` of anything superseded.
   - Run `python3 <ORG_ROOT>/lane-metrics.py <ORG_ROOT> --days 7` and note the trend in the session note:
     merges per dispatch, missing reports, timeouts, NO ACTIONABLE BLOCK, dispatch→merge time.
7. **Show progress:** when something visible lands, publish it for the owner and notify.
8. **Handoff:** keep today's session note current.

Rules: goals not tests; vault first; never force-push; never touch other projects' processes; the owner's
interactive sessions are off-limits.
