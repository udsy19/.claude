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

**`/agent-org` is `/setup` with scope=org** (`commands/setup.md`). `/setup` asks the base and vault
questions, remembers every answer (`~/.claude/setup.json`, `<ORG_ROOT>/org.json`), and installs with
`KIT/scripts/setup.mjs`; its tier 3 is §1 below. Start there: `node KIT/scripts/setup.mjs --show` lists what is
already answered, and you never ask those again.

**Already set up?** If the repo has `vault/AGENTS.md` and the host has an `<ORG_ROOT>/org.json`, this org
exists: don't re-run setup. Follow `KIT/templates/handoff/session-protocol.md`, and use `lanes.sh` for lane
changes.

**Requirements:** git, Node ≥ 16, Python ≥ 3.8, bash (3.2 is fine). On the runtime host also tmux, rsync,
`claude`, and `codex` for a codex supervisor; flock only if `build_queue.wrap` installs the build queue.
`bootstrap-host.sh` checks these.

## 0. Before anything: read
Read `docs/HIERARCHY.md` (the why, the failure modes, the file list) and `templates/memory/memory-guide.md`.
The repo layer's own contracts are in `templates/repo/vault/` (`CLAUDE.md`, `AGENTS.md`, `SUPERVISOR.md`,
`Architecture.md` with the authority matrix, `Design/lanes-and-supervisors.md` with the communication
channels, the research flow and the supervisor's memory).

## 1. Interview the owner (AskUserQuestion; at most 4 questions per call; skip what they already said)
This is `/setup`'s tier 3, the only copy of these questions. Skip what `setup.mjs --show` already holds
(the project, its vision and main branch may come from tiers 1–2). Ask for, and record verbatim:
1. **Project:** name, the repo path (existing or new), and the main branch. Does pushing main deploy
   anywhere? If so, a landing is a deploy.
2. **Vision:** a one-liner; who uses it; the acceptance bar ("works as well as X", "Y-level output").
3. **Runtime:** **local** (macOS or Linux, tmux on this machine, run as the owner — not root, because
   `claude` refuses to skip permissions as root) or **remote** (a Linux VPS over SSH: the host, whether the
   owner has an SSH key there, and the name of the worker user that will run the whole org).
4. **Models.** Always ASK; never assume.
   - **Supervisor:** codex (OpenAI, read-only with web search) or Claude (read-only tools)? Which model,
     and what reasoning effort? (Model names change; examples as of 2026-10: `gpt-6-astra`,
     `claude-opus-5-5`.)
   - **Workers:** which Claude models, as keys such as `opus` → `claude-opus-5-5` and `sonnet` → `sonnet`,
     and the default.
   - **Sub-agents:** may workers spawn them? This is on by default.
5. **Lanes:** for each one, the name, a one-paragraph GOAL, the max parallel workers, and whether it may
   land on main. Which lane is the priority (it gets build priority)? Suggest a starting set from the goal,
   e.g. core product, quality, deliverables, UX, critique.
6. **Owner rulings:** anything beyond the four defaults (goals-not-tests, vault-first, judged by real-product
   evidence, settings-not-questions). Which paths are owner-only? Any accounts or services that are
   off-limits? Daily spend caps per lane (defaults: 100 consults, 40 agent starts, 48 agent-hours)?
7. **What has NOT worked so far.** Ask this; it is what stops agents repeating history.

Then show a one-screen summary (lanes table, models, runtime, rules) and get a yes before writing anything.
The installer records that yes: it writes the mission with `accepted-by: owner` (gate-independence law 9),
so never run it before the owner has said yes.

## 2. Generate the repo layer (in the repo; commit on a branch, not main, unless the owner says so)
`KIT/templates/repo/` is the WHOLE repo layer, mirrored path for path: the Obsidian vault (contracts,
Plan, Roadmap, Decisions, Missions, folder hubs, Bases, templates, `.obsidian/` config), the rules,
the hooks and `settings.json`, the role cards and skills, and every enforcement script and gate. One
command installs it. Never hand-copy pieces of it.

0. **A brand-new repo** needs a root commit on main before anything else (the landing gates measure a
   branch against main): `git commit --allow-empty -m "root"` if `git rev-parse <main>` fails.
