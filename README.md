# Claude Code — Production `.claude` Configuration

A complete, batteries-included **`.claude` folder** for [Claude Code](https://code.claude.com): 40 lifecycle skills, 4 agent personas, 8 slash commands, and a set of hooks that turn the skill library from a passive reference into a **reflexive thinking process** — the right skill is suggested on every prompt, and a handful of always-on disciplines (verify-don't-hallucinate, no-bloat, continuous-git, memory, ship-fast) run in the background.

Drop it into `~/.claude/` (global) or a project's `.claude/` and Claude Code picks everything up automatically.

---

## Table of contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [Install](#install)
- [Requirements](#requirements)
- [What's inside](#whats-inside)
- [The hooks](#the-hooks)
- [Configuration & customization](#configuration--customization)
- [Security & trust](#security--trust)
- [Acknowledgements & credits](#acknowledgements--credits)
- [License](#license)
- [Contributing](#contributing)

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

Claude Code reads a `.claude` folder at two scopes. Pick one:

**Global (recommended — applies to every project):**

```bash
# clone, then copy the contents into your user-level .claude
git clone https://github.com/udsy19/.claude.git claude-config
cp -R claude-config/{skills,agents,commands,hooks,rules,references} ~/.claude/
cp claude-config/settings.json ~/.claude/settings.json   # merge if you already have one
```

> If you install globally, the hook paths in `settings.json` use `${CLAUDE_PROJECT_DIR}/.claude/...`. For a pure `~/.claude` install, change those to `$HOME/.claude/...` (or `${CLAUDE_CONFIG_DIR}/...`).

**Per-project (shared with your team via git):**

```bash
cp -R claude-config/{skills,agents,commands,hooks,rules,references,settings.json} your-project/.claude/
cp claude-config/.mcp.json your-project/.mcp.json        # MCP config lives at the project ROOT
```

Then add the hook cache directories to your project's `.gitignore`:

```
.claude/sdd-cache/
.claude/.simplify-ignore-cache/
```

**Important placement notes**

- Contents go **directly** under `.claude/` (i.e. `.claude/skills/...`), not nested in a sub-folder.
- `.mcp.json` belongs at the **project root**, next to `.claude/` — not inside it.
- `.claude/rules/*.md` files without a `paths:` field auto-load every session (that's how `no-bloat.md` is always enforced).

## Requirements

Everything degrades gracefully if a dependency is missing, but for full functionality:

| Dependency | Used by |
|---|---|
| `jq` | all hooks (router, session-start, caches) — they silently no-op without it |
| `curl`, `shasum`/`sha256sum` | the `sdd-cache` web-fetch cache hooks |
| `python3` | the `ui-ux-pro-max` skill's design-system CLI |
| Google Chrome + the AccessLint MCP server | the `accesslint-*` live-DOM accessibility skills |
| Claude Code **v2.1.59+** | native auto-memory referenced by `memory-discipline` |

## What's inside

40 skills organized by development phase, plus the meta-skill that wires discovery.

### Define
| Skill | What it does |
|---|---|
| `interview-me` | Surface what you actually want before any plan or code |
| `idea-refine` | Diverge then converge on an approach |
| `spec-driven-development` | Requirements + acceptance criteria before code |

### Plan
| Skill | What it does |
|---|---|
| `planning-and-task-breakdown` | Decompose into small, verifiable tasks |

### Build
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

### Verify
| Skill | What it does |
|---|---|
| `test-driven-development` | Failing test first, then make it pass |
| `browser-testing-with-devtools` | Runtime verification via Chrome DevTools |
| `debugging-and-error-recovery` | Reproduce → localize → fix → guard |
| `anti-hallucination` | Verify facts/APIs against sources; research best practice before deciding |

### Review
| Skill | What it does |
|---|---|
| `code-review-and-quality` | Five-axis review before merge |
| `code-simplification` | Reduce complexity, preserve behavior |
| `security-and-hardening` | Input validation, least privilege, OWASP |
| `performance-optimization` | Measure first, optimize what matters |
| `web-design-guidelines` *(Vercel)* | Audit UI against 100+ interface rules |
| `accesslint-scan` / `accesslint-audit` / `accesslint-diff` *(AccessLint)* | Live-DOM WCAG auditing via Chrome |

### Ship
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

### Cross-cutting / always-on
| Skill | What it does |
|---|---|
| `using-agent-skills` | The meta-skill: discovery flowchart + operating behaviors (injected each session) |
| `memory-discipline` | What to persist to native memory (and what not) |

> Skills tagged with a source in *(parentheses)* are bundled third-party skills — see [Acknowledgements](#acknowledgements--credits).

### Also included

- **`agents/`** — 4 reusable personas: `code-reviewer`, `security-auditor`, `test-engineer`, `web-performance-auditor`.
- **`commands/`** — 8 slash commands: `/build`, `/plan`, `/spec`, `/test`, `/review`, `/ship`, `/code-simplify`, `/webperf`.
- **`rules/no-bloat.md`** — always-on policy: search before write, leave no dead code.
- **`references/`** — checklists for testing, performance, security, accessibility, observability, orchestration, plus a `.claude`-folder authoring guide.

## The hooks

All wired in `settings.json` and written to fail safe (no dependency → silent no-op; they never block your prompt).

| Hook | Event(s) | What it does |
|---|---|---|
| `session-start.sh` | `SessionStart` | Injects the discovery flowchart + standing operating procedure |
| `skill-router.sh` | `UserPromptSubmit` | Matches the prompt to skills and injects a routing hint (silent on weak/no match; skips slash commands) |
| `sdd-cache-pre.sh` / `sdd-cache-post.sh` | `PreToolUse` / `PostToolUse` (WebFetch) | HTTP-validator cache for `WebFetch` — serves unchanged pages from cache on a 304 |
| `simplify-ignore.sh` | `PreToolUse` (Read) / `PostToolUse` (Edit\|Write) / `Stop` | Hides `simplify-ignore`-marked blocks from the model during edits, restores them after |

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
- The hooks only ever read tool inputs and write to local cache dirs; none phone home.

## Acknowledgements & credits

This project stands on excellent open-source work. **If you fork or redistribute, keep these credits and the corresponding licenses** — they are required by the upstream licenses.

| Component | Author / Source | License |
|---|---|---|
| Core skill library, agents, commands, base hooks, references | **Addy Osmani — [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)** | MIT |
| `frontend-design` | **Anthropic — [`anthropics/skills`](https://github.com/anthropics/skills)** | Apache-2.0 |
| `web-design-guidelines`, `react-best-practices`, `composition-patterns`, `react-native-skills` | **Vercel — [`vercel-labs/agent-skills`](https://github.com/vercel-labs/agent-skills)** | MIT |
| `ui-ux-pro-max` | **[`nextlevelbuilder/ui-ux-pro-max-skill`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** | MIT |
| `accesslint-scan` / `accesslint-audit` / `accesslint-diff` + MCP server | **[`accesslint/claude-marketplace`](https://github.com/accesslint/claude-marketplace)** | MIT |
| `controlled-ux-designer`, `innovative-ux-designer` | **[`bencium/bencium-claude-code-design-skill`](https://github.com/bencium/bencium-claude-code-design-skill)** | ⚠️ None declared — **not cleared for redistribution** |

Original to this project: the `skill-router` reflexive routing system, the SessionStart standing-procedure injection, and the skills `anti-hallucination`, `pre-edit-scan` (+ `rules/no-bloat.md`), `memory-discipline`, `ship-fast`, `autonomous-git-workflow`, plus the wiring that ties them together.

Full attributions and license texts are in **[`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md)**. Upstream `LICENSE` files are retained where they ship (`skills/frontend-design/LICENSE.txt` — Apache-2.0; `skills/ui-ux-pro-max/LICENSE` — MIT).

> ⚠️ **The two bencium skills (`controlled-ux-designer`, `innovative-ux-designer`) declare no upstream license** (all rights reserved by default) and are included here without one. Copyright remains with bencium — obtain the author's permission before reusing or redistributing them. See [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).

## License

This project's **original contributions** are MIT-licensed — see [`LICENSE`](LICENSE) (set your name in the copyright line). Bundled third-party skills remain under **their own licenses**; see [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md). Your project license does not override theirs.

## Contributing

Issues and PRs welcome. When adding a skill, follow the existing anatomy — `name` + `description` frontmatter, then Overview / When to Use / Process / Common Rationalizations / Red Flags / Verification — and reference other skills rather than duplicating them (the `pre-edit-scan` and `no-bloat` disciplines apply to this repo too).
