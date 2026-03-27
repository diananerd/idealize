# Idealize

Watch Claude Code work in real time — file tree, code viewer, and Claude side by side in Ghostty. A lightweight, event-driven IDE experience.

```
┌──────────┬────────────────────────┬──────────────┐
│          │                        │              │
│  tree    │    code viewer         │  claude code │
│  (broot) │    (bat / glow)        │              │
│          │                        │              │
└──────────┴────────────────────────┴──────────────┘
```

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | sh
```

The installer downloads Idealize to `~/.local/bin/`, configures a `PostToolUse` hook in `~/.claude/settings.json`, and checks your dependencies. If `~/.local/bin` isn't in your PATH, it will tell you how to add it.

Then, from any project directory:

```bash
idealyze
```

This opens a 3-pane Ghostty window with broot on the left, a code viewer in the center, and Claude Code on the right. As Claude reads, edits, and navigates files, the tree and viewer update instantly.

## What you get

- **Live file tracking** — every Read, Edit, Write, Glob, and Grep updates the tree and viewer
- **Line highlighting** — the viewer jumps to the exact line Claude is working on
- **Markdown preview** — toggle between syntax-highlighted code (bat) and rendered markdown (glow)
- **Collapsible tree** — hide the sidebar when you need more space
- **Zero overhead when idle** — hooks exit in <1ms if no Idealize session is running

## Commands

| Command | What it does |
|---|---|
| `idealyze` | Launch the IDE layout in the current directory |
| `idealyze toggle tree` | Collapse or restore the file tree sidebar |
| `idealyze toggle preview` | Switch the viewer between bat and glow |
| `idealyze stop` | Close the session and clean up |
| `idealyze uninstall` | Remove Idealize, its hooks, and all files |

## How it works

Idealize is event-driven. No background daemons besides a lightweight viewer loop.

1. `idealyze` creates a Ghostty window with 3 panes via AppleScript
2. Claude Code runs in the right pane; a viewer loop watches for render commands in the center pane
3. When Claude uses a file tool, the `PostToolUse` hook fires
4. The hook updates broot via socket IPC and writes a render command to `~/.idealyze/viewer-cmd`
5. The viewer loop picks up the command and re-renders bat/glow, including on terminal resize

## Requirements

- macOS (uses AppleScript)
- [Ghostty](https://ghostty.org) 1.3+
- [broot](https://dystroy.org/broot/)
- [bat](https://github.com/sharkdp/bat)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [jq](https://jqlang.github.io/jq/)
- [glow](https://github.com/charmbracelet/glow) (optional, for markdown preview)

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

MIT
