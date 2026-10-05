#!/bin/bash
# Falsification for scripts/loop-guard.sh. One scratch tree per case — a harness that reused
# one tree once reported 2/2/2 for logs holding 0, 0 and 3. A harness that cannot be trusted
# is worse than no harness.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/loop-guard.sh"
today=$(date +%Y-%m-%d); day_utc=$(date -u +%Y-%m-%d)   # notes: local date; the dispatch log: UTC, as usage-hook.sh writes it
FAILED=0
unset AGENT_NAME AGENT_ORG_HEADLESS   # a lane worker running this suite must not silence every case (case K tests that path)
CASES=0
# $5 is the COUNT the message must report, and it is the whole point of this file.
# Without it the suite asserted exit codes only — and counting LINES instead of dispatches
# does not change any exit code, so the sabotage that restores the shipped defect came back
# GREEN. A falsification that returns NULL on the defect its test exists for is a test that
# measures nothing; the exit codes were never the property under test, the NUMBER was.
# SET AN MTIME PORTABLY. `date -r <epoch>` is BSD/macOS only — on GNU `-r` means "reference
# FILE" — so a suite written on a Mac failed on the Linux box that runs it. python3 has no
# such split.
set_mtime() { python3 -c "import os,sys; t=int(sys.argv[2]); os.utime(sys.argv[1],(t,t))" "$1" "$2"; }

