# Idealize: IDE-alize your Claude Code

Watch Claude Code work in real time — file tree and code viewer side by side in Ghostty. A lightweight, event-driven IDE companion.

```
┌──────────┬─────────────────────────────────────┐
│          │                                     │
│  tree    │         code viewer                 │
│  (broot) │         (bat / glow)                │
│          │                                     │
└──────────┴─────────────────────────────────────┘
```

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh)
```

The installer downloads Idealize to `~/.local/bin/`, configures a `PostToolUse` hook in `~/.claude/settings.json`, and checks your dependencies.

Then, from any project directory:

```bash
idealyze
```

This opens a 2-pane Ghostty window: broot file tree on the left and a code viewer on the right. As Claude reads, edits, and navigates files in any terminal, the tree and viewer update instantly.

## What You Get

- **Live file tracking** — every Read, Edit, Write, Glob, and Grep updates the tree and viewer
- **Line highlighting** — the viewer jumps to the exact line Claude is working on, with multi-line block highlights for edits
- **Project scoping** — only reacts to files in the current project (use `--global` to track everything)
- **Markdown preview** — toggle between syntax-highlighted code (bat) and rendered markdown (glow)
- **Collapsible tree** — hide the sidebar when you need more space
- **Optional Claude pane** — add an embedded Claude terminal on demand
- **Resize-aware** — viewer re-renders automatically when you resize panes
- **Zero overhead when idle** — hooks exit immediately if no Idealize session is running

## Commands

| Command | What it does |
|---|---|
| `idealyze` | Launch IDE layout (tree + viewer) |
| `idealyze --with-claude` | Launch with an embedded Claude pane |
| `idealyze --global` | Track files outside the project too |
| `idealyze toggle tree` | Collapse or restore the file tree sidebar |
| `idealyze toggle claude` | Add or remove the Claude pane |
| `idealyze toggle render` | Switch viewer between raw and rendered mode |
| `idealyze stop` | Close the session and Ghostty window |
| `idealyze uninstall` | Remove Idealize, its hooks, and all files |

Set `IDEALYZE_DEBUG=1` before launching to enable verbose logging to `~/.idealyze/debug.log`.

## How It Works

Idealize is event-driven. No background daemons besides a lightweight viewer loop.

1. `idealyze` creates a Ghostty window with panes via AppleScript
2. A viewer loop watches for render commands in the viewer pane
3. When Claude uses a file tool (in any terminal), the `PostToolUse` hook fires
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

## Install channels

The default install always pulls from the `latest` tag (stable):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/latest/install.sh)
```

To try pre-release features:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/beta/install.sh) --beta
```

## Contributing

Idealize is maintained by [@diananerd](https://github.com/diananerd). Contributions welcome:

1. Fork the repo and create a feature branch
2. Make your changes and test with `idealyze doctor`
3. Open a PR against `main` — describe what and why

Please keep PRs focused (one feature or fix per PR). For larger changes, open an issue first to discuss the approach.

## Documentation

- [Design](docs/design.md) — architecture, pane layout, and IPC model

## License

MIT
