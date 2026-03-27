# Idealize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `idealyze`, a terminal IDE that syncs Ghostty panes (file tree, code viewer) with Claude Code activity in real time via event-driven hooks.

**Architecture:** Ghostty AppleScript creates a 3-pane layout (broot tree | bat/glow viewer | claude). Claude's PostToolUse hooks dispatch file/line info to broot (socket IPC) and bat (re-invocation via AppleScript `input text`). All stateless — no daemons, no loops.

**Tech Stack:** Bash, AppleScript (osascript), broot, bat, glow, jq, Ghostty 1.3+

**Working directory:** `/Users/diananerd/Documents/personal/claude/idealize`

---

## Task 1: Project scaffolding

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `bin/.gitkeep` (directory structure)
- Create: `lib/.gitkeep`
- Create: `config/.gitkeep`

- [ ] **Step 1: Create MIT LICENSE**

```
MIT License

Copyright (c) 2026 diananerd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create .gitignore**

```
.DS_Store
*.swp
*.swo
*~
```

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p bin lib config
```

- [ ] **Step 4: Commit**

```bash
git add LICENSE .gitignore docs/ bin/ lib/ config/
git commit -m "feat: initial project scaffolding with design spec"
```

---

## Task 2: broot sidebar config

**Files:**
- Create: `config/broot-sidebar.toml`

- [ ] **Step 1: Create minimal broot config for sidebar mode**

```toml
# Idealize: minimal broot config for sidebar display
# Launched via: broot --conf config/broot-sidebar.toml --listen idealyze /path

max_panels_count = 1

# Minimal columns: just file/dir names with git markers
cols_order = [
    "mark",
    "git",
    "name",
]

# Disable search on typing (sidebar is display-only by default)
# Users can still type to search if they want
show_selection_mark = true

# Keep broot running on all navigation
[[verbs]]
invocation = "focus"
key = "enter"
internal = "focus"
apply_to = "directory"
leave_broot = false

[[verbs]]
invocation = "open"
key = "enter"
internal = "open_stay"
apply_to = "file"
leave_broot = false

# Disable dangerous verbs for safety (override with harmless command)
[[verbs]]
invocation = "rm"
execution = "/bin/true"

[[verbs]]
invocation = "mv"
execution = "/bin/true"
```

- [ ] **Step 2: Verify broot can launch with this config**

```bash
# Quick test — should open broot in sidebar mode, Ctrl-C to exit
broot --conf config/broot-sidebar.toml .
```

Expected: broot opens with minimal columns (mark, git, name), no permission/size/date columns.

- [ ] **Step 3: Commit**

```bash
git add config/broot-sidebar.toml
git commit -m "feat: add minimal broot sidebar config"
```

---

## Task 3: AppleScript layout

**Files:**
- Create: `lib/layout.applescript`

This is the core piece — creates the 3-pane Ghostty layout and outputs terminal IDs as JSON.

- [ ] **Step 1: Create layout.applescript**

The script receives the project directory and idealyze lib path as arguments, creates the layout, and prints terminal IDs to stdout as JSON.

```applescript
-- lib/layout.applescript
-- Usage: osascript lib/layout.applescript <project_dir> <idealyze_lib_dir> <broot_conf_path>
-- Outputs: JSON with terminal IDs for session.json

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv

    tell application "Ghostty"
        activate

        -- Create surface config with project working directory
        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        -- Create main window (this becomes the tree pane)
        set win to new window with configuration cfg

        -- Get reference to the first terminal (will be tree pane)
        set treeTerminal to terminal 1 of selected tab of win

        -- Split right to create the combined center+right area
        set rightArea to split treeTerminal direction right with configuration cfg

        -- rightArea is now the right pane, treeTerminal is the left pane
        -- Split rightArea to create viewer (left of right) and claude (right of right)
        set claudeTerminal to split rightArea direction right with configuration cfg

        -- Now: treeTerminal | rightArea (viewer) | claudeTerminal
        set viewerTerminal to rightArea

        -- Get IDs for session tracking
        set treeId to id of treeTerminal
        set viewerId to id of viewerTerminal
        set claudeId to id of claudeTerminal
        set winId to id of win

        -- Resize: make tree narrow (~18%) using perform action
        -- Note: resize_split amount is in pixels. Repeat to achieve desired proportion.
        -- Shrink tree pane by moving the divider left (in pixel increments)
        repeat 15 times
            perform action "resize_split:left,20" on viewerTerminal
        end repeat

        -- Grow claude pane slightly
        repeat 3 times
            perform action "resize_split:right,20" on claudeTerminal
        end repeat

        -- Launch broot in tree pane (no --force needed; broot auto-cleans stale sockets)
        input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal

        -- Launch bat welcome in viewer pane
        input text "clear && echo 'idealize: waiting for claude activity...'\n" to viewerTerminal

        -- Launch claude in claude pane
        input text "claude\n" to claudeTerminal

        -- Output JSON with terminal IDs (id may be integer, coerce to string)
        return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"claude_id\":\"" & (claudeId as text) & "\"}"
    end tell
end run
```

