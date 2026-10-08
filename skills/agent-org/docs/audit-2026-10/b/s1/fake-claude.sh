#!/usr/bin/env bash
case "$*" in *"reply with just OK"*) echo OK; exit 0;; esac
prompt=$(cat); report=$(printf '%s' "$prompt" | grep -o 'Write your report to `[^`]*`' | head -1 | sed 's/.*`\(.*\)`/\1/')
[ -f "$LANE_ROOT/../../worker-$AGENT_NAME.sh" ] && . "$LANE_ROOT/../../worker-$AGENT_NAME.sh"
printf '## TL;DR\n%s done\n' "$AGENT_NAME" > "$report"
