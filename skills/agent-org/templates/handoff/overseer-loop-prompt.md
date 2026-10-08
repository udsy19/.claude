Track the {{PROJECT}} lanes on {{HOST}} and keep them healthy. Org root {{ORG_ROOT}}.

Each tick:
1. **Read new events:** `lane-events.sh` (via the armed Monitor) or each lane's `lane.log` tail. Look at
   dispatches, finishes (rc, report present?), MERGE/LAND results and every REFUSED (the coordinator's
   refusal file is `reports/NNNN-zz-<merge|land>-refused-<branch>.md`, with each failed verification's
   log), RECONCILED promotions (a crash interrupted them), `DONE claimed` / `DONE verified` / `DONE NOT
   verified`, RECOVERED leftovers, PIDFILE UNREADABLE, UNISOLATED agents (they ran without the sandbox),
   ASK_OWNER, BUDGET caps, usage limits, UNFILLED, SUPERVISOR ERROR and WORKER AUTH FAILED.
2. **Check each finished worker.** Read its report, check the evidence (screenshots, commits), and confirm
   the report opens with a Vault check. A proposal in its `## Open questions` (a sandboxed worker cannot
   file one) is yours to file with `node scripts/propose.mjs` or answer. A `RECOVERED` agent's leftovers
   are a patch in `lanes/<lane>/recovered/`: read it, never apply it blindly; nothing merges it.
3. **DONE NOT verified** halts the lane with the reasons in `owner-questions.md`: a failing criterion
   needs work (restart the lane with a brief), an empty or wrong Definition-of-done table needs the owner,
   and a manual criterion needs the owner's own `python3 <ORG_ROOT>/promote.py <ORG_ROOT> accept <key>
   --note "…"`. Never accept on the owner's behalf.
4. **New ASK_OWNER:** answer it from the standing rulings (`.claude/rules/owner-rulings.md`, then the lane's
   `rulings.md`) if they cover it. Otherwise tell the owner in one
   or two plain sentences, with images, and append the answer to the lane's `owner-answers.md` when it
   comes (its own `## <date> · <question>` section). Then record the ruling: a project-wide one in `.claude/rules/owner-rulings.md` (`Authority: owner`), a
   lane-only one in the lane's `rulings.md`; replace any ruling it supersedes. Consults show `rulings.md` in full but only the newest 10 raw
   answers, so a ruling missing from `rulings.md` is eventually forgotten.
5. **Health:** load and CPU steal, orphan processes (parent PID 1, finished owner), workers timing out with
   no report (`REPORT OVERDUE`), `NO ACTIONABLE BLOCK` twice in a row (the supervisor's output format or
   login is broken), `KILLED` agents, a loop silent for over 2 h, git-sync DIVERGED or refused pushes,
   repo ownership (the org's one user must own it), disk (`logs/gc.log`; `lanes.sh <ORG_ROOT> gc` by hand), worker and supervisor logins (workers authenticate with the token in `isolation.auth_token_file`), the canonical state (`python3 <ORG_ROOT>/orgstate.py <ORG_ROOT> verify`; the `state/journal` branch on origin keeps up), and the deploy after any LAND. Fix what is safe; report the rest.
6. **Promote memory.** New LEARN entries in `lanes/*/lane-memory.md` that hold beyond the lane (tried and
   rejected, measured, decided) get one line each in `vault/Index.md`, written INSIDE the `INDEX:PROMOTED-BEGIN` …
   `INDEX:PROMOTED-END` markers (the rest of Index.md is generated and is overwritten on regeneration),
   linked to the evidence, appended (never rewrite an earlier line). Commit it (`Authority: supervisor`); push to main only if the
   owner allowed landings on main. Workers' vault notes on unmerged branches never reach main, so this is how that knowledge
   survives.
7. **WEEKLY (Mondays, or the first tick of a new week), compound the memory:**
   - Promote each LEARN entry in `lanes/*/lane-memory.md` that has held for a week (a rejected approach,
     a measured limit, a constraint) into that lane's `context.md` § "What has NOT worked" (one line,
     evidence path), and, if it holds beyond the lane, into the `vault/Index.md` PROMOTED block.
   - Demote entries older than ~90 days that no longer steer decisions: move them from `lane-memory.md`
     and `context.md` into `lanes/<lane>/lane-memory.archive-<YYYYMMDD>.md`, and leave one line linking the
     archive. Prune `rulings.md` of anything superseded.
   - Run `python3 <ORG_ROOT>/lane-metrics.py <ORG_ROOT> --days 7` and note the trend in the session note:
     merges per dispatch, merges and lands refused, missing reports, timeouts, NO ACTIONABLE BLOCK,
   dispatch→merge time.
8. **Show progress:** when something visible lands, publish it for the owner and notify.
9. **Handoff:** keep today's session note current.

Rules: goals not tests; vault first; never force-push; never touch other projects' processes; the owner's
interactive sessions are off-limits.
