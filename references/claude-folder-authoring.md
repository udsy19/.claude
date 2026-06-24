# Authoring a `.claude` Folder — Reference

Compiled from the official Claude Code docs (URLs at the bottom). Where the docs are exhaustive (e.g. the full `settings.json` key list), this file keeps the load-bearing parts and points to the source rather than reproducing every field — verify rarely-used keys against the doc before relying on them.

## 1. Directory layout & what auto-loads

A `.claude` folder works at two scopes: **project** (`<repo>/.claude/`, shared via git) and **user** (`~/.claude/`, applies to all projects). Same structure at both.

```
.claude/
├── settings.json          # config: hooks, permissions, env, model …   (auto)
├── settings.local.json    # personal overrides, gitignored               (auto)
├── .mcp.json              # MCP servers (project root, NOT inside .claude) (auto, with approval)
├── CLAUDE.md              # instructions / memory                         (auto, loaded in full)
├── rules/*.md             # path-scoped or always-on instructions         (auto*)
├── skills/<name>/SKILL.md # discoverable workflows                        (desc auto; body on invoke)
├── commands/<name>.md     # legacy slash commands (merged into skills)     (auto)
├── agents/<name>.md       # subagents                                     (auto at startup)
├── hooks/*.sh             # scripts referenced by settings.json           (NOT auto — wired in settings)
└── output-styles/*.md     # optional output formatting                    (auto)
```

| Thing | Auto-loaded? |
|---|---|
| Project-root `CLAUDE.md` | Yes, in full, every session |
| `rules/*.md` **without** a `paths:` frontmatter field | Yes, at startup (unconditional) |
| `rules/*.md` **with** `paths:` | Lazily, when Claude reads a file matching the glob |
| Skill `description` (frontmatter) | Yes, always (~100 tokens/skill) |
| Skill body (`SKILL.md` content) | Only when the skill is invoked |
| Skill supporting files (references/scripts) | Only when explicitly read/run |
| `agents/*.md` | Discovered at startup; system prompt loads when delegated to |
| `hooks/*.sh` | Never auto — only run when registered under a hook event in `settings.json` |

**Progressive disclosure is the core efficiency model**: name+description for every skill is cheap; the heavy content loads on demand. This is why 30+ skills cost little at rest.

## 2. settings.json

Lives at `.claude/settings.json` (shared) and `.claude/settings.local.json` (gitignored). Precedence, highest → lowest: **managed/enterprise → CLI args → local → project → user**. Permission rules **merge** across scopes rather than overriding.

Load-bearing keys:

```json
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(jq:*)"],
    "ask":   ["Bash(git push:*)"],
    "deny":  ["Read(./.env)", "Read(./.env.*)"]
  },
  "env": { "SOME_VAR": "value" },
  "model": "claude-opus-4-8",
  "hooks": { "...": "see §5" }
}
```

Permission rule syntax is `Tool(matcher)` — e.g. `Bash(npm run test:*)`, `Read(./secret)`, `Skill(deploy)`. For the full key list see the settings doc.

## 3. skills/ — SKILL.md

```yaml
---
name: my-skill                      # required; kebab-case; should match the directory name
description: >                      # required; FIRST sentence drives auto-activation —
  What it does (third person), then explicit "Use when…" triggers.
  Combined with when_to_use; total budget ~1,536 chars.
when_to_use: "Trigger phrases and situations."   # optional; appended to description
allowed-tools: Read, Grep, Bash(rg:*)            # optional; restrict the tool pool
argument-hint: "[issue] [branch]"                # optional; enables /my-skill as a command
model: inherit                                   # optional
---

# Title
## Overview / When to Use / Process / Common Rationalizations / Red Flags / Verification
```

Rules of thumb:
- A skill is a **directory** with `SKILL.md`, not a loose file — it can bundle scripts/templates/reference docs.
- Keep `SKILL.md` focused (≤ ~500 lines); push long reference material to sibling files and point to them so they load only when needed.
- The `description` is the single most important field — vague descriptions activate unreliably; precise ones with explicit triggers fire consistently.
- Naming: `.claude/skills/deploy/SKILL.md` → `/deploy`. Nested dirs namespace as `dir:name`.
- Dynamic context: a fenced block beginning with `!` (or inline ``!`cmd` ``) runs and its output is injected before Claude reads the skill. Useful but executes on load — keep portable.

