#!/bin/bash
# One-line installer for the kimi-code status line + TUI preferences.
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/env/main/kimi-code/install.sh)"
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/darkClaw921/env/main/kimi-code"
KIMI_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"

echo "-> Installing kimi-code status line into $KIMI_HOME"
mkdir -p "$KIMI_HOME/.cache"

curl -fsSL "$REPO_RAW/statusline.sh" -o "$KIMI_HOME/statusline.sh"
chmod +x "$KIMI_HOME/statusline.sh"
echo "   statusline.sh installed"

TUI="$KIMI_HOME/tui.toml"
if [ -f "$TUI" ]; then
  cp "$TUI" "$TUI.backup-$(date +%Y%m%d-%H%M%S)"
  # drop any existing [status_line] block (up to the next blank line)
  sed -i.bak '/^\[status_line\]/,/^$/d' "$TUI"
  rm -f "$TUI.bak"
  # enable fullscreen (mouse scroll) mode
  if grep -q '^tui_mode[[:space:]]*=' "$TUI"; then
    sed -i.bak 's|^tui_mode[[:space:]]*=.*|tui_mode = "fullscreen" # enables mouse scroll/selection|' "$TUI"
    rm -f "$TUI.bak"
  else
    { printf 'tui_mode = "fullscreen" # enables mouse scroll/selection\n'; cat "$TUI"; } > "$TUI.tmp"
    mv "$TUI.tmp" "$TUI"
  fi
else
  curl -fsSL "$REPO_RAW/tui.toml" -o "$TUI"
fi
cat >> "$TUI" <<'EOF'

[status_line]
items = ["mode", "model", "tasks", "cwd", "git"]
command = "~/.kimi-code/statusline.sh"
EOF
echo "   tui.toml updated"

echo "Done. Start a new kimi session (or run /reload-tui)."
echo "Note: quota in the status line appears after 'kimi /login'."
