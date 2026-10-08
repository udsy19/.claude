---
type: dashboard
status: current
date: {{DATE}}
updated: {{DATE}}
owner: owner
---

# SUPERVISOR — the contract for the agent that assigns work

[[AGENTS]] is what a subagent reads. This is what the **overseer** reads: the Claude session
working with the owner, which edits the plan, answers proposals and lands work by hand. Lane
supervisors are read-only processes; they follow their own `lanes/<lane>/supervisor-brief.md`
(see [[Design/lanes-and-supervisors]]), and the loop that runs them (`supervise.py`) does their
merging. This contract lives in the vault, not on one machine, because a contract that exists
only on the build box cannot be read by an agent on the laptop, reviewed in a diff, or held to a
gate.

Run as `ORG_ROLE=supervisor`: the set-up writes it to the untracked `.claude/settings.local.json`,
so worker worktrees never inherit it. That is what lifts the ownership hook — and it is the only
thing that does, so never export it for a subagent. The owner runs as `ORG_ROLE=owner`.

---

## 1. What is yours alone

- **Intent:** `vault/Plan.md` · `vault/Roadmap.md` · `vault/Decisions/` · `vault/Missions/` · `vault/Vision.md` · `vault/Index.md`
- **Contracts and instructions:** `vault/AGENTS.md` · `vault/SUPERVISOR.md` · `vault/Architecture.md` · `CLAUDE.md` (every one) · `.claude/rules/` · `.claude/agents/` · `.claude/skills/` · `.claude/settings.json` · `.mcp.json`
- **Enforcement:** `scripts/gates/` · `scripts/hooks/` · `scripts/lib/protected-paths.mjs` · `scripts/lib/landing-range.mjs` · `scripts/lib/commit-trailers.mjs` · `scripts/lib/git-env.mjs` · `scripts/lib/argv.mjs` · `scripts/loop-guard.sh` · `scripts/loop-guard.count.test.sh` · `scripts/usage-hook.sh` · `scripts/gen-subject-index.py` · `scripts/vault-hubs.mjs` · `.github/workflows/`

A lane never lands a change to any of these, whatever its commit message claims: a trailer is written by whoever makes the commit, so `scripts/gates/plan-ownership.mjs --lane` refuses them outright at a lane's landing. They reach main only as the owner's or overseer's own commits, or as a proposal the owner applies.

Only the two roles `supervisor` and `owner` may write these. `scripts/hooks/agent-contract.mjs`
refuses everyone else's edit, and `scripts/gates/plan-ownership.mjs` re-derives from git which
commits touched them and what authority each claimed. **Every commit you make to one of these
must carry `Authority: supervisor` (or `Authority: owner`, quoting the owner's ruling, or
`Proposal: #<n>`) in its message** — not as ceremony, but because the gate reads the commit, not
your intent, and a plan change nobody can attribute is indistinguishable from drift. Rules and
decisions are the OWNER's: the supervisor writes them only to record a ruling the owner gave.

A commit that GROWS the tracked tree must carry an `EVIDENCE-GROWTH: <reason>` paragraph that
names what it added and why, in words the gate could not have written itself
(`scripts/gates/sprawl.mjs`). Automation may remove the remembering, never the reasoning.

## 2. Assigning work

**One plan row per agent.** Not a theme, not an area — a numbered row, with its acceptance
gate quoted into the prompt. The prompt says: *do row N; read `vault/AGENTS.md` first.*

**Before dispatching, ask whether it is one row.** A row that is really ten is the single
most expensive mistake available: the agent works for hours, nothing is tickable, and the next
agent cannot tell what is left. Decompose it into `N.1 … N.k` FIRST.
`scripts/gates/plan-hierarchy.mjs` holds you to it — a parent is not done while a child is open.

**Give work that does not collide.** Two agents in one file is a merge conflict you chose.
[[Map-code]] is how you check.

### Every dispatch prompt opens with these five lines, verbatim

Copy them in. Do not link to them, and do not assume the role card carries them.

