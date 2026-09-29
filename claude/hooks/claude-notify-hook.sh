#!/bin/bash
PORT="${CLAUDE_NOTIFY_PORT:-23517}"
INPUT=$(cat)
curl -s -X POST -H "Content-Type: application/json" \
  -d "$INPUT" --connect-timeout 1 --max-time 2 \
  "http://localhost:${PORT}/event" > /dev/null 2>&1 || true
exit 0