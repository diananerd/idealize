# Idealize — Terminal IDE for Claude Code

## Overview

Idealize is an open-source terminal IDE that turns Ghostty + Claude Code into a development environment where you watch Claude work in real time — navigating files, reading code, editing — like watching a coworker in an IDE. Everything is event-driven: no background daemons besides a lightweight viewer loop that watches for render commands.

**CLI name:** `idealyze`

## Stack

| Component | Role | Why |
|-----------|------|-----|
| Ghostty 1.3+ | Terminal emulator, layout via AppleScript | Native GPU-rendered splits, programmatic control |
| broot | Filesystem tree sidebar | Socket IPC (`--listen`/`--send`), native tree view |
| bat | Code viewer with syntax highlighting | Instant invocation, `--highlight-line`, zero overhead |
| glow | Markdown preview (optional) | Terminal-rendered markdown, toggle-able |
| Claude Code | AI development assistant | Hook system provides event-driven file activity data |

## CLI Interface

```
idealyze                     # Launch IDE layout in current directory
idealyze toggle tree         # Collapse/restore broot sidebar
idealyze toggle preview      # Switch bat <-> glow in code viewer
idealyze stop                # Close session cleanly
idealyze uninstall           # Remove hooks, libs, binary
idealyze --hook post-tool-use  # Internal: called by Claude hooks (not user-facing)
```

## Layout

```
┌──────────┬────────────────────────┬──────────────┐
│          │                        │              │
│  broot   │  bat (code viewer)     │  claude code │
│  (tree)  │  ─ or ─               │  (terminal)  │
│          │  glow (preview mode)   │              │
│  ~18%    │       ~47%             │   ~35%       │
│          │                        │              │
└──────────┴────────────────────────┴──────────────┘
```

- Three columns, proportional sizing
- Sidebar (broot) is collapsible via `idealyze toggle tree`
- Center pane alternates between bat and glow via `idealyze toggle preview`
- Right pane runs Claude Code CLI

## Architecture

### Event-driven flow

```
Claude Code executes tool (Read, Edit, Write, Glob)
        │
        ▼
PostToolUse hook (async, non-blocking)
        │
        ▼
idealyze --hook post-tool-use (reads JSON from stdin)
        │
        ├─► tree.sh ──► broot --send idealyze -c ":escape;filename"
        │
        ├─► viewer.sh ──► builds bat/glow command string
        │                  writes to ~/.idealyze/viewer-cmd
        │
        └─► exit 0 (stateless hook, no daemon)

viewer-loop.sh (persistent process in viewer pane)
        │
        ├─► polls ~/.idealyze/viewer-cmd every 0.3s
        ├─► executes new commands (bat/glow) when found
        └─► re-renders on terminal resize (SIGWINCH)
```

### Key principles

1. **Stateless hooks** — each invocation reads stdin, dispatches commands, exits. The only resident process is `viewer-loop.sh` in the viewer pane.
2. **Session guard** — hooks check for `~/.idealyze/session.json`. If absent, exit 0 immediately (<1ms overhead when not using idealyze).
3. **Async execution** — hooks run with `async: true` so Claude is never blocked by UI updates.
4. **Direct IPC** — broot via socket, viewer via command file (`~/.idealyze/viewer-cmd`), Ghostty via AppleScript.

### Session state

Minimal file at `~/.idealyze/session.json`:

```json
{
  "version": "0.1.0",
  "pid": 12345,
  "project_dir": "/path/to/project",
  "broot_socket": "idealyze",
  "viewer_mode": "bat",
  "tree_visible": true,
  "current_file": null,
  "current_line": 1,
  "panes": {
    "window": "<ghostty-window-id>",
    "tree": "<ghostty-terminal-id>",
    "viewer": "<ghostty-terminal-id>",
    "claude": "<ghostty-terminal-id>"
  }
}
```

Created by `idealyze`, read by hooks and `toggle`, deleted by `idealyze stop` or on Ghostty close.

## Launch sequence (`idealyze`)

1. Validate dependencies (ghostty, broot, bat, claude). Warn if glow missing (optional).
2. Create `~/.idealyze/session.json` with project directory.
3. AppleScript: create Ghostty window at `$PWD`.
4. AppleScript: split right → Claude pane (~35%).
5. AppleScript: in left pane, split right → code viewer pane (middle).
6. Original left pane → sidebar: run `broot --listen idealyze $PWD`.
7. Middle pane → run `viewer-loop.sh` (shows README or first file, then polls for commands).
8. Right pane → run `claude` (Claude Code CLI).
9. Store pane references (window, tree, viewer, claude IDs) in session.json.

## Claude Code integration

### Hook configuration

