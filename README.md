# CC Overlord

macOS menu bar app that shows when Claude Code finishes a task — across all VS Code windows.

Named after the StarCraft Zerg Overlord: floats above the map providing vision everywhere.

## How it works

```
Claude Code finishes responding
  → Stop hook writes signal file
  → CC Overlord detects it via file watcher
  → Menu bar shows: 4 🔔 jarvis-cont…
                     ↑       ↑
               click for   click to jump
               dropdown    directly
```

When you click a terminal in the dropdown, CC Overlord focuses the right VS Code window and switches to that terminal tab.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- [dtach-persist](https://github.com/waihonger/dtach-vscode-persist) v0.2.0+ (VS Code extension that creates the signal files)
- [Claude Code](https://claude.ai/code) with hooks configured (see below)

## Install

### 1. Build

```bash
git clone https://github.com/waihonger/cc-overlord.git
cd cc-overlord
swift build -c release
```

### 2. Run

```bash
.build/release/cc-overlord
```

To run on login, add it to System Settings → General → Login Items.

### 3. Configure Claude Code hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "test -n \"$DTACH_SIGNAL_DIR\" && test -n \"$DTACH_SOCKET_INDEX\" && touch \"$DTACH_SIGNAL_DIR/$DTACH_SOCKET_INDEX.signal\" || true", "timeout": 1000 }] }
    ],
    "PermissionRequest": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "test -n \"$DTACH_SIGNAL_DIR\" && test -n \"$DTACH_SOCKET_INDEX\" && touch \"$DTACH_SIGNAL_DIR/$DTACH_SOCKET_INDEX.permission\" || true", "timeout": 1000 }] }
    ],
    "StopFailure": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "test -n \"$DTACH_SIGNAL_DIR\" && test -n \"$DTACH_SOCKET_INDEX\" && touch \"$DTACH_SIGNAL_DIR/$DTACH_SOCKET_INDEX.error\" || true", "timeout": 1000 }] }
    ]
  }
}
```

Three signal types:
- **Stop** → `.signal` file → "done" (yellow)
- **PermissionRequest** → `.permission` file → "needs approval" (red, urgent)
- **StopFailure** → `.error` file → "error" (red, urgent)

## Menu bar UX

| State | Menu bar | Click behavior |
|---|---|---|
| No signals | 🔔 | — |
| 1 signal | 🔔 project-name | Click name → jump to terminal |
| 2+ signals | N 🔔 project-name | Click N/🔔 → dropdown, click name → jump to most recent |

- Signals auto-clear after 4 hours (configurable via `DTACH_SIGNAL_STALE_HOURS` env var)
- Signals clear when you switch to that terminal in VS Code
- Dropdown groups terminals by project with time since completion

## How it connects to dtach-persist

CC Overlord watches `$TMPDIR/dtach-persist/*/signals/` for `.signal`, `.permission`, and `.error` files. These are created by Claude Code hooks (which use env vars `DTACH_SIGNAL_DIR` and `DTACH_SOCKET_INDEX` set by dtach-persist at terminal creation).

When you click a terminal in the dropdown, CC Overlord:
1. Writes a `goto` file with the terminal index
2. Opens the project in VS Code (`open -a "Visual Studio Code" /path/to/project`)
3. dtach-persist reads the `goto` file and focuses the right terminal tab

## License

MIT
