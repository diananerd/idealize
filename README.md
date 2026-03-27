# idealize

A terminal IDE that syncs with Claude Code in real time. Watch Claude navigate, read, and edit files — like watching a coworker in an IDE.

```
┌──────────┬────────────────────────┬──────────────┐
│          │                        │              │
│  tree    │    code viewer         │  claude code │
│  (broot) │    (bat / glow)        │              │
│          │                        │              │
└──────────┴────────────────────────┴──────────────┘
```

## How it works

Claude Code's hook system emits events when it reads, edits, or navigates files. Idealize catches these events and updates the file tree and code viewer in real time — no polling, no daemons.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | sh
```

### Requirements

- macOS (Ghostty uses AppleScript)
- [Ghostty](https://ghostty.org) 1.3+
- [broot](https://dystroy.org/broot/)
- [bat](https://github.com/sharkdp/bat)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [jq](https://jqlang.github.io/jq/)
- [glow](https://github.com/charmbracelet/glow) (optional, for markdown preview)

## Usage

```bash
# Launch in current project
idealyze

# Toggle file tree sidebar
idealyze toggle tree

# Switch code viewer between bat and glow (markdown preview)
idealyze toggle preview

# Close session
idealyze stop

# Remove everything
idealyze uninstall
```

## Architecture

Idealize is event-driven and stateless:

1. You run `idealyze` — it creates a Ghostty window with 3 panes via AppleScript
2. Claude Code runs in the right pane
3. When Claude uses Read/Edit/Write/Glob, a PostToolUse hook fires
4. The hook sends the file path to broot (socket IPC) and re-renders bat in the viewer pane
5. Each hook invocation is stateless — runs, dispatches, exits

No background processes. No polling loops. No daemons.

## License

MIT