## 4. commands/ (legacy)

`.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both create `/deploy`; commands are the older form, now merged into skills. Same markdown+frontmatter format. New work should use `skills/`; existing command files still work.

## 5. hooks

Hooks are **scripts wired into lifecycle events from `settings.json`** — the `hooks/` directory itself is not auto-discovered. Shape:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Edit",
        "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh\"" }] }
    ]
  }
}
```

- Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStart/Stop`, `Notification`, `SessionEnd`, and more.
- `matcher` filters by tool name (regex/alternation, e.g. `Edit|Write`); omit for events without tools.
- Hook receives a JSON object on **stdin** (`tool_name`, `tool_input`, `cwd`, `hook_event_name`, …).
- **Exit 0** = proceed; for `SessionStart` and `UserPromptSubmit`, stdout on exit 0 is **added to Claude's context**. **Exit 2** = block, stderr is fed back to Claude. Other = logged, proceed.
- Or emit structured JSON on stdout (`hookSpecificOutput`) for richer decisions.
- Use `${CLAUDE_PROJECT_DIR}` so paths resolve regardless of cwd.

## 6. agents/ — subagents

```yaml
---
name: code-reviewer
description: When Claude should delegate here. Drives auto-delegation.
tools: Read, Grep, Glob, Bash          # optional allowlist; inherits all if omitted
model: sonnet                          # optional
---

You are a … (system prompt body)
```

Discovered from `.claude/agents/` (project) and `~/.claude/agents/` (user). Good for focused, tool-restricted delegation.

## 7. .mcp.json

Project-scoped MCP servers, at the **project root** (next to `.claude/`), shared via git:

```json
{ "mcpServers": {
    "name": { "command": "npx", "args": ["-y", "@scope/pkg"] },
    "remote": { "type": "http", "url": "https://…/mcp", "headers": { "Authorization": "Bearer ${TOKEN}" } }
} }
```

Types: `stdio` (local process), `http`/`sse` (remote), `ws`. Env-var expansion (`${VAR}`, `${VAR:-default}`) works in `command`/`args`/`env`/`url`/`headers`. User-scope servers live in `~/.claude.json`.

## 8. CLAUDE.md / memory & rules/

- Load order (high→low): managed policy → user `~/.claude/CLAUDE.md` → ancestor → current-dir `CLAUDE.md` → `CLAUDE.local.md` (gitignored) → nested `CLAUDE.md` (lazy).
- `@path` imports inline another file (relative/absolute/`~`, up to ~4 hops). Backtick to escape.
- `.claude/rules/*.md`: a `paths:` frontmatter glob makes a rule **path-scoped** (loads when matching files are read); **no `paths:`** means it loads at startup for every session — use that for always-on policy.
- Keep `CLAUDE.md` tight (≤ ~200 lines); specific instructions ("2-space indent") beat vague ones.

## Authoring best practices (cross-cutting)

- Prefer **progressive disclosure**: short descriptions, heavy detail behind on-demand files.
- One concern per skill/agent/rule; reference others instead of duplicating.
- Restrict tools (`allowed-tools` / `tools`) to what's needed.
- Make hook commands portable with `${CLAUDE_PROJECT_DIR}` and degrade gracefully if a dependency is missing.
- Review nested `CLAUDE.md` + `rules/` for contradictions — conflicting instructions degrade adherence.

## Sources (official docs)

- Directory: https://code.claude.com/docs/en/claude-directory
- Settings: https://code.claude.com/docs/en/settings
- Skills: https://code.claude.com/docs/en/skills
- Subagents: https://code.claude.com/docs/en/sub-agents
- Hooks: https://code.claude.com/docs/en/hooks-guide
- Memory/CLAUDE.md: https://code.claude.com/docs/en/memory
- MCP: https://code.claude.com/docs/en/mcp

> Verify against the live docs before relying on rarely-used keys — Claude Code moves fast and some fields change between versions.
