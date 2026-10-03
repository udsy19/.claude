---
name: session-open
description: Open a work session the way the vault contract requires — read vault/Home.md, the newest session note and the mission being served, check the session registry for live lines, declare this session, and state the single next move before touching code. Use at the start of every interactive Claude Code session in this repo (not in a lane worker, whose report is its trail), or when the user says "start", "pick up where we left off", or "/session-open".
---

# /session-open

1. Read, in this order, and quote nothing you did not read:
   - `vault/Home.md` (NOW, next moves, blockers, lines in flight)
   - the newest file in `vault/Sessions/` (its **Next** and **Open questions**)
   - the mission in force (`ORG_MISSION` in `.claude/settings.json`) in `vault/Missions/`
   - `vault/Reports/audits/SESSION-REGISTRY.md` — a `LIVE` declaration you did not write for the
     branch you intended to use means you take a NEW branch.
   - `node scripts/propose.mjs --list` if you are the overseer (`ORG_ROLE=supervisor`): every open proposal is answered
     this session (`vault/SUPERVISOR.md` §4).
2. `git status --short` and `git log -3 --oneline`. If the shared checkout is dirty with work that is
   not yours, do not touch it: work in your own worktree (`git worktree add <path> -b <branch>`).
3. Create the session note now, from `vault/Templates/session.md`, as
   `vault/Sessions/YYYY-MM-DD-<slug>.md` with `outcome: in-progress`, and run
   `node scripts/vault-hubs.mjs` so it is hub-linked. Append a `LIVE` declaration to the registry
   naming branch, worktree, scope, and what you will not touch.
4. Reply to the user with: the NOW item you are serving, the one next move, the branch/worktree,
   and any blocker that needs a human. Then start.

Never begin by re-deriving the vision or reading a long register end to end. Search it.
