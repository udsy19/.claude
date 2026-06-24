---
name: ship-fast
description: Optimizes for short cycle time — ship the smallest valuable increment, often, behind flags, instead of batching work into big risky releases. Use when scoping how much to build before shipping, when work is piling up unshipped, when choosing between a big-bang release and incremental delivery, or whenever speed-to-production matters. Ship fast means small + reversible + observable, never reckless.
---

# Ship Fast

## Overview

The fastest way to deliver value and learn is to ship small increments continuously, not to perfect a large batch and release it all at once. Big batches mean late feedback, large blast radius, and painful merges. Small batches mean fast feedback, tiny blast radius, and trivial rollback. "Fast" here is a property of **batch size and reversibility**, not of cutting corners — small, flag-guarded, observable changes are exactly what make speed safe.

This is the cadence that ties together [[incremental-implementation]] (build small), [[autonomous-git-workflow]] (commit/integrate continuously), and [[shipping-and-launch]] (deploy safely). It is the opposite discipline to hoarding work.

## When to Use

- Scoping how much to build before the first ship.
- Work has been in progress for days with nothing released.
- Choosing between one big-bang release and a series of small ones.
- Any time speed-to-production matters.

When **not** to rush: irreversible or high-blast-radius actions — data migrations, public API contracts, security-sensitive changes. There, slow down and pair with [[doubt-driven-development]] and [[security-and-hardening]]. Ship fast applies to the reversible majority of work, not the dangerous minority.

## Process

### Principles

1. **Small batches.** Ship the smallest increment that delivers value on its own. Smaller batch → faster feedback, smaller blast radius, easier review.
2. **Low WIP.** Finish and ship one thing before starting the next. Unshipped work is inventory: it ages, drifts, and hides risk. Keep work-in-progress to one or two streams.
3. **Decouple deploy from release.** Deploy continuously behind a feature flag (off by default); *releasing* is flipping the flag. This lets code reach production long before the feature is "done."
4. **Bias to ship.** A thin correct slice in production today beats a perfect slice next week. Iterate in prod with monitoring rather than polishing in private.
5. **Integrate continuously.** Short-lived branches/worktrees, merged frequently, avoid merge debt (see [[autonomous-git-workflow]]'s worktree parallelization).
6. **Fast feedback loops.** Cheap CI, fast tests, and observability so you learn within minutes of shipping, not days.

### The loop

1. **Slice** to the smallest independently valuable, shippable unit.
2. **Build** it ([[incremental-implementation]]); **commit continuously** ([[autonomous-git-workflow]]).
3. **Ship behind a flag**, off by default.
4. **Verify in production** with monitoring; enable progressively (canary → wider).
5. **Repeat** — keep WIP low, integrate daily, retire the flag once stable.

What makes fast safe: small diffs + flags + observability + an easy rollback. If a change can't be made reversible, that's the signal to slow down — not to ship a big batch carefully.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll ship it all at once when it's done." | Big batches delay feedback and enlarge blast radius. Slice and ship the first valuable piece now. |
| "It's not perfect yet." | Ship a thin, correct slice behind a flag and iterate. Perfect-but-late loses to good-and-shipping. |
| "Long-lived branch keeps it safe until the big merge." | Divergence accumulates merge debt. Integrate frequently. |
| "Feature flags are overhead." | Flags are precisely what let you deploy fast while controlling risk. |
| "Faster means sloppier." | Faster means *smaller and reversible*. Small flagged diffs are safer than big careful ones. |

## Red Flags

- Work in progress for days/weeks with nothing shipped.
- Big-bang releases bundling many unrelated changes.
- Long-lived branches drifting from main.
- "We'll test/integrate it all at the end."
- Risky changes deployed with no flag and no rollback path.

## Verification

- ☐ Each increment is independently shippable and was shipped/merged within a short cycle
- ☐ Risky or incomplete features ship behind a flag, off by default
- ☐ WIP is low; branches/worktrees are short-lived and integrated frequently
- ☐ Every ship has a rollback path (small diff or flag)
- ☐ Monitoring is in place to learn from the ship quickly