```
You may NOT edit a protected path (scripts/lib/protected-paths.mjs: the plan, missions, vision, contracts, rules, gates, hooks, workflows).
To change one:  node scripts/propose.mjs --row <id> --kind split|reorder|add|done|challenge --why "<reason WITH a number>"
Your row, in full:  node scripts/plan-row.mjs <id>
Which code is where: vault/Map-code.md   ·   who already implements X: node scripts/where.mjs <name> --branches
Already decided or tried: vault/Index.md   ·   full contract: vault/AGENTS.md
```

**Why verbatim, and why not a link.** An edit to a role card in `.claude/agents/` may not reach a
subagent dispatched from the session that made the edit (the registry is cached), and a read-only
role has no `Edit` tool, so the hook that delivers the contract never fires for it. The dispatch
prompt is the ONLY channel you compose fresh every time.

**Three things a dispatch must not do:**

- **Never order an edit to a protected path.** Say instead: *when the row is progressed, file it
  with `scripts/propose.mjs`.*
- **Never dispatch without a worktree, a port and a branch.** An agent in the shared checkout
  watches HEAD move under it mid-task.
- **Never omit what is NOT on main.** A row whose acceptance names a symbol that lives only on an
  unlanded branch sends the agent looking for it on main; it concludes nothing exists and writes a
  second one. Run `node scripts/where.mjs <symbol> --branches` and say where it lives.

## 3. Model tiering

Set the model on every dispatch (the Agent tool's `model` parameter overrides the card, and the
card's `model:` may be cached). Defaults: judgment, landing and disputes on the strongest model;
building, fixing, reviewing and research on the mid tier; mechanical runs (a bench, a browser
drive) on the light tier. **Override up, never silently down**, and say why in the brief.

## 4. Answering proposals — every cycle, without exception

```bash
node scripts/propose.mjs --list
```

Each open proposal is answered with **one of exactly two things**:

- **a measurement that rejects it** — a number, a file, a sha; not "I don't think so";
- **research, then a ruling written to `vault/Decisions/`**, which makes it law until superseded.

```bash
ORG_ROLE=supervisor node scripts/propose.mjs --resolve <n> --verdict accept|reject \
  --because "<the measurement, or the decision note this produced>"
```

**Silence is not a verdict.** An unanswered proposal is how a subagent learns that filing one is
pointless, and after that it stops telling you things.

## 5. When a subagent says the approach is wrong

Take it seriously in proportion to its evidence, not its confidence. You are not obliged to
agree; you ARE obliged to answer in the same currency. **The cost of an unrecorded correct
decision is that it gets made again, worse, by someone with less context.**

## 6. Landing

1. The worker reports; a read-only `reviewer` re-derives the numbers; only on ACCEPT does it land.
2. Run `bash scripts/gates/org-board.sh` on the merged tree. Exit 0 or it does not land; a skip is
   named, never counted as a pass.
3. Tick the plan row **in the same change**, `done:<sha>`, quoting the gate and its exit code, and
   append the Roadmap tick as the LAST line of its "landing ticks" section, then
   `node scripts/gates/plan-integrity.mjs --relocate` and the plain gate.
4. Lift durable findings into the vault (a report, a decision), regenerate the hubs and the Index,
   and keep [[Home]] NOW true.

A lane supervisor's `LAND` is gated by its loop instead: it needs main checked out in the repo and
`plan-ownership.mjs`, `sprawl.mjs` and `protected-paths.mjs` passing on the candidate (with main's gate
code); a refusal is the lane's `reports/NNNN-zz-land-refused-<branch>.md` and a `REFUSED` line in the
event feed. Read it before landing that branch by hand.

## 7. What you are actually optimising

Not agents started. Not rows opened. **Rows finished, per token.** And the thing that actually
goes wrong is not a bad fix — it is **the fifth rediscovery of a fix that already exists**,
because nobody opened [[Index]]. Every prompt you write makes the agent check there first, and
every proposal you accept ends with something written down.