1. **Install.** `node KIT/scripts/setup.mjs --scope org --install project --answers <file>` does this step
   (it runs `init-repo.mjs` with the answers' `vars`). By hand, write the interview answers to a vars file
   and run the installer:
   ```bash
   node KIT/scripts/init-repo.mjs --repo <repo> --vars /tmp/agent-org-vars.json --install-global-skills
   ```
   Keys (UPPER_SNAKE): `PROJECT`, `DATE`, `MAIN_BRANCH`, `MISSION` (a slug — the mission file name and
   `ORG_MISSION`), `MISSION_TITLE`, `MISSION_GOAL`, `VISION_ONE_LINER`, `USERS`, `ACCEPTANCE_BAR`,
   `OWNER_WORDS` (verbatim), `NOT_WORKED`, `NEXT_MOVE`, `FIRST_TRACK`, `FIRST_TRACK_ITEM`,
   `EXTRA_RULINGS` (the owner's rulings beyond the four defaults, as `- ` bullets, or empty — they go into
   `.claude/rules/owner-rulings.md`),
   `SOURCE_AREAS` (complete table rows, one per product area, newline-separated:
   `` | `dir/` | what lives here | `file to open first` | ``, for `vault/Map-code.md`), and for
   `vault/Design/lanes-and-supervisors.md`: `SUPERVISOR_DESC`, `WORKER_DESC`, `RUNTIME`, `HOST`,
   `ORG_ROOT`, `STATE_BRANCH` (must equal `state_backup_branch` in `org.json`; default
   `backup/lane-state`), `LANE_TABLE` (complete rows, one per lane, with six cells:
   `| lane | goal | <ORG_ROOT>/lanes/<lane> | lane/<lane>/* | max parallel | may land on main |`).
   The installer MERGES — an existing file is kept, `.gitignore` and `.claude/settings.json` get only
   what is missing (an existing `settings.json` that still holds a `{{KEY}}` is not merged, and the run
   exits 1) —
   strips the `.tmpl` suffix the kit uses for four protected entries, installs the PR gate
   `.github/workflows/org-gates.yml` (org-board, plan-ownership and sprawl on every PR to main), and
   regenerates the hubs, Map and Index. It REFUSES before writing anything (exit 2, naming the keys)
   if any key is missing, so a partial install cannot happen; a re-run never overwrites a file. It exits 1
   if an existing `.claude/settings.json` can't be parsed (fix it and re-run), and warns when an existing
   `ORG_*` env value there differs from the vars file (make them agree: the gates read settings).
2. **Owner rulings** live in `<repo>/.claude/rules/owner-rulings.md` (the four defaults plus
   `EXTRA_RULINGS`): the one standing source, versioned and protected. A later ruling is a line there in
   the owner's words, committed with `Authority: owner`. The kit installs seven rules: gate-independence,
   no-bloat, goals-not-tests, vault-first, evidence-and-honesty, protected-paths, owner-rulings. If the
   owner names more protected paths (the kit protects `vault/Plan.md`, `vault/Roadmap.md`,
   `vault/Decisions/`, `.claude/rules/` and `.claude/settings.json`), add them to
   `scripts/lib/protected-paths.mjs` (the ONE declaration) and to the four documents
   `scripts/gates/protected-paths.mjs` holds to it.
3. **CLAUDE.md:** append `KIT/templates/claude/CLAUDE.project-snippet.md` (filled: `HOST`, `ORG_ROOT`) to
   `<repo>/CLAUDE.md`, or create it. Skip this if `CLAUDE.md` already contains the snippet's first heading
   (a re-run must not duplicate it).
4. **First session note:** `vault/Sessions/<date>-agent-org-setup.md` from `vault/Templates/session.md`,
   recording the interview verbatim (replace or delete every blank in the template); then
   `node scripts/vault-hubs.mjs` and `python3 scripts/gen-subject-index.py`.
5. **Commit, then run the board.** Commit on a branch with `Authority: owner` in the message (the commit
   touches protected paths) and an `EVIDENCE-GROWTH:` paragraph. The sprawl gate grades that paragraph:
   it must name at least one added path with two or more segments (e.g. `vault/Home.md`,
   `scripts/gates/org-board.sh`) and, besides the paths, say in at least four words why the growth is
   needed. Then `bash scripts/gates/org-board.sh` must exit 0 (skips are named, e.g. the code map without
   a graph).
6. **Merge the set-up to main** once the owner agrees (lanes are cut from main, and `lanes.sh new` refuses
   while main lacks `vault/AGENTS.md`).

## 3. Generate the memory layer (auto-memory dir for this project)
The directory is `~/.claude/projects/<repo path with every / replaced by ->/memory/` (e.g.
`/home/me/app` → `~/.claude/projects/-home-me-app/memory/`). Copy and fill
`KIT/templates/memory/owner-rulings.md` (`PROJECT`, `ORG_ROOT`: a pointer to the repo's
`.claude/rules/owner-rulings.md`, never a copy of the rulings) and `org-architecture.md` (`LANE_LIST`:
lane names with one-line goals, plus the repo-layer keys of the same names), and add their lines from
`KIT/templates/memory/MEMORY.md` to `MEMORY.md`. Create the index if it is missing; merge if it exists,
never duplicating.

## 4. Generate the org layer (on the runtime host; for remote, run these over SSH)
**One user runs the org** (`org.json` `runtime`): **local** — the owner, as themselves, no worker user, no
sudo, no `/srv` (the build queue goes in `<ORG_ROOT>/bin`); **remote** — a Linux VPS where `worker_user` runs
the loop, git-sync, the snapshot and the builds. Nothing re-owns a repository: the repo must belong to that
user (clone it as them).
1. `ORG_ROOT` (default `~/agent-org`; remote e.g. `/srv/org`): `setup.mjs --scope org` writes `org.json`
   with local defaults; by hand, copy `KIT/scripts/org.example.json` (its example is remote) and fill it.
   Set `sync.push_main` to `true` only if the owner allowed pushes to main (a push to main may deploy); it
   defaults to `false`. Make `claude_bin` an absolute path (workers run with `worker_env.PATH`). Other keys:
   `bin_dir` (default `/srv/bin` remote, `<ORG_ROOT>/bin` local), `build_queue` (`slots`, `wrap`, and
   `real.<tool>` for a binary PATH can't find), `worktree_links` (git-ignored paths only — a tracked path is
   skipped and logged), `state_backup.include` (extra lane paths for the snapshot), the per-lane daily caps
   `max_consults_per_day` / `max_agent_starts_per_day` / `max_agent_hours_per_day`, `agent_timeout_s`,
   `consult_timeout_s` and `usage_limit_wait_s`.
2. Copy `KIT/scripts/` and `KIT/templates/lane/` to the host (keeping that layout), then run
   `bootstrap-host.sh <ORG_ROOT>` (`setup.mjs --bootstrap` runs it when the org runs on this machine):
   - **local:** as yourself. Refused as root, and refused with a `worker_user` (on macOS, or with
     runtime local).
   - **remote, phase 1, as root:** creates `worker_user`, hands it `ORG_ROOT` (not recursively), installs
     the build queue in `/srv/bin` and the worker's crontab line, then exits. **Phase 2, as the worker:**
     `su - <worker> -c 'bash <KIT>/scripts/bootstrap-host.sh <ORG_ROOT>'`.
   It checks the tools, copies the scripts and lane templates into `<ORG_ROOT>`, installs the
   `pre-edit-scan` and `memory-discipline` skills for that user (nothing else of the owner's global
   config: the router, standing procedure and session notes stay on the owner's machine), starts git-sync,
   and schedules the hourly job (`lanes.sh gc`, then `state-snapshot.sh`): a launchd agent on macOS (a run
   missed asleep runs on wake), else the crontab (lines tagged `# agent-org <ORG_ROOT>`; other lines are
   never touched), else a `systemd --user` timer, else a tmux loop that does not survive a reboot.
   **Logins are the owner's** (interactive, in their own terminal, never pasted into chat):
   - local: `claude` → `/login`; remote: `su - <worker> -c claude` → `/login` (or `claude setup-token`
     for a long-lived token);
   - `codex login --device-auth`, as the same user, if the supervisor is codex.

   Re-run the bootstrap's login check until both pass.
3. **Per lane:** `lanes.sh <ORG_ROOT> new <name> "<goal>" <par> <may_land>` (fills `LANE`, `LANE_GOAL`,
   `LANE_ROOT`). Then fill the rest of each lane's files by hand:
   - `context.md`: `PROJECT`, `USERS`, `ACCEPTANCE_BAR` (as in the vars file), `VISION_PARAGRAPH`,
     `FAILURES` (what has not worked, as bullets), `STATE` (where things stand) and `REPO_FACTS` (facts
     that bite: build commands, ports, traps);
   - the GOAL section of `supervisor-brief.md`: check it holds the owner's paragraph, verbatim;
   - `rulings.md`: rulings that bind this lane only (shown whole every consult; the project's standing
     ones come from `.claude/rules/owner-rulings.md`, which every consult also carries);
     `owner-answers.md` stays the raw, dated log of the owner's answers.
   `supervise.py` refuses to start a lane whose `context.md` or `supervisor-brief.md` is empty or still
   holds a `{{KEY}}` (logged `UNFILLED`).
4. `grep -rn '{{' <ORG_ROOT>/lanes/*/*.md` must print nothing; then `lanes.sh <ORG_ROOT> start`.

## 5. Become the overseer
0. Give this session the overseer's role: write `{"env": {"ORG_ROLE": "supervisor"}}` to
   `<repo>/.claude/settings.local.json` (merge if it exists; it is untracked, so worker worktrees never
   inherit it), then ask the owner to restart Claude Code in the repo. Without it the contract hook treats
   you as a subagent and refuses your edits to protected paths.
1. Arm a Monitor on `ssh <host> 'bash <ORG_ROOT>/lane-events.sh <ORG_ROOT>'` (or a local `bash …`) with
   `timeout_ms` 1800000, and re-arm it on expiry.
2. Save a filled copy of `KIT/templates/handoff/overseer-loop-prompt.md` (`PROJECT`, `HOST`, `ORG_ROOT`)
   as `<repo>/.claude/loop-prompts/org-tracker.md`. The owner starts the heartbeat with
   `/loop Follow .claude/loop-prompts/org-tracker.md`; you can't start `/loop` yourself, so ask them to.
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
- Never push to main or deploy unless the owner said a landing may deploy (that includes git-sync's
  `push_main`).
- Never kill a lane's tmux session while workers run. Use `lanes.sh restart`, which adopts them.
- Never touch processes or services on a shared host that aren't this org's.
- Never let ASK_OWNER questions sit unseen. If the overseer stops tracking, say so to the owner.
