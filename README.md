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

When your AI agent reads a file, the viewer shows it with syntax highlighting. When it edits a line, the viewer scrolls to the exact line and highlights the change. The file tree tracks which file is active. All of this happens automatically — you just watch.

## Quick Start

```bash
curl -fsSL https://idealize.diananerd.com/install | bash
```

The installer walks you through everything: checks your system, installs missing dependencies via brew, downloads Idealize, configures agent hooks, and sets up Ghostty. Add `--auto` to skip prompts and install everything.

Then, from any project directory:

```bash
idealyze
```

That's it. A Ghostty window opens with your file tree on the left and a code viewer on the right. Start using your AI agent in any terminal — the viewer reacts to every file operation.

## What You See

- **File tree** (left) — powered by [broot](https://dystroy.org/broot/). Highlights the active file as your agent navigates the codebase.
- **Code viewer** (center) — powered by [bat](https://github.com/sharkdp/bat). Shows the file being read or edited, with syntax highlighting and line-level focus. Supports rendered markdown via [glow](https://github.com/charmbracelet/glow).
- **Agent pane** (optional, right) — an embedded terminal running your agent. Toggle it on with `idealyze toggle agent` or launch with `idealyze --with-agent`.

## What It Tracks

Every time your agent uses a file tool (Read, Edit, Write, Grep, Glob), Idealize reacts:

| Agent action | What Idealize does |
|---|---|
| Read a file | Viewer shows the file, scrolls to the read offset |
| Edit a file | Viewer highlights the edited line(s) with a colored block |
| Write a file | Viewer shows the new file from the top |
| Grep/Glob | File tree navigates to the searched directory |

All of this is scoped to your current project by default — activity from other terminals working on other projects is ignored.

## Commands

| Command | What it does |
|---|---|
| `idealyze` | Launch IDE layout (tree + viewer) |
| `idealyze --with-agent` | Launch with agent pane (default: claude) |
| `idealyze --with-agent CMD` | Launch with custom agent command |
| `idealyze --global` | Track files from all projects, not just current |
| `idealyze toggle tree` | Show or hide the file tree sidebar |
| `idealyze toggle agent` | Add or remove the agent pane |
| `idealyze toggle render` | Switch viewer between raw (bat) and rendered (glow) |
| `idealyze doctor` | Check dependencies, hooks, config, and updates |
| `idealyze update` | Update to latest version |
| `idealyze stop` | Close the Idealize window and clean up |
| `idealyze uninstall` | Remove Idealize completely (hooks, config, files) |

## Configuration

Idealize reads config from JSON files with 3-level priority:

1. **Project** `.idealyze/config.json` — overrides for this project only
2. **User** `~/.idealyze/config.json` — your personal defaults
3. **Built-in** `lib/config-defaults.json` — shipped defaults

Only specify keys you want to change. Example `~/.idealyze/config.json`:

```json
{
  "agent_cmd": "aider",
  "viewer": {
    "highlight_color": "80;0;80"
  },
  "layout": {
    "tree_shrink_2pane": 20
  }
}
```

All available keys are in [`lib/config-defaults.json`](lib/config-defaults.json).

## Environment Variables

| Variable | Description |
|---|---|
| `IDEALYZE_DEBUG=1` | Enable detailed logging to `~/.idealyze/debug.log` |
| `IDEALYZE_AGENT_CMD=<cmd>` | Override agent command for this session |

## Troubleshooting

Run `idealyze doctor` — it checks everything and offers to fix what it can.

For deeper issues, enable debug mode:

```bash
IDEALYZE_DEBUG=1 idealyze
```

Then reproduce the problem and share `~/.idealyze/debug.log`.

## How It Works

Idealize is event-driven. No background daemons besides a lightweight viewer loop.

1. `idealyze` creates a Ghostty window with panes via AppleScript
2. A viewer loop runs in the viewer pane, watching for render commands
3. When your agent uses a file tool, the `PostToolUse` hook fires
4. The hook writes a render command to `~/.idealyze/viewer-cmd` and updates broot via socket
5. The viewer loop picks it up and re-renders, including on terminal resize (SIGWINCH)

The hook system is provider-based. Currently ships with a [Claude Code](https://docs.anthropic.com/en/docs/claude-code) provider. Adding support for other agents means creating a new file in `lib/providers/` — see [Design](docs/design.md) for the interface.

## Requirements

| Dependency | Required | Install |
|---|---|---|
| macOS | Yes | Uses AppleScript for Ghostty control |
| [Ghostty](https://ghostty.org) 1.3+ | Yes | Download from ghostty.org |
| [broot](https://dystroy.org/broot/) | Yes | `brew install broot` |
| [bat](https://github.com/sharkdp/bat) | Yes | `brew install bat` |
| [jq](https://jqlang.github.io/jq/) | Yes | `brew install jq` |
| [glow](https://github.com/charmbracelet/glow) | No | `brew install glow` (for rendered markdown) |

The installer and `idealyze doctor` can install all brew dependencies automatically.

## Install Options

**Stable (recommended):**
```bash
curl -fsSL https://idealize.diananerd.com/install | bash
```

**Beta (pre-release features):**
```bash
curl -fsSL https://idealize.diananerd.com/install?channel=beta | bash
```

**Non-interactive (CI/scripting):**
```bash
curl -fsSL https://idealize.diananerd.com/install | bash --auto
```

**Project-local install:**
```bash
curl -fsSL https://idealize.diananerd.com/install | bash --project
```

## Contributing

Idealize is maintained by [@diananerd](https://github.com/diananerd). Contributions welcome:

1. Fork the repo and create a feature branch from `dev`
2. Make your changes and test with `idealyze doctor`
3. Open a PR against `main` — describe what and why

Keep PRs focused (one feature or fix per PR). For larger changes, open an issue first to discuss the approach.

## Documentation

- [Design](docs/design.md) — architecture, IPC model, provider interface
- [Releasing](docs/releasing.md) — release channels, tagging, and workflow
- [CLAUDE.md](CLAUDE.md) — development guide for AI agents working on this codebase

## License

MIT