- [ ] **Step 2: Test the AppleScript manually**

```bash
osascript lib/layout.applescript "$(pwd)" "$(pwd)/lib" "$(pwd)/config/broot-sidebar.toml"
```

Expected: Ghostty opens with 3 panes — broot on left, welcome message in center, claude on right. Script outputs JSON with terminal IDs.

- [ ] **Step 3: Commit**

```bash
git add lib/layout.applescript
git commit -m "feat: add Ghostty AppleScript layout creator"
```

---

## Task 4: Tree controller

**Files:**
- Create: `lib/tree.sh`

- [ ] **Step 1: Create tree.sh**

Receives a file path or directory, sends the appropriate command to broot via socket.

```bash
#!/usr/bin/env bash
# lib/tree.sh — Send navigation commands to broot sidebar
# Usage: tree.sh select <file_path>
#        tree.sh focus <directory_path>

set -euo pipefail

SOCKET_NAME="idealyze"
ACTION="${1:-}"
TARGET="${2:-}"

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    exit 0
fi

# Check if broot socket exists
if [[ ! -S "/tmp/broot-server-${SOCKET_NAME}.sock" ]]; then
    exit 0
fi

case "$ACTION" in
    select)
        # Navigate to the file's parent directory, then select the file
        # Uses -c flag (required for sending commands) and ; to chain commands
        parent_dir=$(dirname "$TARGET")
        filename=$(basename "$TARGET")
        broot --send "$SOCKET_NAME" -c ":focus ${parent_dir};:select ${filename}" 2>/dev/null || true
        ;;
    focus)
        broot --send "$SOCKET_NAME" -c ":focus ${TARGET}" 2>/dev/null || true
        ;;
    *)
        exit 0
        ;;
esac
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x lib/tree.sh
# With broot running via --listen idealyze:
./lib/tree.sh select "$(pwd)/lib/layout.applescript"
```

Expected: broot navigates to `lib/` and highlights `layout.applescript`.

- [ ] **Step 3: Commit**

```bash
git add lib/tree.sh
git commit -m "feat: add broot tree controller"
```

---

## Task 5: Viewer controller

**Files:**
- Create: `lib/viewer.sh`

- [ ] **Step 1: Create viewer.sh**

Builds the bat/glow command string to display a file. Outputs the command to stdout — the caller (hooks.sh) sends it to the viewer pane via AppleScript.

```bash
#!/usr/bin/env bash
# lib/viewer.sh — Build viewer command for bat or glow
# Usage: viewer.sh <file_path> [line_number] [viewer_mode]
# Outputs: the shell command to run in the viewer pane

set -euo pipefail

FILE_PATH="${1:-}"
LINE_NUMBER="${2:-}"
VIEWER_MODE="${3:-bat}"

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

FILE_EXT="${FILE_PATH##*.}"

# Use glow for markdown when in preview mode
if [[ "$VIEWER_MODE" == "glow" && "$FILE_EXT" == "md" ]] && command -v glow &>/dev/null; then
    echo "clear && glow -w \$(tput cols) \"${FILE_PATH}\""
    exit 0
fi

# Default: bat with syntax highlighting
BAT_CMD="clear && bat --paging=never --style=numbers,header,grid --color=always"

if [[ -n "$LINE_NUMBER" && "$LINE_NUMBER" != "0" ]]; then
    # Show context around the target line
    BAT_CMD="${BAT_CMD} --highlight-line ${LINE_NUMBER}"

    # Calculate a window around the line
    start=$((LINE_NUMBER > 10 ? LINE_NUMBER - 10 : 1))
    BAT_CMD="${BAT_CMD} --line-range ${start}:"
fi

BAT_CMD="${BAT_CMD} \"${FILE_PATH}\""
echo "$BAT_CMD"
```

