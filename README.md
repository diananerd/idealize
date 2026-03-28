# Idealize

A terminal IDE companion for AI coding agents. Watch your agent work in real time — file tree and code viewer side by side in Ghostty.

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
bash <(curl -fsSL https://idealize.diananerd.com/install.sh)
```

The installer checks dependencies (installs missing ones via brew), downloads Idealize to `~/.idealyze/`, and configures hooks. Run with `--auto` to skip prompts.

Then, from any project directory:

```bash
idealyze
```

This opens a 2-pane Ghostty window: broot file tree on the left and a code viewer on the right. As your agent reads, edits, and navigates files, the tree and viewer update instantly.

## What You Get

- **Live file tracking** — every Read, Edit, Write, Glob, and Grep updates the tree and viewer
- **Line highlighting** — the viewer jumps to the exact line being worked on, with multi-line block highlights for edits
- **Project scoping** — only reacts to files in the current project (use `--global` to track everything)
- **Markdown preview** — toggle between raw code (bat) and rendered markdown (glow)
- **Collapsible tree** — hide the sidebar when you need more space
- **Optional agent pane** — add an embedded terminal for any agent (claude, aider, etc)
- **Resize-aware** — viewer re-renders automatically when you resize panes
- **Zero overhead when idle** — hooks exit immediately if no session is running

## Commands

| Command | What it does |
|---|---|
| `idealyze` | Launch IDE layout (tree + viewer) |
| `idealyze --with-agent` | Launch with agent pane (default: claude) |
| `idealyze --with-agent CMD` | Launch with custom agent command |
| `idealyze --global` | Track files outside the project too |
| `idealyze toggle tree` | Show or hide the file tree sidebar |
| `idealyze toggle agent` | Add or remove the agent pane |
| `idealyze toggle render` | Switch viewer between raw and rendered mode |
| `idealyze doctor` | Diagnose and fix dependencies |
| `idealyze stop` | Close the session and Ghostty window |
| `idealyze uninstall` | Remove Idealize, its hooks, and all files |

## Environment

| Variable | Description |
|---|---|
| `IDEALYZE_DEBUG=1` | Enable verbose logging to `~/.idealyze/debug.log` |
| `IDEALYZE_AGENT_CMD=<cmd>` | Override agent command (default: claude) |

## How It Works

Idealize is event-driven. No background daemons besides a lightweight viewer loop.

1. `idealyze` creates a Ghostty window with panes via AppleScript
2. A viewer loop watches for render commands in the viewer pane
3. When your agent uses a file tool, the `PostToolUse` hook fires
4. The hook updates broot via socket IPC and writes a render command to `~/.idealyze/viewer-cmd`
5. The viewer loop picks up the command and re-renders bat/glow, including on terminal resize

Currently ships with hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). PRs welcome for other agents.

## Requirements

- macOS (uses AppleScript)
- [Ghostty](https://ghostty.org) 1.3+
- [broot](https://dystroy.org/broot/)
- [bat](https://github.com/sharkdp/bat)
- [jq](https://jqlang.github.io/jq/)
- [glow](https://github.com/charmbracelet/glow) (optional, for rendered markdown preview)

All dependencies except Ghostty can be installed automatically by the installer or `idealyze doctor`.

## Install Channels

The default install pulls from the `latest` tag (stable):

```bash
bash <(curl -fsSL https://idealize.diananerd.com/install.sh)
```

To try pre-release features:

```bash
bash <(curl -fsSL https://idealize.diananerd.com/install.sh?channel=beta) --beta
```

## Contributing

Idealize is maintained by [@diananerd](https://github.com/diananerd). Contributions welcome:

1. Fork the repo and create a feature branch
2. Make your changes and test with `idealyze doctor`
3. Open a PR against `main` — describe what and why

Please keep PRs focused (one feature or fix per PR). For larger changes, open an issue first to discuss the approach.

## Documentation

- [Design](docs/design.md) — architecture, pane layout, and IPC model
- [Releasing](docs/releasing.md) — release channels, tagging, and workflow

## License

MIT
