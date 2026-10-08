#!/usr/bin/env bash
# Hourly: copy each lane's RECOVERY state — what lives outside git and a restart needs — into a git branch
# (org.json state_backup_branch, default backup/lane-state) and push it to origin: anyone who can read origin can
# read it. Per lane, only: plan.md, lane-memory*.md, rulings.md, owner-questions.md, lane.json, loop-state.json,
# context.md and supervisor-brief.md (the lane's goal: recovery must not mean retyping it) and the pinned renders
# (renders/owner, renders/latest); plus org.json reduced to an allowlist of known-safe keys. Anything else
# (prompts, rounds, reports, owner-answers.md, supervise.out …) only if org.json state_backup.include
# names it, as a path or rsync pattern relative to a lane dir. Never build dirs or worktrees.
# usage: state-snapshot.sh <ORG_ROOT>        (hourly, from the job bootstrap-host.sh installs)
ORG_ROOT=${1:?ORG_ROOT}; CFG=$ORG_ROOT/org.json
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[2]));print(eval(sys.argv[1]))" "$1" "$CFG"; }
R=$(j 'd["repo"]'); BR=$(j 'd.get("state_backup_branch","backup/lane-state")')
W=$ORG_ROOT/state-wt
cd "$R" || exit 1
git show-ref -q --verify "refs/heads/$BR" || git branch -q "$BR" "$(git commit-tree "$(git hash-object -t tree /dev/null)" -m 'lane state root')"
[ -d "$W" ] || { git worktree prune; git worktree add -q "$W" "$BR"; }   # prune: a deleted state-wt stays registered
[ -e "$W/.git" ] || { echo "$(date -u +%F' '%H:%M) no snapshot worktree at $W — not snapshotting"; exit 1; }
inc=(); for p in plan.md 'lane-memory*.md' rulings.md owner-questions.md lane.json loop-state.json context.md supervisor-brief.md \
                 renders/ renders/owner/ 'renders/owner/*.png' renders/latest/ 'renders/latest/*.png'; do inc+=(--include="/*/$p"); done
while IFS= read -r p; do [ -n "$p" ] && inc+=(--include="/*/${p%/}" --include="/*/${p%/}/**"); done \
  < <(j '"\n".join(d.get("state_backup", {}).get("include", []))')
mkdir -p "$ORG_ROOT/lanes" "$W/lanes"
rsync -a --delete --delete-excluded --include='/*/' "${inc[@]}" --exclude='*' "$ORG_ROOT/lanes/" "$W/lanes/"
find "$W" -mindepth 1 -maxdepth 1 ! -name .git ! -name lanes -exec rm -rf {} +   # older kits copied scripts and renders here
python3 - "$CFG" "$W/org.json" <<'PY'
# org.json goes to origin, so only keys known to be safe are copied (an allowlist, not a secret-name guess: a
# blocklist on "auth" also dropped auth_probe_interval_s). Anything else is left out and NAMED, so a recovery
# knows what to re-add by hand. True = keep the value; a set = keep only those sub-keys; "map" = a name->value map.
import json, sys
SUP = {"backend", "model", "effort", "web_search", "command", "web_domains"}
ALLOW = {"_comment": True, "_isolation": True, "_supervisor_alt": SUP, "project": True, "repo": True, "main_branch": True,
         "runtime": True, "host": True, "worker_user": True, "claude_bin": True, "bin_dir": True, "supervisor": SUP,
         "worker_models": "map", "default_worker_model": True, "worker_env": {"PATH"},
         "commit_env": {"GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"},
         "per_agent_build_dir": True, "worktree_links": True, "build_queue": {"slots", "wrap", "real"},
         "sync": {"push_main", "branch_globs", "interval_s"}, "state_backup_branch": True,
         "state_backup": {"include"}, "auth_probe_interval_s": True, "agent_timeout_s": True,
         "max_consults_per_day": True, "max_agent_starts_per_day": True, "max_agent_hours_per_day": True,
         "consult_timeout_s": True, "usage_limit_wait_s": True, "idle_wait_s": True, "poll_interval_s": True,
         "report_overdue_s": True, "lane_memory_tail_bytes": True, "lane_memory_consolidate_every": True,
         "owner_answers_recent": True,
         "isolation": {"mode", "srt_bin", "allowed_domains", "allow_read", "allow_write", "auth_token_file"}}
out, dropped = {}, []
for k, v in json.load(open(sys.argv[1])).items():
    spec = ALLOW.get(k)
    if spec is None:
        dropped.append(k)
    elif isinstance(spec, set) and isinstance(v, dict):
        out[k] = {s: x for s, x in v.items() if s in spec}
        dropped += [f"{k}.{s}" for s in v if s not in spec]
    else:
        out[k] = v
json.dump(out, open(sys.argv[2], "w"), indent=2)
if dropped:
    print(f"snapshot: org.json keys not backed up (not on the allowlist; re-add by hand on recovery): {', '.join(dropped)}")
PY
cd "$W" && git add -A && { git commit -q --no-verify -m "lane state snapshot $(date -u +%F' '%H:%MZ)" || true; } \
  && git push -q origin "$BR" && echo "$(date -u +%F' '%H:%M) lane state snapshot pushed"   # pushes a missed commit too
exit 0
