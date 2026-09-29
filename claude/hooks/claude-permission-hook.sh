#!/bin/bash
PORT="${CLAUDE_NOTIFY_PORT:-23517}"
INPUT=$(cat)

# POST event to macOS app (fire & forget)
curl -s -X POST -H "Content-Type: application/json" \
  -d "$INPUT" --connect-timeout 1 --max-time 2 \
  "http://localhost:${PORT}/event" > /dev/null 2>&1 &
disown

# Clean up stale decision file
rm -f /tmp/claude-permission-decision

# Poll for decision (240 * 0.5s = 120 seconds timeout)
TRIES=240
I=0
while [ "$I" -lt "$TRIES" ]; do
  if [ -f /tmp/claude-permission-decision ]; then
    DECISION=$(cat /tmp/claude-permission-decision)
    rm -f /tmp/claude-permission-decision
    if [ "$DECISION" = "allow" ]; then
      echo '{"behavior": "allow"}'
    elif [ "$DECISION" = "deny" ]; then
      echo '{"behavior": "deny"}'
    fi
    exit 0
  fi
  sleep 0.5
  I=$((I + 1))
done

# Timeout — no decision
exit 0