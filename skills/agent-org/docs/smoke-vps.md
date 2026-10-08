# Remote-mode smoke test (runbook)

CI runs every host script under fakes. This run exercises once, on a real Linux box, what those fakes stand in
for: `useradd`, `crontab -u`, a real worker login, real tmux, `flock` and git. Do it before the first remote org
points at a real project. A run takes about an hour, including the box.

## You need

- A **disposable** Ubuntu LTS host, reachable as `root` over SSH with a key (`ssh -o BatchMode=yes root@HOST true`
  must succeed). The script installs packages, creates the user `agent`, and edits root's and agent's crontabs.
- A Claude account to log the worker in (Pro/Max/Team/Enterprise/Console). From step 2 on, the run calls no model:
  the supervisor is the script backend and the workers are a fake binary.

## Run it

```bash
bash skills/agent-org/scripts/smoke-vps.sh root@HOST
```

1. Step 1 (phase A, as root) runs the following, then **stops with exit 10**:
   - installs git, tmux, python3, rsync, jq, cron and nodejs;
   - installs Claude Code from Anthropic's signed apt repository, checking the key fingerprint
     (https://code.claude.com/docs/en/setup);
   - writes `/srv/org/org.json` (`runtime: vps`, `worker_user: agent`, a Claude supervisor,
     `build_queue.wrap: ["cargo build"]`, caps 30/10/12);
   - runs bootstrap phase 1;
   - clones the project repo as `agent` and installs the vault on its `main`.
2. Log the worker in, interactively, on the box:
   ```bash
   ssh -t root@HOST "su - agent -c 'claude'"      # then /login, then exit
   ```
3. Resume. Step 1 re-runs phase A as a no-op, then runs bootstrap phase 2 twice as `agent`, and continues
   through step 8:
   ```bash
   bash skills/agent-org/scripts/smoke-vps.sh root@HOST --resume-from 1
   ```

Any other non-zero exit names the failed step. Fix it on a branch, with a check that fails first, then resume
from that step with `--resume-from N`. Everything goes to `./smoke-vps-<UTC stamp>.log`, or `$SMOKE_LOG`.

## What each step must produce

| Step | Artefact |
|---|---|
| 1 | phase 1: user `agent`; `/srv/bin/build-queue` and the `cargo` wrapper; `crontab -u agent -l` holds only the tagged line; the phase-2 command printed. Repo and `.git` owned by `agent`; org-board passes. Phase 2: `host ready (remote, as agent)` and `worker claude: OK`; a re-run leaves the crontab unchanged; git-sync is running |
| 2 | `lanes.sh start` as root is refused and names `su - agent -c "…"`, with no session created; as `agent`, `lane-core` runs |
| 3 | the workers' pid files; `MERGE lane/core/alpha ok`; `hubs regenerated after MERGE`; `LAND lane/core/planner REFUSED` with `reports/*zz-land-refused-lane-core-planner.md`; `main` unmoved; `lane/*` on origin within one sync interval; with the repo parked on another branch, local `main` fast-forwards and `HEAD` stays put |
| 4 | `status` lists `core/sleeper`; after `restart`, `adopted running agent sleeper`; `gc` prints `keep wt/sleeper` and the worktree stays |
| 5 | the cron line's command, run as `agent`, exits 0; the snapshot branch on origin holds the lane's recovery files and nothing outside the allowlist; its `org.json` has every key of the live one |
| 6 | three `cargo build` jobs on 2 slots: the third starts after the first ends; locks in `/srv/org/locks`; with no real cargo, exit 127 with `build-queue: no real cargo` |
| 7 | `find /home/agent/demo/.git /srv/org ! -user agent` prints nothing |
| 8 | after `lanes.sh stop core`, the loop exits, its agents finish, no lane process is left, and git-sync is still running |

## Record it

Add `skills/agent-org/docs/smoke-vps-<date>.md` with:
- the host image (`lsb_release -ds`, `uname -r`), `claude --version` and the kit SHA (the log's first line);
- each step's artefact lines from the log;
- every bug the run found, with its fix commit.

That record is the evidence that remote mode has run once.