case_run() {
  local label="$1" nat="$2" nemp="$3" want="$4" want_count="$5"
  CASES=$((CASES + 1))
  local T; T=$(mktemp -d)
  mkdir -p "$T/vault/_log" "$T/vault/Sessions" "$T/vault/Missions" "$T/scripts"
  cp "$SRC" "$T/scripts/loop-guard.sh"
  printf -- '---\nstate: running\n---\n' > "$T/vault/Missions/test-mission.md"
  : > "$T/vault/_log/agents.jsonl"
  local i
  i=0; while [ $i -lt "$nat" ]; do echo "{\"ts\":\"${day_utc}T01:00:00Z\",\"agent\":\"bug-fixer\",\"session\":\"s\"}" >> "$T/vault/_log/agents.jsonl"; i=$((i+1)); done
  i=0; while [ $i -lt "$nemp" ]; do echo "{\"ts\":\"${day_utc}T02:00:00Z\",\"agent\":\"\",\"session\":\"s\"}" >> "$T/vault/_log/agents.jsonl"; i=$((i+1)); done
  local out rc
  out=$(ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" 2>&1); rc=$?
  local verdict="ok"
  if [ "$rc" != "$want" ]; then verdict="MISMATCH (wanted exit $want)"; FAILED=$((FAILED + 1)); fi
  if [ -n "$want_count" ] && ! printf '%s' "$out" | grep -q -- "$want_count"; then
    verdict="MISCOUNT (message must report: $want_count)"; FAILED=$((FAILED + 1))
  fi
  printf '%-44s exit=%s  %-11s %s\n' "$label" "$rc" "$verdict" "$(echo "$out" | head -1 | sed 's/loop-guard: //;s/ — write.*//' | cut -c1-72)"
  rm -rf "$T"
}
echo "=== loop-guard dispatch count, one clean tree per case ==="
case_run "A  7 real + 233 unattributed (today)"  7 233 2 "7 (plus 233 subagent stop(s) the log could not attribute)"
case_run "B  0 real + 5 unattributed"            0 5   2 "5 unattributed subagent stop(s)"
case_run "C  0 real + 0 unattributed"            0 0   0 ""
case_run "D  3 real + 0 unattributed"            3 0   2 "3 agent dispatch(es) today"

# ─────────── FRESHNESS: the note must be newer than the LAST DISPATCH ───────────
# The guard once compared the note to the MISSION FILE, which nobody edits, so any note
# written today satisfied it for the rest of the day. EVERY CASE DECLARES ITS EXPECTED
# OUTCOME BEFORE IT RUNS — verifying a cut landed is not enough to know the case tested what
# its label says.
fresh_case() {
  local label="$1" note_offset="$2" want="$3" want_text="$4"   # note_offset: seconds relative to the dispatch
  CASES=$((CASES + 1))
  local T; T=$(mktemp -d)
  mkdir -p "$T/vault/_log" "$T/vault/Sessions" "$T/vault/Missions" "$T/scripts"
  cp "$SRC" "$T/scripts/loop-guard.sh"
  printf -- '---\nstate: running\n---\n' > "$T/vault/Missions/test-mission.md"
  # THE MISSION FILE IS DELIBERATELY MADE OLD, and that is what makes case E discriminate:
  # with the mission old and the note written between it and the last dispatch, the old
  # (mission-file) comparison is silent and the dispatch comparison fires. An earlier harness
  # set the note in the future, so all three cases passed against the OLD code as well —
  # three vacuous cases that read as a falsification.
  local disp; disp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if [ "$note_offset" != "none" ]; then
    echo "{\"ts\":\"${day_utc}T01:00:00Z\",\"agent\":\"bug-fixer\",\"session\":\"s\"}" > "$T/vault/_log/agents.jsonl"
    echo "{\"ts\":\"$disp\",\"agent\":\"bug-fixer\",\"session\":\"s\"}" >> "$T/vault/_log/agents.jsonl"
  else
    echo "{\"ts\":\"$disp\",\"agent\":\"bug-fixer\",\"session\":\"s\"}" > "$T/vault/_log/agents.jsonl"
  fi
  if [ "$note_offset" != "none" ]; then
    local nf="$T/vault/Sessions/${today}-note.md"; echo "# note" > "$nf"
    local de; de=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$disp" '+%s' 2>/dev/null || date -u -d "$disp" '+%s')
    set_mtime "$nf" $((de + note_offset))
  fi
  set_mtime "$T/vault/Missions/test-mission.md" $((de - 86400))
  local out rc; out=$(PATH="${CASE_PATH:-$PATH}" ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" 2>&1); rc=$?
  local v="ok"
  [ "$rc" = "$want" ] || { v="MISMATCH (wanted exit $want)"; FAILED=$((FAILED + 1)); }
  if [ -n "$want_text" ] && ! printf '%s' "$out" | grep -q -- "$want_text"; then
    v="MISTEXT (must say: $want_text)"; FAILED=$((FAILED + 1))
  fi
  printf '%-52s exit=%s  %-12s %s\n' "$label" "$rc" "$v" "$(echo "$out" | head -1 | sed 's/.*session note(s)//;s/ — write.*//' | cut -c1-30)"
  rm -rf "$T"
}
echo
echo "=== freshness: note vs LAST DISPATCH (not vs the mission file) ==="
fresh_case "E  note after the mission, BEFORE the dispatch -> FIRE" -60 2 "STALE"
fresh_case "F  note 60 s AFTER  the dispatch -> must be SILENT"  60  0 ""
fresh_case "G  no note at all, dispatches exist -> must FIRE" none 2 ""
# GNU `date` reads `-r` as a reference FILE, so `date -r <epoch>` fails on Linux. A stub that
# behaves that way proves the message no longer depends on BSD date (it once said "written ,").
GNU_DATE=$(mktemp -d); REAL_DATE=$(command -v date)
# shellcheck disable=SC2016  # the fake date script is written with literal $vars
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = -r ] && { echo "date: $2: No such file or directory" >&2; exit 1; }; done\nexec %s "$@"\n' "$REAL_DATE" > "$GNU_DATE/date"; chmod +x "$GNU_DATE/date"
CASE_PATH="$GNU_DATE:$PATH" fresh_case "M  GNU date (no -r epoch) -> STALE still says HH:MM" -60 2 "STALE: written [0-9][0-9]:[0-9][0-9],"
rm -rf "$GNU_DATE"
# The log is UTC, notes are local: wherever the two dates differ (every evening west of UTC, every
# morning east of it) a guard matching the log by LOCAL date found no dispatches and went silent.
# At any moment at least one of these two zones has a date different from UTC's, so this is
# deterministic around the clock.
TZ=Etc/GMT+12 fresh_case "P  UTC-12: no note, dispatches exist -> must FIRE" none 2 ""
TZ=Etc/GMT-14 fresh_case "Q  UTC+14: no note, dispatches exist -> must FIRE" none 2 ""

# ─────────── SCOPE: the guard is silent when no mission is in force ───────────
CASES=$((CASES + 1))
T=$(mktemp -d); mkdir -p "$T/vault/_log" "$T/vault/Missions" "$T/scripts"; cp "$SRC" "$T/scripts/loop-guard.sh"
printf -- '---\nstate: running\n---\n' > "$T/vault/Missions/test-mission.md"
echo "{\"ts\":\"${day_utc}T01:00:00Z\",\"agent\":\"builder\",\"session\":\"s\"}" > "$T/vault/_log/agents.jsonl"
rc=0; (unset ORG_MISSION; CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1) || rc=$?
v="ok"; [ "$rc" = "0" ] || { v="MISMATCH (wanted exit 0)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "H  ORG_MISSION unset -> must be SILENT" "$rc" "$v"
rc=0; ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1 || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "2" ] || { v="MISMATCH (wanted exit 2 — the positive control)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "I  same tree, ORG_MISSION set -> must FIRE (control)" "$rc" "$v"
printf -- '---\nstate: paused\n---\n' > "$T/vault/Missions/test-mission.md"; rm -f "$T/vault/.loop-blocks"
rc=0; ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1 || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "0" ] || { v="MISMATCH (wanted exit 0)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "J  state: paused -> must be SILENT" "$rc" "$v"
printf -- '---\nstate: running\n---\n' > "$T/vault/Missions/test-mission.md"; rm -f "$T/vault/.loop-blocks"
rc=0; AGENT_NAME=a1 ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1 || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "0" ] || { v="MISMATCH (wanted exit 0)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "K  lane worker (AGENT_NAME set) -> must be SILENT" "$rc" "$v"
rc=0; (unset AGENT_NAME; ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1) || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "2" ] || { v="MISMATCH (wanted exit 2 — the control for K)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "L  same tree, no AGENT_NAME -> must FIRE (control)" "$rc" "$v"
rc=0; AGENT_ORG_HEADLESS=1 ORG_ROLE=supervisor ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1 || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "0" ] || { v="MISMATCH (wanted exit 0)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "N  lane supervisor (headless, no AGENT_NAME) -> SILENT" "$rc" "$v"
rc=0; ORG_ROLE=supervisor ORG_MISSION=test-mission CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/loop-guard.sh" >/dev/null 2>&1 || rc=$?
CASES=$((CASES + 1)); v="ok"; [ "$rc" = "2" ] || { v="MISMATCH (wanted exit 2 — the overseer, the control for N)"; FAILED=$((FAILED + 1)); }
printf '%-52s exit=%s  %s\n' "O  overseer (ORG_ROLE=supervisor, interactive) -> FIRE" "$rc" "$v"
rm -rf "$T"

# AN EXIT CODE, NOT A PRINTED WORD: a board reads the code, not the prose (gate-independence
# law 6).
if [ "$FAILED" -eq 0 ]; then
  echo "LOOP-GUARD-COUNT PASS ($CASES cases, 0 failing)"; exit 0
fi
echo "LOOP-GUARD-COUNT FAIL ($FAILED of $CASES cases)"; exit 1
