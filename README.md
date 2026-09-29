# kimi-code-setup

Status line + TUI preferences for [Kimi Code CLI](https://moonshotai.github.io/kimi-code/):
model/mode/cwd/git/context, live quota (5h window + monthly) with reset countdown
and burn-rate projections ("~2h15m" until a limit runs out at the current pace).

## Install (one line)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/kimi-code-setup/main/install.sh)"
```

The installer:

- downloads `statusline.sh` to `~/.kimi-code/` and makes it executable;
- merges `tui.toml` — enables `tui_mode = "fullscreen"` (mouse scroll) and wires
  `[status_line] command` — backing up any existing `tui.toml` first;
- is idempotent: re-running it is safe.

Then start a new kimi session (or `/reload-tui`).

**Quota data requires `kimi /login`** — without credentials the line still renders,
just without the quota segment.

## How the quota part works

- `~/.kimi-code/statusline.sh` reads the TUI's JSON snapshot on stdin and prints one line.
- Quota comes from `https://api.kimi.ai/coding/v1/usages` (the same endpoint as `/usage`),
  fetched by a background process into `~/.kimi-code/.cache/` (60s cache), so the
  fast path stays under kimi's 300ms status-line timeout.
- Consumption samples accumulate for 7 days; projections average over that week,
  so idle days and heavy days both count.
- Works in both regions (`mainland-cn` / `global`) and refreshes the OAuth token itself.

## Files

| File           | Purpose                                             |
| -------------- | --------------------------------------------------- |
| `statusline.sh`| the status line command (also usable standalone)    |
| `tui.toml`     | reference config the installer falls back to        |
| `install.sh`   | one-line installer                                  |

## tmux note

Inside tmux: `set -g mouse on`, and select with **Shift+drag** to copy via `pbcopy`.
On iTerm2 enable Settings → General → Selection →
"Applications in terminal may access clipboard" so in-app copy (OSC52) reaches the system clipboard.
