# env

Personal environment configs, one directory per tool. Each directory is
self-contained: its own files and a one-line installer where applicable.

## Configs

| Directory      | Tool                                   | Install |
| -------------- | -------------------------------------- | ------- |
| `kimi-code/`   | Kimi Code CLI status line + TUI prefs  | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/env/main/kimi-code/install.sh)"` |
| `claude/`      | Claude Code statusline, hooks, settings| `bash -c "$(curl -fsSL https://raw.githubusercontent.com/darkClaw921/env/main/claude/install.sh)"` |

## Convention

- One folder per config, named after the tool.
- Installers are idempotent, back up existing files before overwriting,
  and must survive re-runs.
