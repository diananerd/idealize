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
