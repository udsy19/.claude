---
description: Set up this config, a project's vault, or a full agent organisation — one tiered interview, answers remembered
argument-hint: "[base|vault|org]"
disable-model-invocation: true
---

Run `/setup` as an interview, then install with the engine. You ask; `setup.mjs` writes. Never hand-copy
what the engine installs, and never install before the owner's yes.

## 0. Find the engine and what is already answered

```bash
TOP=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
for K in "$TOP/.claude/skills/agent-org" "$HOME/.claude/skills/agent-org"; do [ -f "$K/scripts/setup.mjs" ] && break; done
node "$K/scripts/setup.mjs" --show --project "$TOP"
```

If neither path has `setup.mjs`, the config is not installed yet: tell the owner to run
`node <clone>/skills/agent-org/scripts/setup.mjs --scope base --install global` from a clone of the config, then
`/setup` again. `--show` prints `setup` (`~/.claude/setup.json`: `install`, `permissions`, and per project
`project`, `vision`, `main_branch`, `org_root`) and `org` (`<ORG_ROOT>/org.json`). **Skip every question
those already answer.** If anything is answered, the first question of the first call is "Keep the remembered
answers (default)" / "Change answers"; only "Change answers" re-asks them, and the run then passes `--change`.

## 1. Scope

`$ARGUMENTS` names it (`base`, `vault` or `org`); otherwise ask, with this default first:
- not in a git repo, or in `$HOME` → **base** (the config alone);
- a git repo without `vault/AGENTS.md` → **vault** (base + the agent-org vault in this project);
- a repo with a vault → **org** only if the owner wants lanes; else just re-run **vault** (a no-op).

## 2. The interview: `AskUserQuestion`, at most 4 questions per call, every question with its default first

Make the first option of every question the default, labelled "(default)". When nothing is remembered, open
the first call with "Accept all defaults (default)" / "Choose each answer"; on accept, skip to step 3.

**Tier 1 (every scope).**
1. Where the base config goes: "Globally, in ~/.claude (default)" / "In this project's .claude/". For scope
   vault or org this is still the base config's home; the vault itself always goes in the project.
2. Permissions: "The default allowlist (default)" (read-only inspection and local git; push, merge and
   reset ask) / "None: I'll edit settings.json myself" (→ `"permissions": "none"`).

**Tier 2 (vault, org).**
3. Project name and one-line vision: "Infer them; leave a TODO in vault/Index.md (default)" / "I'll give
   them" (free text via Other).
4. Main branch: the inferred one, e.g. "main (default)", confirmed or replaced.

**Tier 3 (org).** Run `skills/agent-org/SKILL.md` §1, questions 1–10 (runtime and host, worker user, models,
lanes, rulings, daily spend caps, what has not worked, the verify commands, the Definition of done), skipping what tiers 1–2 already answered. Do not keep a second copy of
those questions here: §1 is the one interview. From the answers build `vars` (the §2.1 keys) and `org` (the
`org.json` fields: `runtime`, `host` — empty when the org runs on this machine — `worker_user`, `claude_bin`,
`supervisor`, `worker_models`, `default_worker_model`, `build_queue`, `sync`, and the three caps
`max_consults_per_day`, `max_agent_starts_per_day`, `max_agent_hours_per_day` — always, even when the owner
accepted the defaults — and `verify`, which is mandatory: without it every MERGE and LAND is refused),
and `org_root`. The Definition-of-done rows go into the mission file (SKILL.md §2 step 2b).

## 3. Summary, then a yes

Show one screen: scope; where the base config goes; permissions; project, vision, main branch; for org the
lanes table, models, runtime and rules. Wait for an explicit yes. No yes, no install.

## 4. Install

Write the answers to a file in your scratchpad (never in the repo), e.g.
`{"permissions": "default", "base_install": "global", "project": "…", "vision": "…", "main_branch": "main",
"vars": {…}, "org_root": "~/agent-org", "org": {…}}` (omit what was inferred), then:

```bash
node "$K/scripts/setup.mjs" --scope <base|vault|org> --install <global|project> --project "$TOP" \
  --answers <file> [--change] [--bootstrap]
```

`--install` is where this tier goes: `global` or `project` for base; always `project` for vault and org (the
engine refuses `global` with "the vault is per project; run `/setup` inside the project"). Pass
`--bootstrap` for org once the owner said yes: it runs `bootstrap-host.sh` when the org runs on this machine.

Exit 0 is done; exit 1 installed but reported a problem (read it to the owner); exit 2 or 3 is a refusal:
show the message as it is and do what it names. Never work around a refusal.

## 5. After

- **vault / org:** commit on a branch, as `skills/agent-org/SKILL.md` §2.5 says (`Authority: owner` and an
  `EVIDENCE-GROWTH:` paragraph naming the added paths), then `bash scripts/gates/org-board.sh` must exit 0.
- **A changed main branch** touches `.claude/settings.json`, a protected path: commit it with
  `Authority: owner`.
- **org:** continue with SKILL.md §3–§6 (memory, lanes, overseer). The logins stay the owner's.
- In a repo that should not have a vault, the vault gate's reminder stops after `touch .claude/no-vault`.
