# Session handoff protocol (the overseer's duties)

## Opening a session
1. Read `vault/Home.md`, then the newest `vault/Sessions/` note, then MEMORY.md (auto-loaded).
2. Run `lanes.sh <ORG_ROOT> status`. Read each lane's `owner-questions.md` tail, and the event-feed
   backlog since the last session: above all `DONE NOT verified` (a halted lane), `RECONCILED`,
   `RECOVERED` and `UNISOLATED`.
3. Answer what you can from the owner's standing rulings (`.claude/rules/owner-rulings.md`, then the lane's
   `rulings.md`). Relay what you can't to the owner, in plain
   words, with images.
4. Re-arm tracking: arm a Monitor on `lane-events.sh` yourself, and ask the owner to start the heartbeat
   with `/loop Follow .claude/loop-prompts/org-tracker.md` (a session can't start `/loop` itself). If they
   don't, say that tracking only runs while this session is open.

## During a session
- **Owner answers:** append each to the lane's `owner-answers.md` (raw, append-only: its own
  `## <date> · <question>` section, the owner's words), then curate the lane's `rulings.md` (the law in
  force: add the ruling, remove what it supersedes). Consults read `rulings.md` whole and only the newest
  raw answers.
- **Rulings:** a standing, project-wide ruling goes into `.claude/rules/owner-rulings.md` in the owner's
  words, committed with `Authority: owner`; a ruling for one lane goes into that lane's `rulings.md`.
- **Corrections and preferences:** how the owner wants work done, and preferences that hold across
  projects, go to auto-memory with the why. Auto-memory points at the rulings file; it never copies it.
- **Infrastructure:** fix what is safe (orphan processes, ownership, stuck loops); report the rest.
- **Spot-checks:** audit finished workers against their artifacts, not their claims.

## Closing a session (or when the hook demands it)
1. Write or append `vault/Sessions/YYYY-MM-DD-<slug>.md` from `vault/Templates/session.md`, then
   `node scripts/vault-hubs.mjs` (hub-links it) and `python3 scripts/gen-subject-index.py`.
2. Update the `Home.md` NOW table if the facts changed. Promote lane LEARN entries that hold beyond
   the lane into the "Promoted lessons" block of `vault/Index.md` (between its PROMOTED markers — the
   generator carries that block verbatim; anything outside it is regenerated).
3. Answer every open proposal (`node scripts/propose.mjs --list`, plus the ones sandboxed workers put in
   their reports' `## Open questions`) with a measurement or a decision note.
4. `bash scripts/gates/org-board.sh` (must exit 0), then commit with `Authority: owner|supervisor` if
   protected paths changed. Push to main only if the owner allowed it (a push to main may deploy);
   otherwise git-sync carries the work to the host's lane branches.
5. If the owner is leaving, say whether tracking keeps running. Never let questions go unanswered
   overnight in silence.