Injected into `~/.claude/settings.json` (user-level, works across all projects):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Read|Edit|Write|Glob|Grep",
        "hooks": [
          {
            "type": "command",
            "command": "idealyze --hook post-tool-use",
            "async": true
          }
        ]
      }
    ]
  }
}
```

### Hook data extraction

The `PostToolUse` hook receives JSON on stdin with:

- `tool_name` — which tool fired (Read, Edit, Write, Glob, Grep)
- `tool_input.file_path` — the file Claude interacted with
- `tool_input.offset` / `tool_input.limit` — line range for Read
- `tool_input.old_string` / `tool_input.new_string` — for Edit (enables highlight)
- `tool_input.pattern` — for Glob/Grep (extract directory context)
- `tool_input.path` — for Grep (search directory or file)

The hook handler parses this and dispatches:

| Tool | Tree action | Viewer action |
|------|-------------|---------------|
| Read | `:escape;<filename>` | `bat --highlight-line <offset> <file_path>` |
| Edit | `:escape;<filename>` | `bat --highlight-line <edit_line> <file_path>` |
| Write | `:escape;<filename>` | `bat <file_path>` |
| Glob | `:focus <directory>` | (no viewer change) |
| Grep | `:focus <path>` or `:escape;<filename>` | (no viewer change) |

### Viewer behavior

- **bat mode (default):** Re-invokes bat with the target file and `--highlight-line` for the active line. Bat is instant so re-invocation has no perceptible lag.
- **glow mode:** If `viewer_mode` is `glow` AND the file is `.md`, uses glow. Otherwise falls back to bat. Toggle only changes the preference, not forces glow on non-markdown.
- **Scroll position:** For Read with offset, bat's `--line-range <start>:` shows from that line forward.

### Tree behavior

- broot runs with `--listen idealyze` at launch.
- On file events (Read/Edit/Write): `broot --send idealyze -c ":escape;<filename>"` searches and highlights the file.
- On Glob events: `broot --send idealyze -c ":focus <directory>"` expands and navigates to the directory.
- On Grep events: `:focus <path>` if directory, `:escape;<filename>` if file.

## Toggle mechanics

### `idealyze toggle tree`

1. Read session.json → get viewer pane ref and `tree_visible` state.
2. If visible: AppleScript shrinks the tree pane via `resize_split:left,20` repeated 30 times on the viewer terminal. Set `tree_visible: false`.
3. If hidden: AppleScript restores the tree pane via `resize_split:right,20` repeated 15 times on the viewer terminal. Set `tree_visible: true`.

### `idealyze toggle preview`

1. Read session.json → get `viewer_mode`.
2. Toggle `viewer_mode` between `bat` and `glow`.
3. If there's a current file in view, re-render with the new mode immediately.
4. Future hook invocations respect the new mode.

## Installation

### curl | sh installer

```bash
curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | sh
```

The installer:

1. Downloads release archive (or clones repo for dev).
2. Installs `idealyze` binary to `~/.local/bin/` (or first writable dir in PATH).
3. Installs lib scripts to `~/.idealyze/lib/`.
4. Installs broot sidebar config to `~/.idealyze/config/broot.toml`.
5. Merges hooks into `~/.claude/settings.json`:
   - Reads existing file (or creates it).
   - Adds PostToolUse hook entry without overwriting existing hooks.
   - If idealize hooks already present, skips.
6. Checks dependencies and reports status:
   ```
   ✓ ghostty 1.3.2
   ✓ broot 1.44.0
   ✓ bat 0.24.0
   ✓ claude 2.1.90
   ○ glow (optional, not found — preview mode will use bat)
   ```
7. Prints: `Run 'idealyze' in any project directory to start.`

### Uninstall

`idealyze uninstall`:

1. Removes idealize hooks from `~/.claude/settings.json`.
2. Removes `~/.idealyze/` directory.
3. Removes `idealyze` binary from PATH.
4. Prints confirmation.

## Project structure

```
idealize/
├── bin/
│   └── idealyze               # Main CLI entry point (bash)
├── lib/
│   ├── layout.applescript      # Ghostty layout creation
│   ├── hooks.sh                # PostToolUse handler (stdin JSON → dispatch)
│   ├── viewer.sh               # bat/glow command builder
│   ├── viewer-loop.sh          # Persistent viewer process (polls viewer-cmd, handles resize)
│   ├── tree.sh                 # broot --send commands
│   └── toggle.sh               # Toggle tree/preview
├── config/
│   ├── broot-sidebar.toml      # Minimal broot config for sidebar mode
│   └── claude-hooks.json       # Hook template for Claude settings
├── docs/
│   ├── design.md               # Architecture and design documentation
│   └── plan.md                 # Implementation plan
├── install.sh                  # curl | sh installer
├── README.md
├── LICENSE                     # MIT
└── .github/
    └── workflows/
        └── release.yml         # GitHub releases for versioned installs
```

## Constraints and limitations

- **macOS only** — Ghostty AppleScript is macOS-exclusive. Linux support would require a different IPC mechanism (future work).
- **Ghostty 1.3+** — AppleScript support was introduced in 1.3.0.
- **No session persistence** — closing Ghostty loses the layout. Re-run `idealyze` to restore.
- **Single session** — one idealyze session at a time (session.json is singular). Multiple sessions would require session IDs (future work).

## Optional / nice-to-have (drop if too complex)

- **Highlight changes (C-level):** After Edit, temporarily highlight the changed lines in bat using ANSI escape codes or bat's `--diff` mode. Falls back to B-level (scroll to line only) if complex.
- **Diff panel (bottom):** A fourth pane below the viewer for `git diff` output. Only added if highlight changes proves insufficient.
- **Interactive tree:** broot is already interactive by nature. If the user navigates broot manually, optionally update the viewer to show the selected file. No extra logic needed beyond broot's built-in behavior.
- **Tree toggle from Claude:** Claude could run `idealyze toggle tree` via Bash to collapse the sidebar when doing broad operations (Glob across many dirs).
