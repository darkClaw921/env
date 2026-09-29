#!/bin/bash
# Installer for the Claude Code config: statusline, hooks, settings.
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/env/main/claude/install.sh)"
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/darkClaw921/env/main/claude"
CLAUDE_DIR="$HOME/.claude"

echo "-> Installing Claude Code config into $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/hooks"

curl -fsSL "$REPO_RAW/statusline.sh" -o "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo "   statusline.sh installed"

for hook in claude-notify-hook.sh claude-notify-hook1.sh claude-notify-hook2.sh claude-permission-hook.sh hourglyph.sh; do
  curl -fsSL "$REPO_RAW/hooks/$hook" -o "$CLAUDE_DIR/hooks/$hook"
  chmod +x "$CLAUDE_DIR/hooks/$hook"
done
echo "   hooks installed"

SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"
fi
curl -fsSL "$REPO_RAW/settings.json" -o "$SETTINGS"
echo "   settings.json installed (previous backed up if any)"

echo "Done. Start a new Claude Code session."
