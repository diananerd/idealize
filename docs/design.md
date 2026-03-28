# Idealize — Design Document

## Overview

Idealize is a terminal IDE companion for AI coding agents. It creates a Ghostty window with a file tree and code viewer that react in real time to agent file operations. Everything is event-driven: no background daemons besides a lightweight viewer loop.

**CLI name:** `idealyze`

## Stack

| Component | Role | Why |
|-----------|------|-----|
| Ghostty 1.3+ | Terminal emulator, layout via AppleScript | Native GPU-rendered splits, programmatic control |
| broot | File tree sidebar | Socket IPC (`--listen`/`--send`), native tree view |
| bat | Code viewer with syntax highlighting | `--highlight-line`, `--wrap=auto`, zero overhead |
| glow | Rendered markdown preview (optional) | Terminal-rendered markdown with custom style |
| jq | JSON processing | Session state, hook JSON parsing |

## CLI Interface

```
idealyze                       Launch IDE layout (tree + viewer)
idealyze --with-agent          Launch with agent pane (default: claude)
idealyze --with-agent CMD      Launch with custom agent command
idealyze --global              Capture events from all projects
idealyze toggle tree           Show/hide file tree sidebar
idealyze toggle agent          Add/remove agent pane
idealyze toggle render         Switch between raw (bat) and rendered (glow) viewer
idealyze doctor                Diagnose and fix dependencies
idealyze stop                  Close session and Ghostty window
idealyze uninstall             Remove hooks, libs, binary
idealyze --hook post-tool-use  Internal: called by agent hooks
```

## Layout

### Default (2-pane)

```
┌──────────┬─────────────────────────────────────┐
│          │                                     │
│  tree    │         code viewer                 │
│  (broot) │         (bat / glow)                │
│          │                                     │
└──────────┴─────────────────────────────────────┘
```

### With agent (3-pane)

```
┌──────────┬──────────────────┬──────────────────┐
│          │                  │                  │
│  tree    │   code viewer    │   agent          │
│  (broot) │   (bat / glow)   │   (claude, etc)  │
│          │                  │                  │
└──────────┴──────────────────┴──────────────────┘
```

### Split strategy

Panes are created right-to-left using `split direction left`:
1. Window opens with one pane (viewer in 2-pane, agent in 3-pane)
2. Split left from viewer/agent to create tree
3. Shrink tree with `resize_split:left` on tree pane

This order is required because Ghostty's `resize_split:left` only works on panes created via `split left`.

## Session State

`~/.idealyze/session.json` (built with jq to prevent injection):

```json
{
    "version": "0.2.0",
    "pid": 12345,
    "project_dir": "/path/to/project",
    "scope": "project",
    "agent_cmd": "claude",
    "broot_socket": "idealyze",
    "viewer_mode": "raw",
    "tree_visible": true,
    "panes": {
        "window": "<ghostty-window-id>",
        "tree": "<ghostty-terminal-id>",
        "viewer": "<ghostty-terminal-id>",
        "agent": "<ghostty-terminal-id>"
    }
}
```

### Auxiliary files

| File | Purpose | Written by |
|------|---------|------------|
| `~/.idealyze/viewer-cmd` | Render command for viewer-loop | hooks.sh, toggle.sh |
| `~/.idealyze/viewer-cmd.tmp` | Atomic write staging | hooks.sh, toggle.sh |
| `~/.idealyze/current-file` | Current file + line (2 lines) | hooks.sh |
| `~/.idealyze/viewer-loop.pid` | Viewer-loop PID for WINCH | viewer-loop.sh |
| `~/.idealyze/debug.log` | Debug log (when IDEALYZE_DEBUG=1) | all scripts |
| `~/.idealyze/.install-meta` | Install mode/location metadata | install.sh |

## Hook System

### Flow

```
Agent tool use → PostToolUse hook → hooks.sh
    ├── Read file path + offset/limit → viewer.sh → viewer-cmd
    ├── Edit file path + new_string → viewer.sh → viewer-cmd (with line highlight)
    ├── Write file path → viewer.sh → viewer-cmd
    ├── Grep path → tree.sh focus
    └── Glob path → tree.sh focus

    All Read/Edit/Write also → tree.sh select (background)
```

### Project scope filtering

By default, hooks only react to files within `project_dir` from session.json. Events from other projects are silently skipped. Use `--global` to capture everything.

### Viewer command construction

`viewer.sh` builds a shell command string with deferred `$(tput lines/cols)` that evaluates at render time in the viewer pane:

- **With line number:** Centers a terminal-height window on the target line, highlights it with boosted bat color (sed replaces `48;2;51;51;51` → `48;2;40;40;160`)
- **Multi-line edits:** Uses `--highlight-line START:END` for block highlights
- **Without line number:** Shows full file with `--wrap=auto`
- **Glow mode:** Uses custom style from `config/glow-style.json`, width via deferred `$(tput cols)`

### Viewer loop

`viewer-loop.sh` runs persistently in the viewer pane:

1. On startup: waits for pane dimensions to stabilize (polls `tput cols`), then renders initial file (README or first file in root)
2. Polls `~/.idealyze/viewer-cmd` every 0.3s via atomic `mv` (read-and-clear)
3. Traps SIGWINCH to re-render on terminal resize
4. Validates commands match `clear && (bat|glow|BAT_HIGHLIGHT_COLOR|H=)` before eval

### Tree updates

`tree.sh` sends broot commands via `--send` socket IPC:
- `select`: `:escape;filename` (filters and highlights with arrow)
- `focus`: `:focus /path/to/dir` (navigates to directory)

## Toggle Operations

| Toggle | Hide | Restore |
|--------|------|---------|
| tree | `close_surface` on tree pane | Split left from viewer, resize, relaunch broot |
| agent | `close_surface` on agent pane | Split right from viewer, launch agent_cmd |
| render | Set viewer_mode to "raw" in session | Set to "glow" if installed, write new cmd to viewer-cmd |

All tree/agent toggles send WINCH to viewer-loop (via PID file) after 0.5s delay to trigger re-render at new pane size.

## Install System

### Channels

- `latest` tag → stable, default install
- `beta` tag → pre-release testing
- `v0.x.x` tags → immutable version markers

### Cloudflare Worker

`idealize.diananerd.com` proxies to GitHub raw:
- `/install.sh` → `raw.githubusercontent.com/diananerd/idealize/latest/install.sh`
- `/install.sh?channel=beta` → `...beta/install.sh`
- `/` → redirect to GitHub repo

### Installer features

- Interactive with colored output, smart defaults
- `--auto` flag for non-interactive (installs everything including optionals)
- `--user` (default) or `--project` install modes
- Auto-installs missing deps via brew (with confirmation)
- Configures Claude Code PostToolUse hooks
- Stores install metadata for clean uninstall

## Dependencies

### Required

- macOS (AppleScript)
- Ghostty 1.3+ (split API, `perform action`, terminal IDs)
- broot (socket IPC for tree)
- bat (syntax highlighting, line ranges, highlight)
- jq (JSON processing)

### Optional

- glow (rendered markdown preview)

All except Ghostty can be auto-installed via `idealyze doctor` or the installer.
