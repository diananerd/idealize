#!/usr/bin/env bash
# lib/hooks.sh — Claude PostToolUse hook handler
# Called by Claude with JSON on stdin. Dispatches to tree and viewer.

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

# Debug helper — logs to ~/.idealyze/debug.log when IDEALYZE_DEBUG=1
debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[hooks $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

debug "--- hook invoked ---"

# Session guard: exit immediately if no active session
if [[ ! -f "$SESSION_FILE" ]]; then
    debug "no session file, exiting"
    exit 0
fi

# Read session state (single jq call)
read -r VIEWER_MODE VIEWER_ID < <(jq -r '[.viewer_mode // "bat", (.panes.viewer // "" | tostring)] | @tsv' "$SESSION_FILE")
debug "session: viewer_mode=$VIEWER_MODE viewer_id=$VIEWER_ID"

if [[ -z "$VIEWER_ID" ]]; then
    debug "empty VIEWER_ID, exiting"
    exit 0
fi

# Validate VIEWER_ID is alphanumeric/UUID to prevent AppleScript injection
if [[ ! "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
    debug "invalid VIEWER_ID: $VIEWER_ID"
    exit 0
fi

# Read hook JSON from stdin
HOOK_JSON=$(cat)
debug "stdin: ${HOOK_JSON:0:200}"

TOOL_NAME=$(echo "$HOOK_JSON" | jq -r '.tool_name // empty')
if [[ -z "$TOOL_NAME" ]]; then
    debug "no tool_name in JSON, exiting"
    exit 0
fi
debug "tool: $TOOL_NAME"

# Extract file path based on tool type
FILE_PATH=""
LINE_NUMBER=""

case "$TOOL_NAME" in
    Read)
        FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        LINE_NUMBER=$(echo "$HOOK_JSON" | jq -r '.tool_input.offset // "1"')
        debug "Read: file=$FILE_PATH line=$LINE_NUMBER"
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
        debug "Edit: file=$FILE_PATH line=$LINE_NUMBER"
        ;;
    Write)
        FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        LINE_NUMBER="1"
        debug "Write: file=$FILE_PATH"
        ;;
    Grep)
        # Grep: navigate tree to the search path if specified
        GREP_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.path // empty')
        debug "Grep: path=$GREP_PATH"
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
        debug "Glob: path=$GLOB_PATH"
        if [[ -n "$GLOB_PATH" && -d "$GLOB_PATH" ]]; then
            "$LIB_DIR/tree.sh" focus "$GLOB_PATH" &
        fi
        exit 0
        ;;
    *)
        debug "unhandled tool: $TOOL_NAME"
        exit 0
        ;;
esac

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    debug "file not found or empty: $FILE_PATH"
    exit 0
fi

# Update tree sidebar (background, non-blocking)
"$LIB_DIR/tree.sh" select "$FILE_PATH" &

# Build viewer command
VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$FILE_PATH" "$LINE_NUMBER" "$VIEWER_MODE")
debug "viewer_cmd: $VIEWER_CMD"

if [[ -n "$VIEWER_CMD" ]]; then
    # Send command to viewer pane via Ghostty AppleScript
    # Escape double quotes in VIEWER_CMD to avoid breaking AppleScript string
    ESCAPED_CMD=$(printf '%s' "$VIEWER_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
    debug "sending to Ghostty viewer=$VIEWER_ID"
    osascript -e "
        tell application \"Ghostty\"
            set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
            input text \"${ESCAPED_CMD}\n\" to viewerTerm
        end tell
    " 2>"${IDEALYZE_DIR}/osascript-error.log" || debug "osascript failed: $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null)"
fi

# Store current file for toggle preview
jq --arg f "$FILE_PATH" --arg l "${LINE_NUMBER:-1}" \
    '.current_file = $f | .current_line = ($l | tonumber)' \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

debug "done"
wait
