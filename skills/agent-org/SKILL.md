---
name: agent-org
description: Bootstrap a full supervised agent organisation for any project from one prompt — supervisor per lane, Claude worker agents, worker sub-agents, an Obsidian vault as mission control, a 3-layer memory system, session handoffs, owner rules, git sync, hourly state backup, an event feed with auth probes, and recovery. Use when the user says "set up the agent org / lanes / supervisor + sub-agents", "/agent-org", or wants this architecture reproduced on a new project or host.
---

# agent-org: one prompt → a supervised agent organisation

You are setting up, for the user (the **owner**), the organisation described in `docs/HIERARCHY.md`:
- **owner**: sets the vision and rules on decisions;
- **overseer**: you, this Claude session;
- **lane supervisors**: one per lane;
- **worker agents**;
- **sub-agents**.

The vault, memory, session-handoff, rules and recovery layers come with it. Every file you generate comes
from `templates/` and `scripts/` in this skill's folder (`KIT` below). Fill the placeholders; never invent
a different structure.

## 0. Before anything: read
Read `docs/HIERARCHY.md` (the why, the failure modes, the file list) and `templates/memory/memory-guide.md`.
The repo layer's own contracts are in `templates/repo/vault/` (`CLAUDE.md`, `AGENTS.md`, `SUPERVISOR.md`,
`Architecture.md` with the authority matrix, `Design/lanes-and-supervisors.md` with the communication
channels, the research flow and the supervisor's memory).

## 1. Interview the owner (AskUserQuestion; at most 4 questions per call; skip what they already said)
Ask for, and record verbatim:
1. **Project:** name, the repo path (existing or new), and the main branch. Does pushing main deploy
   anywhere? If so, a landing is a deploy.
2. **Vision:** a one-liner; who uses it; the acceptance bar ("works as well as X", "Y-level output").
3. **Runtime:** **local** (tmux on this machine) or **remote** (a VPS over SSH: host, and whether the owner
   has an SSH key there). Should agents run as a separate worker user? On Linux as root this is required,
   because `claude` refuses to skip permissions as root.
4. **Models.** Always ASK; never assume.
   - **Supervisor:** codex (OpenAI, e.g. `gpt-6-astra`, read-only with web search) or Claude (e.g.
     `claude-opus-5-5`, read-only tools)? Which model, and what reasoning effort?
   - **Workers:** which Claude models, as keys such as `opus` → `claude-opus-5-5` and `sonnet` → `sonnet`,
     and the default.
   - **Sub-agents:** may workers spawn them? This is on by default.
5. **Lanes:** for each one, the name, a one-paragraph GOAL, the max parallel workers, and whether it may
   land on main. Which lane is the priority (it gets build priority)? Suggest a starting set from the goal,
   e.g. core product, quality, deliverables, UX, critique.
6. **Owner rulings:** anything beyond the four defaults (goals-not-tests, vault-first, judged by real-product
   evidence, settings-not-questions). Which paths are owner-only? Any spend caps, accounts or services that
   are off-limits?
7. **What has NOT worked so far.** Ask this; it is what stops agents repeating history.

Then show a one-screen summary (lanes table, models, runtime, rules) and get a yes before writing anything.

## 2. Generate the repo layer (in the repo; commit on a branch, not main, unless the owner says so)
`KIT/templates/repo/` is the WHOLE repo layer, mirrored path for path: the Obsidian vault (contracts,
Plan, Roadmap, Decisions, Missions, folder hubs, Bases, templates, `.obsidian/` config), the rules,
the hooks and `settings.json`, the role cards and skills, and every enforcement script and gate. One
command installs it. Never hand-copy pieces of it.

1. **Install.** Write the interview answers to a vars file and run the installer:
   ```bash
   node KIT/scripts/init-repo.mjs --repo <repo> --vars /tmp/agent-org-vars.json --install-global-skills
   ```
   Keys (UPPER_SNAKE): `PROJECT`, `DATE`, `MAIN_BRANCH`, `MISSION` (a slug — the mission file name and
   `ORG_MISSION`), `MISSION_TITLE`, `MISSION_GOAL`, `VISION_ONE_LINER`, `USERS`, `ACCEPTANCE_BAR`,
   `OWNER_WORDS` (verbatim), `NOT_WORKED`, `NEXT_MOVE`, `FIRST_TRACK`, `FIRST_TRACK_ITEM`,
   `SOURCE_AREAS` (one `` `dir/` | what lives here | file to open first `` row per area, for
   `vault/Map-code.md`), and for `vault/Design/lanes-and-supervisors.md`: `SUPERVISOR_DESC`,
   `WORKER_DESC`, `RUNTIME`, `HOST`, `ORG_ROOT`, `STATE_BRANCH`, `LANE_TABLE` (the lanes table rows).
   The installer MERGES — an existing file is kept, `.gitignore` and `.claude/settings.json` get only
   what is missing — strips the `.tmpl` suffix the kit uses for the four protected entries,
   and regenerates the hubs, Map and Index. It REFUSES before writing anything (exit 2, naming the keys)
   if any key is missing, so a partial install cannot happen; a re-run never overwrites a file.
