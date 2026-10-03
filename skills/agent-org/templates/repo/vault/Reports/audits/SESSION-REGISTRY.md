---
type: report
status: current
date: {{DATE}}
updated: {{DATE}}
---

# Session registry — one writer per branch

**One writer per branch; concurrent lines declare themselves at birth.** Two sessions that write one
mission without knowing of each other produce conflicting files, two ledgers and two independent
implementations of one mechanism. Declaration is cheap; rediscovery is not.

## The protocol

1. A session opening work on a branch **reads this file first**.
2. It then **writes its own declaration** below — session id, branch, worktree, scope, what it will
   not touch, state `LIVE` — and commits that before it commits any work.
3. Finding a **live declaration it did not write** for the branch it wanted, it takes a **NEW branch
   named for its line** and proceeds as a declared parallel line. It never writes to the other line's
   branch or worktree.
4. **Worktree attribution extends to branches.** A worktree is owned by the session named in the
   declaration that claims its branch.
5. **Integration of parallel lines is a NAMED PHASE with a single owner** — never an ambient merge.
   The owner of the integration is recorded here before the first port lands.

A declaration is retired by marking it `FINISHED` with its closing state (board line, commits), not by
deletion — a line that ended is evidence. **A stale `LIVE` is worse than no declaration**: the
session-close skill retires it.

## Declarations

*Newest last. One heading per line:*
*`### <branch> — <session / lane> · **LIVE (declared YYYY-MM-DD HH:MM UTC)**` then worktree, scope,
will-not-touch, and on close `**FINISHED <date>** — <closing state>`.*
