# `agent-org`

A reusable kit that sets up the whole supervised agent organisation for any project from **one prompt**.
Each lane has a supervisor, Claude worker agents and their sub-agents. Around them, the kit sets up:
- vault management (Obsidian mission control);
- three-layer memory management;
- session handoff;
- the owner's rules;
- git sync and hourly state backup;
- an event feed with login probes;
- crash recovery.

## Install (once)
It ships with this `.claude` config: installing the config's `skills/` folder installs it, next to the
`pre-edit-scan` and `memory-discipline` skills its rules depend on. To track a clone instead of copying:
```bash
mkdir -p ~/.claude/skills && ln -s "<clone>/skills/agent-org" ~/.claude/skills/agent-org
```

## Use (one prompt, in Claude Code, in any repo)
```
/agent-org set up the agent organisation for this project
```
Claude interviews you about:
- the project and vision;
- local or VPS;
- which models for the supervisor, workers and sub-agents;
- the lanes and their goals;
- your rulings and what has failed before.

It shows a summary for your yes, then installs the repo layer (`templates/repo/`: the Obsidian vault with
its contracts and generated hubs, the six rules, the hooks, the role cards, and every enforcement gate)
with `scripts/init-repo.mjs`, runs the org board until it is green, sets up memory and the lanes, starts
everything, and becomes the overseer. The only things it leaves to you are the logins (`claude`, `codex`),
which you type in your own terminal. It also asks you to start the tracking `/loop`, and to restart Claude Code once so the
session runs with the overseer's role.

## Day to day
| | |
|---|---|
| see what's running | `lanes.sh <ORG_ROOT> status` |
| add a lane | `lanes.sh <ORG_ROOT> new <name> "<goal>" <parallel> <may_land>` then `start <name>` |
| restart a lane safely (workers keep running) | `lanes.sh <ORG_ROOT> restart <name>` |
| stop a lane (`start` resumes it) | `lanes.sh <ORG_ROOT> stop <name>` |
| answer a lane's question | the overseer appends your words to `lanes/<name>/owner-answers.md` and updates `rulings.md` |
| free disk (also hourly from cron) | `lanes.sh <ORG_ROOT> gc [name…]` |
| is each lane getting better? | `python3 <ORG_ROOT>/lane-metrics.py <ORG_ROOT> --days 7` |
| test the loop offline (kit) | `bash scripts/test-supervise.sh` |
| keep the overseer watching | `/loop Follow .claude/loop-prompts/org-tracker.md` |
| is the org itself healthy? (in the repo) | `bash scripts/gates/org-board.sh` |
| what is open, what was proposed (in the repo) | `node scripts/loop-state.mjs` · `node scripts/propose.mjs --list` |

Read `docs/HIERARCHY.md` for how it works and why every guard exists.