2. **Extra owner rulings** go in `<repo>/.claude/rules/<ruling>.md`, one rule one file, no overlap with
   the six the kit installs (gate-independence, no-bloat, goals-not-tests, vault-first,
   evidence-and-honesty, protected-paths). If the owner names more protected paths, add them to
   `scripts/lib/protected-paths.mjs` (the ONE declaration) and to the four documents
   `scripts/gates/protected-paths.mjs` holds to it.
3. **CLAUDE.md:** append `KIT/templates/claude/CLAUDE.project-snippet.md` (filled) to `<repo>/CLAUDE.md`,
   or create it.
4. **First session note:** `vault/Sessions/<date>-agent-org-setup.md` from `vault/Templates/session.md`,
   recording the interview verbatim; then `node scripts/vault-hubs.mjs` and
   `python3 scripts/gen-subject-index.py`. The mission's `accepted-by: owner` records the owner's "yes" to
   the summary in step 1 — never fill it without that yes (gate-independence law 9).
5. **Run the board and commit.** `bash scripts/gates/org-board.sh` must exit 0 (skips are named, e.g. the
   code map without a graph, or plan-ownership/sprawl on an empty landing range). Commit on a branch with
   `Authority: owner` in the message (the commit touches protected paths) and an `EVIDENCE-GROWTH:`
   paragraph naming what the set-up added and why; then re-run `node scripts/gates/plan-ownership.mjs`
   and `node scripts/gates/sprawl.mjs` against that commit.

## 3. Generate the memory layer (auto-memory dir for this project)
Copy and fill `KIT/templates/memory/{owner-rulings.md, org-architecture.md}`, and add their lines to
`MEMORY.md`. Create the index if it is missing; merge if it exists, never duplicating.

## 4. Generate the org layer (on the runtime host; for remote, run these over SSH)
1. `ORG_ROOT` (default `/srv/org` remote, `~/agent-org` local): write `org.json` from
   `KIT/scripts/org.example.json` with the interview answers.
2. Copy `KIT/scripts/*` to the host, then run `bootstrap-host.sh <ORG_ROOT>`. It checks the tools, creates
   the worker user, installs the build queue, starts git-sync, and adds the hourly state snapshot cron.
   **Logins are the owner's** (interactive, in their own terminal, never pasted into chat):
   - `sudo -u <worker> -i claude` → `/login` (or `claude setup-token` for a long-lived token);
   - `codex login --device-auth`, if the supervisor is codex.

   Re-run the bootstrap's login check until both pass.
3. **Per lane:** `lanes.sh <ORG_ROOT> new <name> "<goal>" <par> <may_land>`. Then fill each lane's:
   - `context.md`: from the vision, rulings, failures, state and repo facts;
   - the GOAL section of `supervisor-brief.md`: the owner's paragraph, verbatim;
   - `rulings.md`: seeded with the standing rulings (the law in force, shown whole every consult);
     `owner-answers.md` stays the raw, dated log of the owner's answers.
4. `lanes.sh <ORG_ROOT> start`.

## 5. Become the overseer
1. Arm a Monitor on `ssh <host> 'bash <ORG_ROOT>/lane-events.sh <ORG_ROOT>'` (or a local `bash …`) with
   `timeout_ms` 1800000, and re-arm it on expiry.
2. Start the tracking loop with `/loop` and a filled copy of `KIT/templates/handoff/overseer-loop-prompt.md`
   (save it as `<repo>/.claude/loop-prompts/org-tracker.md`). Tell the owner they must run
   `/loop Follow .claude/loop-prompts/org-tracker.md`; you can't start `/loop` yourself.
3. Follow `KIT/templates/handoff/session-protocol.md` for every session from now on.

## 6. Verify, then report
Verify all of these before telling the owner it works:
- every lane logged `=== CONSULT 1` and dispatched at least one worker;
- a worker has written a checkpoint report that opens with a Vault check;
- git-sync pushed a lane branch;
- the state snapshot ran once (run `state-snapshot.sh` manually);
- the auth probe is green;
- `bash scripts/gates/org-board.sh` exits 0 in the repo (its skips named), and the set-up commit passes
  `plan-ownership.mjs` and `sprawl.mjs`.

Then tell the owner what is running, where it lives, what only they can do (logins, spend), and how to stop
it (`lanes.sh <ORG_ROOT> stop <lane>`).

## Never
- Never hand-edit `vault/Map.md`, the folder hubs or `vault/Index.md` (outside its promoted-lessons
  block): they are generated. Regenerate them.
- Never commit to a protected path without `Authority: owner|supervisor` or `Proposal: #<n>`.
- Never put secrets in chat, git or the vault. Owners type tokens into their own terminals.
- Never push to main or deploy unless the owner said a landing may deploy.
- Never kill a lane's tmux session while workers run. Use `lanes.sh restart`, which adopts them.
- Never touch processes or services on a shared host that aren't this org's.
- Never let ASK_OWNER questions sit unseen. If the overseer stops tracking, say so to the owner.
