# claude

Claude Code (claude-code CLI) personal config.

## What's inside

- `statusline.sh` — status line: dir/git, context bar with remaining-before-autocompact,
  session cost + total tokens, Anthropic 5h/7-day rate limits with reset countdowns.
- `hooks/` — lifecycle hooks wired in `settings.json`:
  - `claude-notify-hook.sh` — terminal notifications (Notification/Stop);
  - `claude-permission-hook.sh` — notification on permission requests;
  - `hourglyph.sh` — posts session/turn token stats to a personal Supabase table
    (uses a **publishable** key, safe to expose, but it's your endpoint — keep in mind);
  - `claude-notify-hook1.sh` / `claude-notify-hook2.sh` — variants not referenced by settings.
- `settings.json` — permissions, hooks, statusLine, language (ru), model efforts, fullscreen TUI.

## Install (one line)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/env/main/claude/install.sh)"
```

The installer downloads `statusline.sh` + `hooks/` into `~/.claude/` and replaces
`settings.json` (backing up the previous one). Idempotent: re-runs are safe.

## Notes

- macOS-oriented: notifications rely on `osascript`/terminal-notifier style hooks.
- The Anthropic quota segment reads credentials from the macOS Keychain
  (`security find-generic-password -s "Claude Code-credentials"`) — it appears
  automatically after you log in with `claude` on a new machine.