- [ ] **Step 2: Test viewer command generation**

```bash
chmod +x lib/viewer.sh
./lib/viewer.sh "$(pwd)/docs/design.md" 50 bat
# Expected: clear && bat --paging=never --style=numbers,header,grid --color=always --highlight-line 50 --line-range 40: "/.../docs/design.md"

./lib/viewer.sh "$(pwd)/docs/design.md" "" glow
# Expected: clear && glow -w $(tput cols) "/.../docs/design.md"
```

- [ ] **Step 3: Commit**

```bash
git add lib/viewer.sh
git commit -m "feat: add viewer controller for bat/glow"
```

---

## Task 6: Hook handler

**Files:**
- Create: `lib/hooks.sh`

This is the central dispatcher — receives PostToolUse JSON from Claude, extracts file/line info, calls tree.sh and viewer.sh, and sends the viewer command to Ghostty via AppleScript.

- [ ] **Step 1: Create hooks.sh**

```bash
#!/usr/bin/env bash
# lib/hooks.sh — Claude PostToolUse hook handler
# Called by Claude with JSON on stdin. Dispatches to tree and viewer.

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

# Session guard: exit immediately if no active session
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Read session state
VIEWER_MODE=$(jq -r '.viewer_mode // "bat"' "$SESSION_FILE")
VIEWER_ID=$(jq -r '.panes.viewer // empty' "$SESSION_FILE")

if [[ -z "$VIEWER_ID" ]]; then
    exit 0
fi

# Read hook JSON from stdin
HOOK_JSON=$(cat)

TOOL_NAME=$(echo "$HOOK_JSON" | jq -r '.tool_name // empty')
if [[ -z "$TOOL_NAME" ]]; then
    exit 0
fi

# Extract file path based on tool type
FILE_PATH=""
LINE_NUMBER=""

case "$TOOL_NAME" in
    Read)
        FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        LINE_NUMBER=$(echo "$HOOK_JSON" | jq -r '.tool_input.offset // "1"')
        ;;
    Edit)
        FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        # Find the line number of old_string in the file for precise highlighting
        OLD_STRING=$(echo "$HOOK_JSON" | jq -r '.tool_input.old_string // empty')
        if [[ -n "$OLD_STRING" && -n "$FILE_PATH" && -f "$FILE_PATH" ]]; then
            # Get the first line of old_string to search for in the file
            FIRST_LINE=$(printf '%s' "$OLD_STRING" | head -1)
            LINE_NUMBER=$(grep -nF "$FIRST_LINE" "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
        fi
        LINE_NUMBER="${LINE_NUMBER:-1}"
        ;;
    Write)
        FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        LINE_NUMBER="1"
        ;;
    Grep)
        # Grep: navigate tree to the search path if specified
        GREP_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.path // empty')
        if [[ -n "$GREP_PATH" ]]; then
            if [[ -d "$GREP_PATH" ]]; then
                "$LIB_DIR/tree.sh" focus "$GREP_PATH" &
            elif [[ -f "$GREP_PATH" ]]; then
                "$LIB_DIR/tree.sh" select "$GREP_PATH" &
            fi
        fi
        exit 0
        ;;
    Glob)
        # Glob: update tree to the search directory, no viewer change
        GLOB_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.path // empty')
        if [[ -n "$GLOB_PATH" && -d "$GLOB_PATH" ]]; then
            "$LIB_DIR/tree.sh" focus "$GLOB_PATH" &
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Update tree sidebar (background, non-blocking)
"$LIB_DIR/tree.sh" select "$FILE_PATH" &

# Build viewer command
VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$FILE_PATH" "$LINE_NUMBER" "$VIEWER_MODE")

if [[ -n "$VIEWER_CMD" ]]; then
    # Send command to viewer pane via Ghostty AppleScript
    # Note: VIEWER_ID may be integer — use 'as integer' for safe comparison
    # Escape double quotes in VIEWER_CMD to avoid breaking AppleScript string
    ESCAPED_CMD=$(printf '%s' "$VIEWER_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "
        tell application \"Ghostty\"
            set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
            input text \"${ESCAPED_CMD}\n\" to viewerTerm
        end tell
    " 2>/dev/null || true
fi

# Store current file for toggle preview
jq --arg f "$FILE_PATH" --arg l "${LINE_NUMBER:-1}" \
    '.current_file = $f | .current_line = ($l | tonumber)' \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

wait
```

