#!/usr/bin/env bash
# lib/hooks.sh — Claude PostToolUse hook handler
# Called by Claude with JSON on stdin. Dispatches to tree and viewer.

set -uo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

# Session guard: exit immediately if no active session (before any I/O)
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Debug helper — always log (session exists so directory is guaranteed)
debug() {
    echo "[hooks $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG"
}
debug "--- hook invoked ---"

# Read session state (single jq call)
read -r VIEWER_MODE VIEWER_ID PROJECT_DIR SCOPE < <(jq -r '[.viewer_mode // "bat", (.panes.viewer // "" | tostring), .project_dir // "", .scope // "project"] | @tsv' "$SESSION_FILE")
debug "session: viewer_mode=$VIEWER_MODE viewer_id=$VIEWER_ID project_dir=$PROJECT_DIR scope=$SCOPE"

if [[ -z "$VIEWER_ID" ]]; then
    debug "empty VIEWER_ID, exiting"
    echo "idealize: hook skipped — no viewer pane in session" >&2
    exit 0
fi

# Validate VIEWER_ID is alphanumeric/UUID to prevent AppleScript injection
if [[ ! "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
    debug "invalid VIEWER_ID: $VIEWER_ID"
    echo "idealize: hook skipped — invalid viewer ID in session" >&2
    exit 0
fi

# Read hook JSON from stdin
HOOK_JSON=$(cat)
debug "stdin: ${HOOK_JSON:0:500}"

TOOL_NAME=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_name // empty')
if [[ -z "$TOOL_NAME" ]]; then
    debug "no tool_name in JSON, exiting"
    echo "idealize: hook skipped — no tool_name in hook JSON" >&2
    exit 0
fi
debug "tool: $TOOL_NAME"

# Filter by project scope (skip events from other projects unless scope=global)
if [[ "$SCOPE" != "global" && -n "$PROJECT_DIR" ]]; then
    # Quick check: extract any file/path from the hook JSON
    EVENT_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.file_path // .tool_input.path // empty')
    if [[ -n "$EVENT_PATH" && "$EVENT_PATH" != "$PROJECT_DIR"* ]]; then
        debug "skipped: $EVENT_PATH outside project $PROJECT_DIR"
        exit 0
    fi
fi

# Extract file path based on tool type
FILE_PATH=""
LINE_END=""
LINE_NUMBER=""

case "$TOOL_NAME" in
    Read)
        FILE_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        read_offset=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.offset // 0')
        read_limit=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.limit // 0')
        if [[ "$read_offset" =~ ^[0-9]+$ && "$read_offset" -gt 0 ]]; then
            # Center on the middle of the read block
            if [[ "$read_limit" =~ ^[0-9]+$ && "$read_limit" -gt 0 ]]; then
                LINE_NUMBER=$(( read_offset + read_limit / 2 ))
            else
                LINE_NUMBER="$read_offset"
            fi
        else
            LINE_NUMBER=""
        fi
        debug "Read: file=$FILE_PATH line=$LINE_NUMBER (offset=$read_offset limit=$read_limit)"
        ;;
    Edit)
        FILE_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        # Find line range of new_string in the file
        NEW_STRING=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.new_string // empty')
        if [[ -n "$NEW_STRING" && -n "$FILE_PATH" && -f "$FILE_PATH" ]]; then
            FIRST_LINE=$(printf '%s' "$NEW_STRING" | head -1)
            LINE_NUMBER=$(grep -nF -- "$FIRST_LINE" "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1 || true)
            # Count lines in new_string for multi-line highlight
            new_line_count=$(printf '%s' "$NEW_STRING" | wc -l | tr -d ' ')
            if [[ -n "$LINE_NUMBER" && "$new_line_count" -gt 1 ]]; then
                LINE_END=$(( LINE_NUMBER + new_line_count ))
            fi
        fi
        LINE_NUMBER="${LINE_NUMBER:-1}"
        debug "Edit: file=$FILE_PATH line=$LINE_NUMBER end=${LINE_END:-}"
        ;;
    Write)
        FILE_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
        LINE_NUMBER="1"
        debug "Write: file=$FILE_PATH"
        ;;
    Grep)
        # Grep: navigate tree to the search path if specified
        GREP_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.path // empty')
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
        GLOB_PATH=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.path // empty')
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

if [[ -z "$FILE_PATH" ]]; then
    debug "empty file path from tool"
    exit 0
fi
if [[ ! -f "$FILE_PATH" ]]; then
    debug "file not found: $FILE_PATH"
    echo "idealize: hook skipped — file not found: $FILE_PATH" >&2
    exit 0
fi

# Update tree sidebar (background, non-blocking)
"$LIB_DIR/tree.sh" select "$FILE_PATH" &

# Build viewer command
VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$FILE_PATH" "$LINE_NUMBER" "$VIEWER_MODE" "${LINE_END:-}")
debug "viewer_cmd: $VIEWER_CMD"

if [[ -n "$VIEWER_CMD" ]]; then
    # Write command to viewer-cmd file (viewer-loop.sh picks it up)
    debug "writing viewer cmd to file"
    printf '%s' "$VIEWER_CMD" > "${IDEALYZE_DIR}/viewer-cmd.tmp"
    mv "${IDEALYZE_DIR}/viewer-cmd.tmp" "${IDEALYZE_DIR}/viewer-cmd"
fi

# Store current file for toggle preview (separate file to avoid race conditions)
printf '%s\n%s' "$FILE_PATH" "${LINE_NUMBER:-1}" > "${IDEALYZE_DIR}/current-file"

debug "done"
wait
