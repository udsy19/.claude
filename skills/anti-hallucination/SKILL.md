---
name: anti-hallucination
description: Grounds every factual claim and every API/library usage in a verified source before asserting it, and researches the current best approach before implementing in an unfamiliar project or domain. Use whenever you are about to state a fact, use an API/flag/config key/version, cite something, or decide "the best way to do X" — especially in an unfamiliar codebase. Prevents confident, plausible, wrong answers.
allowed-tools: WebSearch, WebFetch, Read, Grep, Glob, Bash
---

# Anti-Hallucination

## Overview

The dangerous failure mode of an LLM is not "I don't know" — it's a confident, fluent, specific answer that is wrong: an invented function signature, a config key that doesn't exist, a flag that was removed, a misremembered version, a fabricated citation, a "best practice" that is actually folklore. This skill makes **verification mandatory before assertion**. Anything checkable must be checked against an authoritative source — the code in front of you, the installed package, the official docs — not recalled from training memory. When the task is "what's the best way to do X," it researches before deciding rather than pattern-matching to the most familiar answer.

It composes with [[source-driven-development]] (verify against official docs while coding), [[doubt-driven-development]] (cross-examine non-trivial decisions), [[pre-edit-scan]] (don't invent code that already exists), and the `deep-research` skill (multi-source fact-checked investigation).

## When to Use

Engage before:

- Stating any **fact** about a library, framework, API, protocol, or tool.
- Using an **API, method signature, flag, env var, config key, or CLI option**.
- Asserting a **version number, default value, limit, or compatibility claim**.
- Giving a **citation, quote, statistic, or link**.
- Answering **"what's the best way / which library / should I use X or Y"**.
- Working in an **unfamiliar codebase or domain** (verify its conventions; research the current best practice).

Skip it for genuinely self-evident reasoning, arithmetic you can show, or facts already established and visible in the current context.

## Process

### 1. Classify each claim before you make it

| Class | Source of truth | What to do |
|---|---|---|
| **In-context** — about the repo/files in front of you | The files themselves | Read them. Quote `file:line`. |
| **Checkable external** — API shape, library behavior, version, config | Installed package code/types, official docs | Verify before asserting (steps 2–3). |
| **Judgement** — "best way to do X" | Docs + project conventions + recent authoritative sources | Research and compare (step 4). |
| **Genuinely unknown** | — | Say so. Don't fill the gap with a plausible guess. |

The error to kill: treating a *checkable external* claim as if it were *known*, and stating it from memory.

### 2. Verify against the actual artifact, not memory

- **Library/API usage** → read the installed source or type definitions, don't trust recall:
  ```bash
  # the real signature/behavior lives in the installed package
  rg -n 'def <name>|function <name>|export (const|function) <name>' node_modules/<pkg> 2>/dev/null
  cat node_modules/<pkg>/package.json | rg '"version"'
  python -c "import <pkg>; print(<pkg>.__version__, <pkg>.__file__)" 2>/dev/null
  ```
- **Versions/limits/defaults** → check the lockfile, `package.json`, `pyproject.toml`, `go.mod`, not your memory of "the current version."
- **Project conventions** → grep for how the codebase already does this thing before inventing a new way.

### 3. For external facts, go to the source

Use `WebFetch`/`WebSearch` (and prefer the [[source-driven-development]] flow) to read the **official documentation** for the exact version in use. Treat blogs and forum answers as leads, not authority. Capture the URL and the version the doc applies to.

### 4. Researching "the best way to do X" in a given project

When asked for the best approach — especially in a project you've just been handed:

1. **Inventory the project** first: read `README`, package manifests/lockfiles, config files, CI, and a few representative source files to learn the stack, version constraints, and existing conventions. The "best way" is constrained by what's already there.
2. **Enumerate candidate approaches** (2–4 real options), not just the first that comes to mind.
3. **Research each** against current authoritative sources: official docs for the versions in use, the project's own patterns, and — for anything contested or fast-moving — the `deep-research` skill for a multi-source, fact-checked comparison.
4. **Compare on the axes that matter** for this project (fit with existing stack, maintenance, performance, security, complexity), and state trade-offs.
5. **Recommend one, with reasons and sources.** If the evidence is thin or conflicting, say that and present the options instead of manufacturing false confidence.

### 5. Calibrate language to your evidence

- **Verified** → state it plainly, with the source: *"`useActionState` returns `[state, formAction, isPending]` (react.dev, React 19)."*
- **Uncertain** → mark it: *"I believe X, but I haven't verified — let me check"* and then check.
- **Unknown / unverifiable** → say *"I don't know"* or *"I can't verify this"*. This is a correct answer, not a failure. Then research or ask.
- Never let fluency outrun evidence. Confident phrasing is a claim about certainty — only use it when you have the certainty.

### 6. Cite

Every external fact carries its source inline: `file:line`, a doc URL (with version), or a package version. A claim with no checkable source is a claim you haven't verified.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'm pretty sure that's the API." | "Pretty sure" about a checkable fact = unverified. Read the source; it costs seconds. |
| "That's the standard way to do it." | Standard where, as of when, for this version? Verify it applies *here*. |
| "The user is in a hurry, I'll just answer." | A confident wrong answer costs far more time than a 10-second check. |
| "It was true last time I knew." | Versions move. Re-verify against the version actually installed. |
| "I'll add a citation later." | Without the source you can't tell if the claim is even right. Get it now. |

## Red Flags

- A specific API signature, flag, or version stated without having opened the source or docs.
- A citation, URL, or statistic produced from memory.
- "Best practice" / "everyone does X" with no source and no check of the project's own conventions.
- Recommending a library without confirming it's compatible with the versions in the lockfile.
- Fluent, confident prose about something you did not verify.
- Filling an unknown with a plausible guess instead of saying "I don't know."

## Verification

- ☐ Every checkable external claim has a source (file:line, doc URL + version, or package version)
- ☐ API/library usage was confirmed against the installed code or official docs, not memory
- ☐ For "best way" questions: project inventoried, ≥2 options researched, recommendation has stated reasons + sources
- ☐ Uncertainty is marked as uncertainty; unknowns are stated, not guessed
- ☐ No fabricated citations, versions, signatures, or flags