- [ ] **Step 2: Make executable**

```bash
chmod +x lib/hooks.sh
```

- [ ] **Step 3: Test with mock JSON**

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"'$(pwd)'/docs/design.md","offset":50}}' | ./lib/hooks.sh
```

Expected: With an active session, broot navigates to docs/design.md and bat renders it with line 50 highlighted in the viewer pane.

- [ ] **Step 4: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat: add PostToolUse hook handler dispatcher"
```

---

## Task 7: Toggle controller

**Files:**
- Create: `lib/toggle.sh`

- [ ] **Step 1: Create toggle.sh**

```bash
#!/usr/bin/env bash
# lib/toggle.sh — Toggle tree sidebar or preview mode
# Usage: toggle.sh tree | toggle.sh preview

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "idealize: no active session" >&2
    exit 1
fi

ACTION="${1:-}"

case "$ACTION" in
    tree)
        TREE_VISIBLE=$(jq -r '.tree_visible' "$SESSION_FILE")
        TREE_ID=$(jq -r '.panes.tree' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer' "$SESSION_FILE")

        if [[ "$TREE_VISIBLE" == "true" ]]; then
            # Collapse: resize tree to minimum via perform action (pixel-based)
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                    -- Shrink tree pane by moving divider left repeatedly (pixels)
                    repeat 30 times
                        perform action \"resize_split:left,20\" on viewerTerm
                    end repeat
                end tell
            "
            jq '.tree_visible = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree collapsed"
        else
            # Restore: resize tree back to ~18% (pixel-based)
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                    repeat 15 times
                        perform action \"resize_split:right,20\" on viewerTerm
                    end repeat
                end tell
            "
            jq '.tree_visible = true' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
        fi
        ;;

    preview)
        CURRENT_MODE=$(jq -r '.viewer_mode' "$SESSION_FILE")
        CURRENT_FILE=$(jq -r '.current_file // empty' "$SESSION_FILE")
        CURRENT_LINE=$(jq -r '.current_line // "1"' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer' "$SESSION_FILE")

        if [[ "$CURRENT_MODE" == "bat" ]]; then
            NEW_MODE="glow"
        else
            NEW_MODE="bat"
        fi

        jq --arg m "$NEW_MODE" '.viewer_mode = $m' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
            && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

        # Re-render current file with new mode if one is active
        if [[ -n "$CURRENT_FILE" && -f "$CURRENT_FILE" ]]; then
            VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$CURRENT_FILE" "$CURRENT_LINE" "$NEW_MODE")
            if [[ -n "$VIEWER_CMD" ]]; then
                ESCAPED_CMD=$(printf '%s' "$VIEWER_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
                osascript -e "
                    tell application \"Ghostty\"
                        set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                        input text \"${ESCAPED_CMD}\n\" to viewerTerm
                    end tell
                " 2>/dev/null || true
            fi
        fi

        echo "idealize: viewer mode → ${NEW_MODE}"
        ;;

    *)
        echo "Usage: idealyze toggle tree|preview" >&2
        exit 1
        ;;
esac
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x lib/toggle.sh
git add lib/toggle.sh
git commit -m "feat: add toggle controller for tree and preview"
```

---

## Task 8: Main CLI entry point

**Files:**
- Create: `bin/idealyze`

- [ ] **Step 1: Create the main CLI**

