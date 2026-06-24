---
name: memory-discipline
description: Governs what to persist to Claude Code's native memory and where it belongs, so memory accumulates durable, reusable knowledge instead of noise. Use when you learn something worth carrying across sessions (a build command, a non-obvious convention, a user preference, a debugging insight, a decision with rationale), when the user says "remember this" or "for next time", or when deciding whether a fact belongs in auto-memory, CLAUDE.md, a rule, or nowhere.
allowed-tools: Read, Write, Edit, Grep, Glob
---

# Memory Discipline

## Overview

Claude Code carries knowledge across sessions through **native** mechanisms — no plugin required. Auto-memory is on by default (v2.1.59+), and only the **first 200 lines / 25KB of `MEMORY.md`** load at the start of each session. So the entire game is selectivity and concision: memory is valuable only as long as it stays high-signal. This skill is the discipline for deciding *what* to persist and *where* — not a storage tool.

Composes with [[anti-hallucination]] (recalled memory can be stale — re-verify before acting), [[pre-edit-scan]] (memory is not a substitute for searching the code), and [[context-engineering]] (memory is one context source among several).

## The homes for knowledge — pick the right one

| Home | Who writes it | What belongs there | When it loads |
|---|---|---|---|
| **CLAUDE.md** | You / human ("add to CLAUDE.md") | Durable instructions: build/test commands, standards, architecture, "always do X" | In full, every session |
| **Auto-memory** (`~/.claude/projects/<repo>/memory/MEMORY.md` + topic files) | Claude, automatically | Learnings Claude *discovers*: gotchas, debugging insights, preferences, decisions | First 200 lines/25KB of `MEMORY.md` each session; topic files on demand |
| **`.claude/rules/*.md`** | You | Always-on or path-scoped policy | At startup, or when a matching file is read |
| **Skills** | Author | Repeatable multi-step workflows | On invoke / when relevant |
| **Nowhere** | — | Anything re-derivable from code, transient state, one-off trivia | — |

Rule of thumb: a *standing instruction a human wrote* → CLAUDE.md; a *learning you discovered* → auto-memory; a *path-scoped policy* → rules/; a *workflow* → a skill.

## When to persist (all three must hold)

1. It will be useful in a **future** session — not just this task.
2. It is **not trivially re-derivable** from the code/files in front of you.
3. It is **stable** — it won't be stale next week.

Concrete triggers: the user says "remember…" / "for next time"; you hit the same gotcha twice; you discover a non-obvious build/test/run command; you learn a project convention or user preference that isn't written down; you make a decision whose rationale is worth keeping.

## What NOT to persist

- Facts visible or derivable from the repo (file layout, function signatures) — read them when needed instead.
- Transient state (current branch, today's task, in-progress TODOs).
- **Secrets, tokens, or PII — never.**
- One-off trivia, or anything that will be wrong soon.
- Duplicates of what's already in CLAUDE.md or rules.

## How to write it well

- Keep `MEMORY.md` a **concise index** — one line per fact. Push detail into topic files (`debugging.md`, `conventions.md`) that load on demand. Detail in `MEMORY.md` past the 200-line cap simply never loads.
- One fact per entry; make it specific and verifiable: `build: pnpm, not npm; integration tests need local Redis on :6379`.
- For decisions and preferences, record the **why** in one clause.
- **Prune.** Delete entries that turn out wrong or stale. Memory reflects what was true when written.
- Route it: human's standing instruction → CLAUDE.md; your discovered learning → auto-memory; path-scoped policy → rules/.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll remember everything, just in case." | Only ~200 lines load. Noise crowds out signal — persist selectively. |
| "It's in memory, so it's true." | Memory reflects when it was written. Re-verify named files/flags/versions before relying on them ([[anti-hallucination]]). |
| "I'll put this build command in auto-memory." | If it's a standing project fact, CLAUDE.md is its durable home; auto-memory is for things you *discover*. |
| "Memory means I don't need to read the code." | Memory points you at things; it doesn't replace reading the current source ([[pre-edit-scan]]). |

## Red Flags

- `MEMORY.md` bloating past ~200 useful lines with detail that belongs in topic files.
- Secrets or transient state written to memory.
- The same insight re-learned across sessions because it was never persisted.
- Acting on a recalled fact without re-checking it against the current code.
- A learning saved to memory when it was really a standing instruction (belongs in CLAUDE.md).

## Verification

- ☐ The fact is future-useful, stable, and not re-derivable from code
- ☐ It went to the right home (auto-memory vs CLAUDE.md vs rules vs nowhere)
- ☐ `MEMORY.md` stays a concise index; detail lives in topic files
- ☐ No secrets, PII, or transient state persisted
- ☐ Recalled facts are re-verified before being acted on
