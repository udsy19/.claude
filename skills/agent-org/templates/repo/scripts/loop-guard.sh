#!/usr/bin/env bash
# Stop-hook guard for the supervisor loop. COMPLETION DISCIPLINE, BOUNDED.
#
# Exits 2 (= block the turn from ending, with a reason on stderr) ONLY when ALL hold:
#   1. the mission in force — vault/Missions/$ORG_MISSION.md — says `state: running` in its
#      frontmatter (`state:` is the gating field; vocabulary running|paused|blocked-on-human|done)
#   2. vault/_log/agents.jsonl (written by the SubagentStop hook, scripts/usage-hook.sh — an
#      INDEPENDENT record of dispatches, not the agent's own account) has dispatches dated
#      today, and no session note dated today is at least as fresh as the LAST of them
#   3. the consecutive-block counter vault/.loop-blocks is under 3
# It resets the counter on any clean turn and NEVER blocks when ORG_MISSION is unset, the
# mission file is missing, or its state is anything but `running`.
#
# Falsification: scripts/loop-guard.count.test.sh (one scratch tree per case).
set -u
# Lane workers (supervise.py sets AGENT_NAME) keep no session note: their report is their trail.
# Blocking them would push parallel branches to edit the shared session files, or to pause the mission.
[ -n "${AGENT_NAME:-}" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# ORG_MISSION comes from .claude/settings.json's `env` block; read it from there when the
# hook environment does not carry it, so the guard and the settings cannot disagree.
if [ -z "${ORG_MISSION:-}" ] && [ -f "$ROOT/.claude/settings.json" ]; then
  ORG_MISSION=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('env',{}).get('ORG_MISSION',''))" "$ROOT/.claude/settings.json" 2>/dev/null)
fi
[ -n "${ORG_MISSION:-}" ] || exit 0
MISSION="$ROOT/vault/Missions/${ORG_MISSION}.md"
LOG="$ROOT/vault/_log/agents.jsonl"
COUNTER="$ROOT/vault/.loop-blocks"

clean() { rm -f "$COUNTER"; exit 0; }

[ -f "$MISSION" ] || clean
state=$(sed -n '1,/^---$/{s/^state:[[:space:]]*//p;}' "$MISSION" | head -1 | tr -d '[:space:]')
[ "$state" = "running" ] || clean
[ -f "$LOG" ] || clean

# The session note must be at least as fresh as the last dispatch: the loop's trail is the
# note, so a dispatch that happened after the note was last written is an unlogged dispatch.
today=$(date +%Y-%m-%d)
# COUNT THE DISPATCHES, NOT THE LINES.
#
# This once counted every line dated today: 239 when SEVEN real dispatches had happened,
# because 233 entries carried `"agent":""` (jq's `//` falls through on null/false but NOT on
# an empty string). The WRITER knew; the READER never learned.
#
# The verdict was still right — dispatches did happen and the note was stale — but a guard
# that says "239 dispatches" when you made seven is a guard you learn to dismiss, and this
# one's whole job is to block. A true verdict carrying a fictional number spends the trust
# it needs for the next true verdict.
# `grep -c` ALREADY PRINTS 0 when it matches nothing, and exits 1 while doing it — so the
# idiomatic `$(grep -c … || echo 0)` emits "0\n0", and every arithmetic test downstream then
# reads garbage. My first version of this fix had exactly that, and its own falsification
# caught it: the four cases reported 7/233 correctly and then 2, 2, 2 for logs holding 0, 0
# and 3 dispatches. Substitute the empty-file case explicitly instead of short-circuiting.
lines=$(grep -c "\"ts\":\"$today" "$LOG" 2>/dev/null); lines=${lines:-0}
attributed=$(grep "\"ts\":\"$today" "$LOG" 2>/dev/null | grep -cv '"agent":""'); attributed=${attributed:-0}
unattributed=$((lines - attributed))
# NOT a silent filter. If every stop today was unattributed, dispatches still happened and
# this guard must still fire — it just cannot name them. Making a check ignore something
# always needs a guard that it still sees something, and here that guard is this branch.
if [ "$attributed" -gt 0 ]; then
  dispatched="$attributed"
  [ "$unattributed" -gt 0 ] && dispatched="$attributed (plus $unattributed subagent stop(s) the log could not attribute)"
elif [ "$lines" -gt 0 ]; then
  dispatched="$lines unattributed subagent stop(s) — no agent type recorded, so these cannot be named"
else
  clean
fi
# The independent log proves dispatches happened today; the supervisor's own dispatch table
# (the mission file) says when the LAST one was recorded; the session note must be at least
# that fresh. Sub-sub-agent stops also land in the log, so the log's mtime alone over-fires.
note=$(ls -t "$ROOT/vault/Sessions"/"$today"-*.md 2>/dev/null | head -1)
# COMPARE THE NOTE TO THE LAST DISPATCH, NOT TO THE MISSION FILE.
#
# An earlier version compared the note to the MISSION FILE, a static document nobody edits,
# so ANY note written today satisfied it for the rest of the day, however many agents were
# dispatched after it (measured: sixteen hours and eight passes of silence). The right
# reference is the last attributed dispatch, which this script already reads.
last_ts=$(grep "\"ts\":\"$today" "$LOG" 2>/dev/null | grep -v '"agent":""' | tail -1 |
          sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')
if [ -n "$note" ]; then
  if [ -z "$last_ts" ]; then
    # Dispatches happened but none is attributable to a time — cannot establish staleness,
    # so do not assert it. A guard that cannot measure must not accuse (gate-independence law 7).
    clean
  fi
  # `date -j -f` is BSD/macOS; GNU `date -d` is the fallback. If NEITHER parses the stamp
  # the comparison is unavailable and the guard stays silent rather than guessing.
  last_epoch=$(python3 -c "import datetime as d,sys;print(int(d.datetime.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=d.timezone.utc).timestamp()))" "$last_ts" 2>/dev/null)
  [ -n "$last_epoch" ] || clean
  # ONE PORTABLE CALL, NOT A `||` LADDER. `stat -f %m` is BSD; on GNU `-f` means FILESYSTEM
  # status, prints to stdout AND exits non-zero, so a `||` fallback's output CONCATENATES
  # with it and the integer test fails on a fresh note. A first command that partially
  # succeeds POISONS the fallback. python3 has no such split.
  note_epoch=$(python3 -c "import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))" "$note" 2>/dev/null)
  [ -n "$note_epoch" ] || clean
  # strictly-older only: a note written in the same second as a dispatch is fresh.
  [ "$note_epoch" -ge "$last_epoch" ] && clean
fi
logged=$([ -n "$note" ] && echo "1 (STALE: written $(date -r "$note_epoch" '+%H:%M' 2>/dev/null), before the last dispatch at $last_ts)" || echo 0)

blocks=$(cat "$COUNTER" 2>/dev/null || echo 0)
if [ "$blocks" -ge 3 ]; then clean; fi
echo $((blocks + 1)) > "$COUNTER"
echo "loop-guard: $dispatched agent dispatch(es) today but $logged session note(s) in vault/Sessions — write the session note (/session-close) or set the mission state to paused before ending the turn (block $((blocks + 1))/3)." >&2
exit 2
