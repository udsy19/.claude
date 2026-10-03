---
name: org-architecture
description: How this project's agent organisation runs — lanes, supervisors, workers, state, recovery
metadata:
  type: project
---
Org root `{{ORG_ROOT}}` on {{RUNTIME}} ({{HOST}}).
- **Supervisor:** {{SUPERVISOR_DESC}}.
- **Workers:** {{WORKER_DESC}}.
- **Lanes:** {{LANE_LIST}}.

The loop is `supervise.py` (rolling dispatch, adoption on restart). The event feed is `lane-events.sh`,
which the overseer watches with a Monitor; the heartbeat is the owner-started
`/loop Follow .claude/loop-prompts/org-tracker.md`. Sync and backup:
- `git-sync.sh`, every 5 min;
- `state-snapshot.sh`, hourly to `{{STATE_BRANCH}}`.

Full description: `vault/Design/lanes-and-supervisors.md`.

**Why:** the owner wants the organisation reproducible and resilient: work is never lost, and nothing waits
on a sleeping overseer.
**How to apply:** on session start, read the vault Home and the newest session note, then run
`lanes.sh status`. Never restart a loop by killing its tmux session while workers run; use
`lanes.sh restart`, which adopts them. Related: [[owner-rulings]].