```bash
#!/usr/bin/env bash
# idealyze — Terminal IDE for Claude Code
# https://github.com/diananerd/idealize

set -euo pipefail

VERSION="0.1.0"
IDEALYZE_HOME="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_HOME}/session.json"

# Resolve lib directory (works both from repo and installed)
if [[ -d "${IDEALYZE_HOME}/lib" ]]; then
    LIB_DIR="${IDEALYZE_HOME}/lib"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    LIB_DIR="${SCRIPT_DIR}/../lib"
fi

# Resolve config directory
if [[ -d "${IDEALYZE_HOME}/config" ]]; then
    CONFIG_DIR="${IDEALYZE_HOME}/config"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    CONFIG_DIR="${SCRIPT_DIR}/../config"
fi

usage() {
    cat <<'EOF'
idealyze — Terminal IDE for Claude Code

Usage:
    idealyze                  Launch IDE layout in current directory
    idealyze toggle tree      Collapse/restore file tree sidebar
    idealyze toggle preview   Switch between bat and glow viewer
    idealyze stop             Close session
    idealyze uninstall        Remove idealyze completely
    idealyze --version        Show version
    idealyze --help           Show this help

Requirements: Ghostty 1.3+, broot, bat, claude, jq
Optional: glow (for markdown preview)
EOF
}

check_deps() {
    local missing=()
    command -v osascript &>/dev/null || missing+=("osascript (macOS)")
    command -v broot &>/dev/null || missing+=("broot")
    command -v bat &>/dev/null || missing+=("bat")
    command -v claude &>/dev/null || missing+=("claude")
    command -v jq &>/dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "idealize: missing dependencies: ${missing[*]}" >&2
        exit 1
    fi

    # Check Ghostty is installed
    if [[ ! -d "/Applications/Ghostty.app" ]]; then
        echo "idealize: Ghostty.app not found in /Applications" >&2
        exit 1
    fi

    # Optional: glow
    if ! command -v glow &>/dev/null; then
        echo "idealize: glow not found (optional — preview mode will use bat)" >&2
    fi
}

launch() {
    local project_dir="${1:-$(pwd)}"

    # Check for existing session
    if [[ -f "$SESSION_FILE" ]]; then
        # Verify the session is still alive by checking if the Ghostty window exists
        local win_id
        win_id=$(jq -r '.panes.window // empty' "$SESSION_FILE")
        if [[ -n "$win_id" ]]; then
            # Try to query the window — if it fails, session is stale
            if ! osascript -e "
                tell application \"Ghostty\"
                    first window whose id is (${win_id} as integer)
                end tell
            " &>/dev/null; then
                echo "idealize: cleaning up stale session..."
                rm -f "$SESSION_FILE"
                rm -f "/tmp/broot-server-idealyze.sock"
            else
                echo "idealize: session already active. Run 'idealyze stop' first." >&2
                exit 1
            fi
        else
            rm -f "$SESSION_FILE"
        fi
    fi

    check_deps

    echo "idealize: launching in ${project_dir}..."

    # Create session directory
    mkdir -p "$IDEALYZE_HOME"

    # Run AppleScript layout — returns JSON with terminal IDs
    local pane_json
    pane_json=$(osascript "${LIB_DIR}/layout.applescript" \
        "$project_dir" \
        "$LIB_DIR" \
        "${CONFIG_DIR}/broot-sidebar.toml")

    # Build session.json
    local window_id viewer_id tree_id claude_id
    window_id=$(echo "$pane_json" | jq -r '.window_id')
    tree_id=$(echo "$pane_json" | jq -r '.tree_id')
    viewer_id=$(echo "$pane_json" | jq -r '.viewer_id')
    claude_id=$(echo "$pane_json" | jq -r '.claude_id')

    cat > "$SESSION_FILE" <<SESSIONEOF
{
    "version": "${VERSION}",
    "pid": $$,
    "project_dir": "${project_dir}",
    "broot_socket": "idealyze",
    "viewer_mode": "bat",
    "tree_visible": true,
    "current_file": null,
    "current_line": 1,
    "panes": {
        "window": "${window_id}",
        "tree": "${tree_id}",
        "viewer": "${viewer_id}",
        "claude": "${claude_id}"
    }
}
SESSIONEOF

    echo "idealize: ready. Claude hooks will sync automatically."
}

stop_session() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo "idealize: no active session" >&2
        exit 0
    fi

    # Clean up broot socket
    rm -f "/tmp/broot-server-idealyze.sock"

    # Remove session file
    rm -f "$SESSION_FILE"

    echo "idealize: session closed"
}

uninstall() {
    echo "idealize: uninstalling..."

    # Remove hooks from Claude settings
    local claude_settings="${HOME}/.claude/settings.json"
    if [[ -f "$claude_settings" ]]; then
        # Remove idealize hook entries
        jq 'if .hooks.PostToolUse then
            .hooks.PostToolUse |= map(
                select(.hooks | all(.command | test("idealyze") | not))
            ) |
            if .hooks.PostToolUse | length == 0 then del(.hooks.PostToolUse) else . end |
            if .hooks | length == 0 then del(.hooks) else . end
        else . end' "$claude_settings" > "${claude_settings}.tmp" \
            && mv "${claude_settings}.tmp" "$claude_settings"
        echo "  removed hooks from ${claude_settings}"
    fi

    # Remove idealyze home
    rm -rf "$IDEALYZE_HOME"
    echo "  removed ${IDEALYZE_HOME}"

    # Remove binary (self-delete)
    local self_path
    self_path="$(realpath "$0")"
    echo "  removing ${self_path}"
    rm -f "$self_path"

    echo "idealize: uninstalled"
}

# --- Main ---

case "${1:-}" in
    --version|-v)
        echo "idealyze ${VERSION}"
        ;;
    --help|-h)
        usage
        ;;
    --hook)
        # Internal: called by Claude hooks
        shift
        case "${1:-}" in
            post-tool-use)
                exec "${LIB_DIR}/hooks.sh"
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    toggle)
        shift
        exec "${LIB_DIR}/toggle.sh" "${1:-}"
        ;;
    stop)
        stop_session
        ;;
    uninstall)
        uninstall
        ;;
    "")
        launch
        ;;
    *)
        echo "idealize: unknown command '${1}'" >&2
        usage
        exit 1
        ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/idealyze
```

