---
type: dashboard
status: current
date: {{DATE}}
updated: {{DATE}}
owner: supervisor
---

# AGENTS — read this before you touch anything

You are a subagent on {{PROJECT}}. This page is the **dictionary**: it does not hold the
answers, it tells you **where every answer lives**, so you never grep the whole tree to learn
something this repo already knows.

Reading it is **enforced**, not suggested: `scripts/hooks/agent-contract.mjs` refuses your first
`Edit`/`Write` of a session and delivers this page in the refusal. Everything in a repo that is
merely written down, rather than gated, rots.

---

## 1. Where to look — the routing table

**Never grep for something on this table. Open the file.**

| you need to know | open this | not this |
|---|---|---|
| which code is where, what to open first | [[Map-code]] | grep over the source tree |
| **who already implements a given thing** | `node scripts/where.mjs <name> --branches` — the AST graph (when built), then `git grep` on MAIN (named in the heading, with its commit), then your own HEAD in a section of its own, then every unlanded `lane/*` branch, listing a branch hit only when its CONTENT differs from main and from the branch's own merge-base. [[Map-code]] is a STRUCTURE map: it cannot answer "who already does X", and an agent sent to it for that concludes nothing exists and writes a second one. | the map |
| whether the thing you need is on MAIN at all | `node scripts/where.mjs <symbol>` — `ON MAIN` greps main, `ON THIS BRANCH (HEAD)` is separate. A plan row can name a symbol that exists only on an unlanded branch, which is exactly how a second implementation gets written. | assuming main has it |
| which lane owns what, how the supervised lanes run | [[Design/lanes-and-supervisors]] | asking the supervisor |
| **who may write what** — owner / overseer / supervisor / worker / sub-agent, and what enforces it | [[Architecture#The authority matrix — who may WRITE what]] | assuming you may |
| **how to talk to anyone** — the only channels between agents, and which file each is | [[Design/lanes-and-supervisors#Communication — the only channels]] | messaging another agent directly |
| **where your research findings go** — Research vs Reports vs LEARN vs Index | [[Design/lanes-and-supervisors#Where research findings go]] | a finding that lives only in your context |
| what the supervisor remembers between consults | [[Design/lanes-and-supervisors#Persistent supervisor memory]] | auto-memory (overseer-only) |
| what has already been decided, measured or tried | [[Index]] | grep over every report |
| what decision BINDS right now | `vault/Decisions/` (also listed first in [[Index]]) | a session note that mentions it |
| what work exists and in what order | [[Plan]] — **the ordered queue** | inventing a task |
| **your own row, in full** | `node scripts/plan-row.mjs <id>` — a plan outgrows what one Read returns, and a row graded from a partial view is a row guessed at | reading Plan.md and hoping your row was in the part you got |
| what "done" means for a whole track | [[Roadmap]] | [[Plan]] |
| what the machine that builds this is, and which rules are enforced vs merely declared | [[Architecture]] | folk knowledge |
| where every note in the vault is | [[Map]] | `ls vault/` |
| the laws a gate must obey | `.claude/rules/gate-independence.md` (loads when you touch a gate, hook or test) | — |
| why a law exists, and its worked case | [[Design/gate-independence-cases]] | asking |
| which lines are live right now | [[Reports/audits/SESSION-REGISTRY]] | guessing from branch names |

**Your own role card** is `.claude/agents/<your-role>.md`. It is narrower than this page and
it wins on anything it covers.

## 2. The hierarchy

```
owner ──────────── sets vision, rules on blocked decisions, owns Decisions/
  └── supervisor ── owns Plan.md and Roadmap.md. Assigns work. Decides disputes.
        └── subagent (you) ── does ONE plan row. Writes code, tests, evidence,
                              a session note. Proposes; never decrees.
```

**You may write:** code, tests, gates, evidence under `evidence/<your-dir>/` (with a
README), reports under `vault/Reports/`, and your own session note in `vault/Sessions/`.

**You may NOT write:** `vault/Plan.md`, `vault/Roadmap.md`, `vault/Decisions/`,
`.claude/rules/`. These are the supervisor's and the owner's. A hook enforces it — an
`Edit` to one of those paths is refused, and tells you what to do instead — and a landing gate
re-checks every commit, because the hook cannot see a Bash write.

## 3. How a task runs

1. The supervisor hands you **one plan row** by number, or a goal brief (a lane worker's brief is
   its row).
2. You open this page, then [[Map-code]] for where the code is, then [[Index]] to check
   **whether this was already done or already tried and rejected.** That check is the
   whole reason this page exists — the failure mode is not a wrong fix, it is the fifth
   rediscovery of the same fix.
3. Before writing any new symbol, the search order in `.claude/rules/no-bloat.md`. Reuse or
   extend; write new last.
4. You read only the files the map routed you to.
5. You do the work, with the gate written **first** and watched red before your change.
6. You delete what your change supersedes, in the same change, and grep that nothing still
   references it.
7. You leave: the change, the gate, the evidence, and a session note naming the row. A lane
   worker leaves its report instead; it writes no session note.

## 4. If you want the plan or the roadmap changed

You cannot edit them. You **propose**:

```bash
node scripts/propose.mjs --row 15 --kind split \
  --why "row 15 is 10-20 subtasks, not one; here is the decomposition"
```

That appends to `vault/_log/proposals.jsonl` (in the main checkout, even from a worktree) and
tells the supervisor. The supervisor must then do one of exactly two things, and record which:

- **reject it citing a measurement** — not an opinion, a number or a file;
- **commission research**, then rule, and write the ruling to `vault/Decisions/`.

A ruling in `Decisions/` is law until superseded, which is what stops the same argument
being had again by the next agent.

## 5. If you think the approach is wrong

Say so — that is your job, not a discourtesy. But **argue with evidence**:

1. State what you predict will happen, and what measurement would falsify you.
2. Take the measurement. A disagreement with no number attached is noise here.
3. File it with `scripts/propose.mjs --kind challenge` (it refuses a `--why` with no number).
4. The supervisor rules and records it.

## 6. The three things that get work rejected here

1. **A gate that could not fail.** Write the gate first, watch it go red, and sabotage it
   afterwards. `.claude/rules/gate-independence.md` is the law; the cases are
   [[Design/gate-independence-cases]].
2. **A claim with no scope.** "Untouched" means untouched *by this change*. An unscoped
   negative aggregates into a false one.
3. **Building what exists, or leaving what you replaced.** Search before you write — [[Index]],
   then `where.mjs --branches`, then `git grep`, then the rules; the order and its reasons are
   `.claude/rules/no-bloat.md` (auto-loaded), and the `pre-edit-scan` skill is its operational
   form. Delete what your change supersedes in the same change.
