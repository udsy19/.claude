<div align="center">

# `.claude` — Production Claude Code Configuration

**A complete, batteries-included `.claude` folder that doesn't just _contain_ skills — it _uses_ them.**

41 skills · 4 agent personas · 9 slash commands · reflexive skill routing · always-on engineering disciplines · a one-prompt supervised agent organisation

<p>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/skills-41-22c55e" alt="41 skills">
  <img src="https://img.shields.io/badge/hooks-6-8b5cf6" alt="6 hooks">
  <img src="https://img.shields.io/badge/Claude%20Code-ready-d97706" alt="Claude Code ready">
  <a href="https://github.com/udsy19/.claude/stargazers"><img src="https://img.shields.io/github/stars/udsy19/.claude?color=eab308" alt="Stars"></a>
</p>

[Install](#install) · [How it works](#how-it-works) · [What's inside](#whats-inside) · [Agent organisation](#agent-organisation-agent-org) · [The hooks](#the-hooks) · [License](#license)

</div>

---

## Highlights

- **Reflexive routing** — the right skill is suggested on *every* prompt, no slash command required.
- **Always-on disciplines** — verify-don't-hallucinate, no-bloat, continuous-git, memory, and ship-fast run in the background.
- **40 skills across the full lifecycle** — define → plan → build → verify → review → ship.
- **A supervised agent organisation from one prompt** — `/agent-org` sets up lane supervisors, Claude workers and their sub-agents, an Obsidian vault as mission control, 3-layer memory, session handoffs and crash recovery.
- **6 fail-safe hooks** — degrade gracefully with missing deps and never block your prompt (the vault gate refuses one edit per session, on purpose).
- **Best-in-class bundled skills** — design, React/Next, and accessibility from Anthropic, Vercel, AccessLint & more.
- **Token-conscious** — progressive disclosure plus a trimmed session injection keep context lean.

> Drop it into `~/.claude/` (global) or a project's `.claude/` and Claude Code picks everything up automatically.

---

## Why this exists

A pile of skills is only useful if the agent actually *reaches for them*. Most setups leave that to chance. This configuration adds two things on top of a strong skill library:

1. **Reflexive routing** — a `UserPromptSubmit` hook matches every prompt against the skill set and injects a one-line hint, so the agent applies the right workflow *without you typing a slash command*.
2. **Standing disciplines** — a `SessionStart` hook injects a compact operating procedure every session: verify before asserting, don't write redundant or dead code, commit continuously, persist durable memory, ship in small batches.

The result: the folder doesn't just *contain* skills, it *uses* them.

## How it works

```
                     ┌─────────────────────────────────────────────┐
  every session  →   │ SessionStart hook → injects the discovery    │
                     │ flowchart + standing operating procedure     │
                     └─────────────────────────────────────────────┘
                     ┌─────────────────────────────────────────────┐
  every prompt   →   │ UserPromptSubmit hook (skill-router) →        │
                     │ matches intent → suggests the matching skill  │
                     └─────────────────────────────────────────────┘
                     ┌─────────────────────────────────────────────┐
  always         →   │ Native skill discovery: each skill's         │
                     │ description (~100 tokens) is loaded; the      │
                     │ full body loads only when the skill is used   │
                     └─────────────────────────────────────────────┘
```

Three layers, by design:

- **Native auto-discovery** — Claude Code loads every skill's `description` and activates the one that matches your task. Cheap at rest (progressive disclosure).
- **The router** — a deterministic nudge layer so the right skill surfaces reliably, even mid-session when the discovery map has scrolled out of attention. Conservative: it stays silent when nothing matches strongly.
- **Slash commands** — for when you want to *force* a specific workflow (`/spec`, `/plan`, `/build`, `/test`, `/review`, `/ship`, …).

## Install

One command installs the config; after that, `/setup` does the rest from inside Claude Code.

```bash
git clone https://github.com/udsy19/.claude.git claude-config
node claude-config/skills/agent-org/scripts/setup.mjs --scope base --install global
```

That copies `skills`, `agents`, `commands`, `hooks`, `rules` and `references` into `~/.claude/` and merges
`settings.json` into yours: nothing of yours is overwritten, and missing permissions and hook commands are
added. To install into one project instead (shared with your team via git), run it with
`--install project --project your-project`. That also puts `.mcp.json` at the project root, where MCP config
belongs.

Then, in any project, run **`/setup`**. It asks a short tiered interview, with a default on every question,
remembers the answers in `~/.claude/setup.json`, and installs:

| scope | what you get |
|---|---|
| `base` | this config, globally or in the project |
| `vault` | base plus the agent-org vault in this project: Obsidian mission control, rules, gates and the PR-gate workflow |
| `org` | the vault plus a supervised agent organisation: the full [`/agent-org`](#agent-organisation-agent-org) interview, `org.json`, and the host bootstrap |

Re-running `/setup` changes nothing unless you pick "Change answers". An answer that can't be migrated
(say, moving the config from global to project) is refused, with what to do by hand.

> The same `settings.json` works in both scopes: each hook command runs the project's copy
> (`$CLAUDE_PROJECT_DIR/.claude/hooks/…`) if there is one, else the global one (`~/.claude/hooks/…`), and does
> nothing if neither exists.
>
> The cache hooks write to `.claude/sdd-cache/` and `.claude/.simplify-ignore-cache/` inside whichever project
> you work in, so add those two lines to its `.gitignore` (vault projects get them automatically).
>
> In a git repo without a vault, the **vault gate** blocks the first edit of each session once, reminding you to
> run `/setup`. To work there without a vault, `touch .claude/no-vault` or set `ORG_VAULT=off`.

> [!IMPORTANT]
> - Contents go **directly** under `.claude/` (i.e. `.claude/skills/...`), not nested in a sub-folder.
> - `.mcp.json` belongs at the **project root**, next to `.claude/`, not inside it.
> - `.claude/rules/*.md` files without a `paths:` field auto-load every session (that's how `no-bloat.md` is always enforced).

## Requirements

Everything degrades gracefully if a dependency is missing, but for full functionality:

| Dependency | Used by |
|---|---|
| `jq` | all hooks (router, session-start, caches, vault gate) — they silently no-op without it |
| `curl`, `shasum`/`sha256sum` | the `sdd-cache` web-fetch cache hooks |
| `python3` | the `ui-ux-pro-max` skill's design-system CLI |
| Google Chrome + the AccessLint MCP server | the `accesslint-*` live-DOM accessibility skills |
| Claude Code **v2.1.59+** | native auto-memory referenced by `memory-discipline` |
| `node`, `python3`, `git` | the `agent-org` installer, gates and vault generators |
| `tmux`, `flock`, `rsync`, `claude` (and `codex` for a codex supervisor) | the `agent-org` runtime host — checked by its `bootstrap-host.sh` |

## What's inside

41 skills: 40 organized by development phase (including the meta-skill that wires discovery), plus `agent-org` for running agents as a supervised organisation.

<details open>
<summary><b>Define &amp; Plan</b></summary>

| Skill | What it does |
|---|---|
| `interview-me` | Surface what you actually want before any plan or code |
| `idea-refine` | Diverge then converge on an approach |
| `spec-driven-development` | Requirements + acceptance criteria before code |
| `planning-and-task-breakdown` | Decompose into small, verifiable tasks |

</details>

<details open>
<summary><b>Build</b></summary>

| Skill | What it does |
|---|---|
| `pre-edit-scan` | Search for existing code before writing — no duplicates, no dead code |
| `incremental-implementation` | Thin vertical slices, verified one at a time |
| `context-engineering` | Load the right context; token & tool-use efficiency |
| `source-driven-development` | Verify against official docs before implementing |
| `doubt-driven-development` | Cross-examine non-trivial decisions in-flight |
| `api-and-interface-design` | Stable contracts, clear versioning |
| `frontend-ui-engineering` | Production UI with accessibility |
| `frontend-design` *(Anthropic)* | Distinctive, intentional visual design |
| `ui-ux-pro-max` *(nextlevelbuilder)* | Searchable design DB: styles, palettes, fonts, UX rules |
| `controlled-ux-designer` / `innovative-ux-designer` *(bencium)* | Deep UX fundamentals (systematic / bold variants) |
| `react-best-practices` *(Vercel)* | React/Next performance: waterfalls, bundle, re-renders |
| `composition-patterns` *(Vercel)* | React component architecture, compound components |
| `react-native-skills` *(Vercel)* | React Native / Expo mobile UI performance |

</details>

<details open>
<summary><b>Verify &amp; Review</b></summary>

| Skill | What it does |
|---|---|
| `test-driven-development` | Failing test first, then make it pass |
| `browser-testing-with-devtools` | Runtime verification via Chrome DevTools |
| `debugging-and-error-recovery` | Reproduce → localize → fix → guard |
| `anti-hallucination` | Verify facts/APIs against sources; research best practice before deciding |
| `code-review-and-quality` | Five-axis review before merge |
| `code-simplification` | Reduce complexity, preserve behavior |
| `security-and-hardening` | Input validation, least privilege, OWASP |
| `performance-optimization` | Measure first, optimize what matters |
| `web-design-guidelines` *(Vercel)* | Audit UI against 100+ interface rules |
| `accesslint-scan` / `accesslint-audit` / `accesslint-diff` *(AccessLint)* | Live-DOM WCAG auditing via Chrome |

</details>

<details open>
<summary><b>Ship</b></summary>

| Skill | What it does |
|---|---|
| `autonomous-git-workflow` | Commit continuously; parallelize with worktrees (no-overlap + clean-merge guidance) |
| `git-workflow-and-versioning` | Atomic commits, clean history |
| `ship-fast` | Small batches, low WIP, deploy often behind flags |
| `ci-cd-and-automation` | Automated quality gates on every change |
| `deprecation-and-migration` | Retire old systems and migrate users safely |
| `documentation-and-adrs` | Capture the *why*, not just the *what* |
| `observability-and-instrumentation` | Structured logs, RED metrics, traces |
| `shipping-and-launch` | Pre-launch checklist, monitoring, rollback |

</details>

<details>
<summary><b>Cross-cutting / always-on</b></summary>

| Skill | What it does |
|---|---|
| `using-agent-skills` | The meta-skill: discovery flowchart + operating behaviors (injected each session) |
| `memory-discipline` | What to persist to native memory (and what not) |

</details>

<details open>
<summary><b>Organise</b></summary>

| Skill | What it does |
|---|---|
| `agent-org` | One prompt → a supervised agent organisation: lane supervisors, workers, sub-agents, vault, memory, handoffs, recovery. See [below](#agent-organisation-agent-org). |

</details>

> Skills tagged with a source in *(parentheses)* are bundled third-party skills — see [Acknowledgements](#acknowledgements--credits).

**Also included:**

- **`agents/`** — 4 reusable personas: `code-reviewer`, `security-auditor`, `test-engineer`, `web-performance-auditor`.
- **`commands/`** — 9 slash commands: `/setup`, `/build`, `/plan`, `/spec`, `/test`, `/review`, `/ship`, `/code-simplify`, `/webperf`.
- **`rules/no-bloat.md`** — always-on policy: search before write, leave no dead code.
- **`references/`** — checklists for testing, performance, security, accessibility, observability, orchestration, plus a `.claude`-folder authoring guide.

## Agent organisation (`agent-org`)

The skills above make one Claude session work well. `agent-org` is for when the work outgrows one session: a standing product effort split into lanes that run for days, survive restarts and usage limits, and only stop for the owner's decisions.

```
OWNER        vision · rulings · spend/access · judges by looking
  │
OVERSEER     your Claude session: relays answers, audits evidence, keeps memory + vault + handoff current
  │
SUPERVISOR   one per lane, read-only (Claude or codex): plans, briefs workers, judges evidence, requests merges/lands
  │
WORKER       a Claude Code agent in a sandbox: one task, own clone + branch, builds, screenshots, checkpointed report
  │
SUB-AGENT    the worker's helpers: research, review, parallel exploration
```

Goals go down, evidence comes up. Around the chain the kit installs:

- **an Obsidian vault as mission control**: Vision, Plan, Roadmap, Missions, Decisions and Sessions, with generated hubs and an Index;
- **three memory layers**: auto-memory for corrections and preferences, the vault and `.claude/rules/owner-rulings.md` for project knowledge and the owner's standing rulings, and per-lane memory for each supervisor;
- **seven rules** plus the hooks, role cards (`builder`, `reviewer`, `researcher`, `bug-fixer`, …) and gates that enforce them (`scripts/gates/org-board.sh`, and a PR-gate workflow);
- **one promotion coordinator** (`promote.py`): the only process that moves a lane's integration branch or `main`. It verifies `main` + the request as one tree with your own `verify` commands, records every decision and its evidence in a hash-chained state store (`state/org.db`, mirrored to a `state/journal` branch), and derives "done" from the mission's Definition of done instead of taking an agent's word for it;
- **a sandbox around every agent** (`docs/isolation.md`): its own clone, no reads of your HOME or the org's control files, network only to Claude and the hosts you allow;
- **ops**: git sync, an hourly state snapshot, an event feed with login probes, daily spend caps per lane, and safe lane restarts that keep workers alive.

**Use it** — in Claude Code, in any repo:

```
/setup                          (pick the full org)  — or —  /agent-org set up the agent organisation for this project
```

Claude interviews you about the project, runtime (locally as you, or on a Linux VPS as a worker user), models and lanes, shows a summary for your yes, then installs and starts everything. The only steps left to you are the logins (`claude setup-token` for the agents' token file, `codex` if a codex supervisor), typed in your own terminal. Day-to-day commands are in [`skills/agent-org/README.md`](skills/agent-org/README.md), and the full design (every guard and the failure it exists for) is in [`skills/agent-org/docs/HIERARCHY.md`](skills/agent-org/docs/HIERARCHY.md).

It reuses this config rather than duplicating it: the `pre-edit-scan` and `memory-discipline` skills its rules depend on are the ones in `skills/`, and `references/orchestration-patterns.md` lists it as Pattern 6 (supervised lanes). It is also the most expensive pattern here, a supervisor consult per cycle plus up to N workers per lane, so use it for ongoing efforts, not single features.

## The hooks

All wired in `settings.json` and written to **fail safe** (no dependency → silent no-op; they never block your prompt). The context hooks use Claude Code's documented output: `session-start.sh` returns `hookSpecificOutput.additionalContext`, and `skill-router.sh` prints plain text. Both stay silent in agent-org lane processes (`AGENT_ORG_HEADLESS=1`), which are headless and follow their own rules.

| Hook | Event(s) | What it does |
|---|---|---|
| `session-start.sh` | `SessionStart` | Injects the discovery flowchart + standing operating procedure |
| `skill-router.sh` | `UserPromptSubmit` | Matches the prompt to skills and injects a routing hint (silent on weak/no match; skips slash commands) |
| `sdd-cache-pre.sh` / `sdd-cache-post.sh` | `PreToolUse` / `PostToolUse` (WebFetch) | HTTP-validator cache for `WebFetch` — serves unchanged pages from cache on a 304 |
| `simplify-ignore.sh` | `PreToolUse` (Read) / `PostToolUse` (Edit\|Write) / `Stop` | Hides `simplify-ignore`-marked blocks from the model during edits, restores them after |
| `vault-gate.sh` | `PreToolUse` (Edit\|Write\|MultiEdit\|NotebookEdit) | In a git repo without an agent-org vault, refuses the first edit of a session once with "run `/setup` here"; silent outside git, with a vault, in headless org processes, and with `.claude/no-vault` or `ORG_VAULT=off` |

## Configuration & customization

- **Permissions** — `settings.json` ships a conservative allowlist (read-only inspection + local git ops like `add`/`commit`/`worktree`); `push`/`merge`/`reset` stay in `ask`. Trim to taste.
- **Tune the router** — all keyword patterns live in one labeled block in `hooks/skill-router.sh`. Add/adjust a line per skill; it's plain `grep -E`.
- **Add a skill** — drop a `skills/<name>/SKILL.md` with `name` + `description` frontmatter. It's discoverable immediately; add a router line if you want an explicit nudge.
- **Disable a hook** — remove its entry from `settings.json` (the script can stay).
- **MCP** — `.mcp.json` configures the AccessLint server (launched on demand via `npx`). Remove the block if you don't want it.

## Security & trust

Agent Skills can execute code (scripts, and `!`-prefixed shell blocks run on load). Treat any skill folder like third-party code:

- **Review before you trust.** Everything here is plain markdown and shell — readable end to end.
- The bundled third-party skills were scanned for obvious exfiltration / shell-escape / credential-read patterns and ran clean at bundling time, but you should verify for your own threat model.
- `ui-ux-pro-max` ships a local Python CLI (queries bundled CSVs — no network); the `accesslint-*` skills drive a local Chrome via an MCP server. Review both if that matters to you.
- The hooks only ever read tool inputs and write to local cache and state dirs; none phone home.
- `agent-org` runs agents with permissions skipped, so its safety rests on what the machine and the coordinator enforce, not on what an agent chooses to do:
  - **Enforced by the sandbox** (`docs/isolation.md`): every worker and a Claude supervisor run inside the sandbox runtime (Seatbelt on macOS, bubblewrap on Linux), in their own clone, with no reads of your HOME, the org's control files or the main repo, network only to Claude and `isolation.allowed_domains`, and a scrubbed environment. Limits: an agent can read its own auth token; a broad allowed domain can be abused (keep it narrow); workers and the loop share one OS user, so a sandbox escape reaches that user; the runtime is a beta research preview.
  - **Enforced by the coordinator**: only `promote.py` moves integration or `main`, and only after main's own gates and your `verify` commands pass on the exact merged tree; a lane can never land a change to a protected path (plan, missions, rules, contracts, gates, hooks, workflows), whatever its commit messages claim; "done" is derived from the Definition of done. Every decision is a record in a hash-chained store.
  - **Advisory only**: the PreToolUse contract hook, the role cards and the prompts. Worker reports reach the supervisor fenced as untrusted text, but whether a model follows injected instructions is not something the kit can prove; that is why nothing an agent says moves a ref.
  - **Not yet proven**: remote mode has not run on a real host yet (`smoke-vps.sh` exists on its own branch), and the Linux sandbox is exercised by CI on GitHub's Ubuntu runners, not yet on a real VPS. Evidence log files live on the host; only their hashes and records are in the `state/journal` branch.
  - It pushes lane branches, the `state/journal` branch, and `main` only if you set `sync.push_main`. The hourly lane-state snapshot is pushed to `origin` too (`org.json` reduced to an allowlist of known-safe keys). The only secret it holds is the agents' token file you write (`isolation.auth_token_file`, mode 600).

## CI

`.github/workflows/ci.yml` runs on pushes to `main` and on every PR (one run per change; a newer commit cancels the run it supersedes). A lint job (Ubuntu) runs shellcheck over the hooks and the agent-org scripts, checks that every JSON config parses, that every `skills/*/SKILL.md` has YAML frontmatter with `name` and `description`, that no Python bytecode is tracked, and that the README's skill count matches `skills/`. A test job on Ubuntu and macOS runs every `*.test.mjs` under `node --test`, the loop-guard cases, and the agent-org suites: the lane loop, the host scripts, the init-repo e2e with `org-board.sh`, the headless audit, the `/setup` permutation matrix, and a local org run end to end (setup, two lanes, refused landings, a restart adopting a running agent, the hourly snapshot, STOP). Then the adversarial suites: forged authority and neutered gates, the promotion coordinator under concurrency, crashes and lying workers, and a hostile worker and supervisor inside the real sandbox (the job installs it: bubblewrap with user namespaces on Ubuntu, Seatbelt on macOS; a missing sandbox fails the run). Control steps prove the tests test something: the authority and promotion suites must go red against the pre-P0 kit, the isolation suite must go red with the sandbox off, and the `/setup` matrix's gate rows must go red with the vault-gate hook removed. All of it uses fakes; none needs a login.

## Acknowledgements & credits

This project stands on excellent open-source work. **If you fork or redistribute, keep these credits and the corresponding licenses** — they are required by the upstream licenses.

| Component | Author / Source | License |
|---|---|---|
| Core skill library, agents, commands, base hooks, references | **Addy Osmani — [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)** | MIT |
| `frontend-design` | **Anthropic — [`anthropics/skills`](https://github.com/anthropics/skills)** | Apache-2.0 |
| `web-design-guidelines`, `react-best-practices`, `composition-patterns`, `react-native-skills` | **Vercel — [`vercel-labs/agent-skills`](https://github.com/vercel-labs/agent-skills)** | MIT |
| `ui-ux-pro-max` | **[`nextlevelbuilder/ui-ux-pro-max-skill`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** | MIT |
| `accesslint-scan` / `accesslint-audit` / `accesslint-diff` + MCP server | **[`accesslint/claude-marketplace`](https://github.com/accesslint/claude-marketplace)** | MIT |
| `controlled-ux-designer`, `innovative-ux-designer` | **[`bencium/bencium-claude-code-design-skill`](https://github.com/bencium/bencium-claude-code-design-skill)** | None declared — **not cleared for redistribution** |

Original to this project: the `skill-router` reflexive routing system, the SessionStart standing-procedure injection, and the skills `anti-hallucination`, `pre-edit-scan` (+ `rules/no-bloat.md`), `memory-discipline`, `ship-fast`, `autonomous-git-workflow`, the `agent-org` supervised-organisation kit, plus the wiring that ties them together.

Full attributions and license texts are in **[`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md)**. Upstream `LICENSE` files are retained where they ship (`skills/frontend-design/LICENSE.txt` — Apache-2.0; `skills/ui-ux-pro-max/LICENSE` — MIT).

> [!WARNING]
> The two bencium skills (`controlled-ux-designer`, `innovative-ux-designer`) declare **no upstream license** (all rights reserved by default) and are included here without one. Copyright remains with bencium — obtain the author's permission before reusing or redistributing them. See [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).

## License

This project's **original contributions** are MIT-licensed — see [`LICENSE`](LICENSE). Bundled third-party skills remain under **their own licenses**; see [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md). Your project license does not override theirs.

## Contributing

Issues and PRs welcome. When adding a skill, follow the existing anatomy — `name` + `description` frontmatter, then Overview / When to Use / Process / Common Rationalizations / Red Flags / Verification — and reference other skills rather than duplicating them (the `pre-edit-scan` and `no-bloat` disciplines apply to this repo too).

<div align="center">
<sub>Built for <a href="https://code.claude.com">Claude Code</a> · MIT (original work) · see <a href="THIRD-PARTY-LICENSES.md">THIRD-PARTY-LICENSES</a> for bundled components</sub>
</div>