- [ ] **Step 3: Test help and version**

```bash
./bin/idealyze --help
./bin/idealyze --version
```

Expected: Help text displays correctly, version shows `idealyze 0.1.0`.

- [ ] **Step 4: Commit**

```bash
git add bin/idealyze
git commit -m "feat: add main CLI entry point"
```

---

## Task 9: Claude hooks config template

**Files:**
- Create: `config/claude-hooks.json`

- [ ] **Step 1: Create hook template**

This is the JSON fragment that the installer merges into `~/.claude/settings.json`.

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

- [ ] **Step 2: Commit**

```bash
git add config/claude-hooks.json
git commit -m "feat: add Claude hooks config template"
```

---

## Task 10: Install script

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create install.sh**

```bash
#!/usr/bin/env bash
# Idealize installer
# Usage: curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | sh

set -euo pipefail

REPO="diananerd/idealize"
INSTALL_DIR="${HOME}/.idealyze"
BIN_DIR="${HOME}/.local/bin"

echo "idealize: installing..."

# Create directories
mkdir -p "$INSTALL_DIR"/{lib,config}
mkdir -p "$BIN_DIR"

# Download files (from main branch)
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

echo "  downloading..."

# Core files
curl -fsSL "${BASE_URL}/bin/idealyze" -o "${BIN_DIR}/idealyze"
chmod +x "${BIN_DIR}/idealyze"

# Lib files
for f in layout.applescript hooks.sh viewer.sh tree.sh toggle.sh; do
    curl -fsSL "${BASE_URL}/lib/${f}" -o "${INSTALL_DIR}/lib/${f}"
    chmod +x "${INSTALL_DIR}/lib/${f}" 2>/dev/null || true
done

# Config files
curl -fsSL "${BASE_URL}/config/broot-sidebar.toml" -o "${INSTALL_DIR}/config/broot-sidebar.toml"

# Merge Claude hooks into settings
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="idealyze --hook post-tool-use"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # Check if hook already exists
    if jq -e '.hooks.PostToolUse[]?.hooks[]? | select(.command == "'"$HOOK_CMD"'")' "$CLAUDE_SETTINGS" &>/dev/null; then
        echo "  claude hooks already configured"
    else
        # Merge: add our hook entry to PostToolUse array
        jq --arg cmd "$HOOK_CMD" '
            .hooks //= {} |
            .hooks.PostToolUse //= [] |
            .hooks.PostToolUse += [{
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [{
                    "type": "command",
                    "command": $cmd,
                    "async": true
                }]
            }]
        ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" \
            && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        echo "  claude hooks configured"
    fi
else
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cat > "$CLAUDE_SETTINGS" <<HOOKSEOF
{
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [
                    {
                        "type": "command",
                        "command": "${HOOK_CMD}",
                        "async": true
                    }
                ]
            }
        ]
    }
}
HOOKSEOF
    echo "  claude hooks configured (new settings file)"
fi

# Check dependencies
echo ""
echo "  dependencies:"
for dep in broot bat claude jq; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "found")
        echo "    ✓ ${dep} (${ver})"
    else
        echo "    ✗ ${dep} — required, please install"
    fi
done

# Ghostty check
if [[ -d "/Applications/Ghostty.app" ]]; then
    echo "    ✓ ghostty"
else
    echo "    ✗ ghostty — required (macOS only)"
fi

# Optional: glow
if command -v glow &>/dev/null; then
    echo "    ✓ glow (optional)"
else
    echo "    ○ glow (optional — preview mode will use bat)"
fi

# Check PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠ ${BIN_DIR} is not in your PATH. Add it:"
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
fi

echo ""
echo "idealize: installed! Run 'idealyze' in any project directory."
```

