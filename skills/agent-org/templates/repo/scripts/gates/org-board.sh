#!/usr/bin/env bash
# scripts/gates/org-board.sh — the organisation's own board: every vault, plan, ownership,
# anti-sprawl and anti-duplicate gate, aggregated BY EXIT CODE (gate-independence law 6: a
# board may not trust a summary line; the deciding act must not be a human reading prose).
#
#   bash scripts/gates/org-board.sh            run every row
#
# Exit codes, per row and for the board:
#   0   green
#   1   red                         → the board exits 1
#   2   refused (could not grade)   → counted RED: a row that cannot measure is not a pass
#   77  declared skip (e.g. an empty landing range) → named in the tally, NEVER a tick
#   any other / a hang              → counted RED, named as NO VERDICT
# The board exits 0 only when no row is red; skips are printed by name either way.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2
if [ "$#" -gt 0 ]; then echo "org-board: unrecognised argument: $1" >&2; echo "org-board: takes no arguments" >&2; exit 2; fi

GREEN=(); RED=(); SKIP=()
row() {   # row <name> <command...>
  local name="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  case "$rc" in
    0)  GREEN+=("$name"); printf '  ok    %s\n' "$name" ;;
    77) SKIP+=("$name");  printf '  skip  %s — %s\n' "$name" "$(printf '%s\n' "$out" | grep -m1 -i 'skip' | cut -c1-110)" ;;
    *)  RED+=("$name (exit $rc)"); printf '  RED   %s (exit %s)\n' "$name" "$rc"
        printf '%s\n' "$out" | grep -E 'FAIL|REFUSED|STALE|MISMATCH|MISCOUNT|Error' | head -8 | sed 's/^/          /' ;;
  esac
}

echo "ORG-BOARD — $(git rev-parse --short HEAD 2>/dev/null || echo 'no HEAD')"
row 'vault hubs current'          node scripts/vault-hubs.mjs --check
row 'vault index current'         python3 scripts/gen-subject-index.py --check
row 'code map current'            python3 scripts/gen-code-map.py --check
row 'vault reachability'          node scripts/gates/vault-reachability.mjs
row 'vault reachability selftest' node scripts/gates/vault-reachability.mjs --selftest
row 'plan integrity'              node scripts/gates/plan-integrity.mjs
row 'plan hierarchy'              node scripts/gates/plan-hierarchy.mjs
row 'protected paths'             node scripts/gates/protected-paths.mjs
row 'rules index'                 node scripts/gates/rules-index.mjs
row 'plan ownership'              node scripts/gates/plan-ownership.mjs
row 'sprawl'                      node scripts/gates/sprawl.mjs
row 'sprawl selftest'             node scripts/gates/sprawl.mjs --selftest
row 'loop state'                  node scripts/loop-state.mjs --check
row 'agent-contract hook'         node scripts/hooks/agent-contract.test.mjs
row 'propose channel'             node scripts/propose.test.mjs
row 'where'                       node scripts/where.test.mjs
row 'loop guard'                  bash scripts/loop-guard.count.test.sh

total=$(( ${#GREEN[@]} + ${#RED[@]} + ${#SKIP[@]} ))
echo
if [ "${#SKIP[@]}" -gt 0 ]; then echo "skipped (not passes): ${SKIP[*]}"; fi
if [ "${#RED[@]}" -gt 0 ]; then
  echo "ORG-BOARD FAIL — ${#RED[@]} of $total row(s) red, ${#SKIP[@]} skipped"
  for r in "${RED[@]}"; do echo "  $r"; done
  exit 1
fi
echo "ORG-BOARD PASS — ${#GREEN[@]} of $total row(s) green, ${#SKIP[@]} skipped"
exit 0
