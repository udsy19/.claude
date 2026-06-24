---
name: autonomous-git-workflow
description: Commits continuously after each working change with simple structured messages, and parallelizes feature work using git worktrees — reserving branches for large or divergent efforts. Use whenever code changes and needs saving to version control: implementing features, adding functionality, fixing bugs, or working on several features at once.
---

# Autonomous Git Workflow

## Overview

Version control is a continuous background discipline, not a step you do at the end. Every working unit of change gets committed immediately with a simple, structured message describing the delta from the previous commit. The default is a single working branch with frequent commits. When several features or ideas are in flight, parallelize them with **git worktrees** rather than switching branches in place. Create a **new branch** only when the work is a genuinely different direction or a large feature that could destabilize the running app — and ask the user first.

## When to Use

Active throughout implementation, automatically:

- **After any functional unit is added and verified** → commit.
- **When working on two or more features/ideations at once** → use a worktree per stream.
- **When the work is a distinct product direction or a large/risky feature** → branch (ask first).

## Process

### 1. Commit continuously

1. Work in small functional units — one behavior, fix, or piece of functionality at a time.
2. The moment a unit works and is verified (build passes, tests green), stage and commit it. Don't batch unrelated changes into one commit.
3. Never commit broken or half-built code to the working line. If you need a checkpoint for experimental work, do it in a worktree/branch.
4. One logical change per commit. If you did two distinct things, make two commits.

### 2. Commit message format

Keep it simple. The message describes the **difference between the last commit and this one** — nothing more. Use bullet points, at most **ten**, one idea each.

```
<concise imperative summary, ≤72 chars>

- what changed versus the previous commit
- the next distinct change in this unit
- ... (maximum 10 bullets, no filler)
- Note: <only if something must be explicitly flagged — breaking change, migration, manual step, follow-up>
```

Rules:
- Bullets describe the **delta**, not the whole system or the obvious.
- No vague one-liners ("updates", "fixes", "wip"). Say what actually changed.
- Include the `Note:` line **only** when there's something explicit to call out. Omit it otherwise.
- If ten bullets isn't enough, the commit is too big — split it.

### 3. Worktrees — the default for parallel work

When juggling multiple features or ideations in the same app, give each stream its own **git worktree** instead of stashing and switching branches in place. Each line of work stays isolated and they progress in parallel — faster, with no context collisions.

```
git worktree add ../<repo>-<feature> -b <feature-branch>   # spin up an isolated tree
# ...implement, commit continuously, push...
# open a PR for the branch
git worktree remove ../<repo>-<feature>                     # tear down when merged
```

Prefer a worktree over serial branch-switching whenever two efforts would otherwise contend for the same working tree. Use them aggressively to get more done in parallel.

**Parallelizing without overlap (so merges stay clean):**

- **Partition by disjoint files.** Before splitting work across trees, list the files each stream will touch and assign so no two trees edit the same files. Overlap is a guaranteed merge conflict. If two streams must touch the same file, either serialize them or factor the shared piece out and land it first.
- **Parallelize the independent; serialize the dependent.** Good split candidates: separate features, separate modules, docs vs. code, test-writing vs. an unrelated feature. Bad: two changes to the same module or API surface — run those in sequence.
- **Keep each tree fresh.** Rebase or merge `main` into each worktree regularly so trees don't drift. The longer a tree lives without syncing, the worse the eventual merge.
- **Merge in dependency order, one at a time.** Land the foundational/shared change first, then rebase the other trees onto the new `main` before merging them. Never merge two large trees simultaneously.
- **Integrate continuously, not at the end.** Small frequent merges beat one big-bang integration (see [[ship-fast]]).
- **Tear down cleanly.** After a branch merges, `git worktree remove ../<repo>-<feature>` and delete the branch so stale trees don't accumulate.

**When NOT to parallelize:** if the streams are coupled (touch the same code) or each is small, the coordination overhead of multiple trees costs more than it saves — just do them in sequence on the working branch.

### 4. Branches — reserved, and ask first

Create a dedicated branch only when **either**:
- the work is a **completely different ideation** / product direction, or
- it's a **large feature that could break** the running application.

For routine changes, stay on the working branch and commit continuously — branching every small thing just fragments history.

Before branching for a big or divergent effort, **confirm with the user**: name the work, say why it warrants isolation, and propose the branch/worktree. Then proceed. If it's clearly routine, don't ask — just commit.

### 5. Pull requests

- Each branch/worktree stream gets its own PR.
- Reuse the same bulleted delta format for the PR description.
- Don't merge without the user's go-ahead unless they've already said to.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll commit everything at the end." | Continuous commits give recoverable history and clear, reviewable deltas. Batching loses both. |
| "It's one feature, so one big commit is fine." | Split by logical unit — `git bisect` and reviewers need granularity. |
| "Branching is safer, I'll branch for everything." | Branch overhead fragments simple work. Default to commit-on-working-branch + worktrees; branch only for divergent/large work. |
| "I'll just switch branches to do the other feature." | Switching serializes work that could be parallel and risks losing your working state. Use a worktree. |
| "The message is obvious, a one-liner is fine." | A one-liner can't answer "what changed since last commit?" Write the bullets. |

## Red Flags

- A finished, verified functional unit sitting in an uncommitted working tree.
- A commit message that's a single vague line with no delta bullets.
- Broken or half-built code committed to the working line.
- Branching for a trivial change — or starting a large/divergent feature on the working line without asking.
- Stashing and switching branches to juggle features instead of using worktrees.
- A `Note:` added when nothing actually needs flagging (noise), or omitted when there's a breaking change.

## Verification

- `git log --oneline` shows one commit per functional unit, each with a structured ≤10-bullet message.
- `git status` is clean after each completed unit.
- `git worktree list` shows parallel features in separate trees, each with its own branch/PR.
- Each commit builds and passes tests on its own — history is bisectable.