- [ ] **Step 2: Make executable and test locally**

```bash
chmod +x install.sh
# Dry-run test: just check it parses correctly
bash -n install.sh
echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add curl|sh installer"
```

---

## Task 11: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 12: GitHub release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create release workflow**

Triggers on version tags (`v*`), creates a GitHub release with the source archive.

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create release archive
        run: |
          VERSION="${GITHUB_REF#refs/tags/}"
          tar -czf "idealyze-${VERSION}.tar.gz" \
            bin/ lib/ config/ install.sh LICENSE README.md

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: idealyze-*.tar.gz
```

- [ ] **Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/release.yml
git commit -m "ci: add GitHub release workflow"
```

---

## Task 13: End-to-end verification

- [ ] **Step 1: Run idealyze from the repo**

```bash
cd /Users/diananerd/Documents/personal/claude/idealize
./bin/idealyze
```

Expected: Ghostty opens with 3 panes — broot tree on left, "waiting for claude activity" in center, Claude Code on right.

- [ ] **Step 2: Test hook integration**

In the Claude pane, ask Claude to read a file:
```
Read the README.md file
```

Expected: broot navigates to README.md, bat renders it in the viewer pane with syntax highlighting.

- [ ] **Step 3: Test toggle tree**

```bash
./bin/idealyze toggle tree
# Tree should collapse
./bin/idealyze toggle tree
# Tree should restore
```

- [ ] **Step 4: Test toggle preview**

```bash
./bin/idealyze toggle preview
# With a .md file active, viewer should switch to glow
./bin/idealyze toggle preview
# Should switch back to bat
```

- [ ] **Step 5: Test stop**

```bash
./bin/idealyze stop
```

Expected: Session file removed, clean exit.

- [ ] **Step 6: Final commit with any fixes**

```bash
git add -A
git commit -m "fix: adjustments from e2e testing"
```

---

## Verification checklist

| Scenario | How to test | Expected |
|----------|-------------|----------|
| Launch | `idealyze` in any dir | 3-pane Ghostty layout opens |
| Auto-follow Read | Ask Claude to read a file | broot + bat update |
| Auto-follow Edit | Ask Claude to edit a file | broot + bat update with line highlighted |
| Auto-follow Glob | Ask Claude to glob a pattern | broot navigates to directory |
| Auto-follow Grep | Ask Claude to grep for a term | broot navigates to search path |
| Toggle tree | `idealyze toggle tree` x2 | Collapses then restores sidebar |
| Toggle preview | `idealyze toggle preview` on .md | Switches bat ↔ glow |
| Session guard | Hook fires without active session | Exit 0 silently, <1ms |
| Stale session | Close Ghostty, run `idealyze` again | Auto-cleans stale session, launches fresh |
| Stop | `idealyze stop` | Session file removed |
| Install | `bash install.sh` | Files installed, hooks merged |
| Uninstall | `idealyze uninstall` | Everything removed cleanly |
