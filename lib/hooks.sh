#!/usr/bin/env bash
# lib/hooks.sh — PostToolUse hook handler
# Dispatches to tree and viewer based on agent events.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

# Session guard
[[ -f "$SESSION_FILE" ]] || exit 0

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[hooks $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

# Read session state
VIEWER_ID=$(jq -r '.panes.viewer // ""' "$SESSION_FILE")
PROJECT_DIR=$(jq -r '.project_dir // ""' "$SESSION_FILE")
VIEWER_MODE=$(cfg "viewer.mode" "raw")
SCOPE=$(cfg "scope" "project")

[[ -z "$VIEWER_ID" ]] && exit 0
[[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || exit 0

# Load provider
PROVIDER=$(cfg "provider" "claude-code")
source "${LIB_DIR}/providers/${PROVIDER}.sh"

# Read hook JSON
HOOK_JSON=$(cat)
debug "stdin: ${HOOK_JSON:0:500}"

# Parse event with provider
PARSED=$(provider_parse_event "$HOOK_JSON") || { debug "parse failed"; exit 0; }
eval "$PARSED"
debug "tool=$TOOL_NAME type=${TOOL_TYPE:-}"

# Scope filter
if [[ "$SCOPE" != "global" && -n "$PROJECT_DIR" ]]; then
    local_path="${FILE_PATH:-${EVENT_PATH:-}}"
    if [[ -n "$local_path" && "$local_path" != "$PROJECT_DIR"* ]]; then
        debug "skipped: $local_path outside $PROJECT_DIR"
        exit 0
    fi
fi

# Search tools (Grep/Glob) — update tree only
if [[ "${TOOL_TYPE:-}" == "search" ]]; then
    if [[ -n "${EVENT_PATH:-}" ]]; then
        if [[ -d "$EVENT_PATH" ]]; then
            "$LIB_DIR/tree.sh" focus "$EVENT_PATH" &
        elif [[ -f "$EVENT_PATH" ]]; then
            "$LIB_DIR/tree.sh" select "$EVENT_PATH" &
        fi
    fi
    wait
    exit 0
fi

# File tools — update tree + viewer
[[ -z "${FILE_PATH:-}" || ! -f "${FILE_PATH:-}" ]] && exit 0

"$LIB_DIR/tree.sh" select "$FILE_PATH" &

VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$FILE_PATH" "${LINE_NUMBER:-}" "$VIEWER_MODE" "${LINE_END:-}")
debug "viewer_cmd: $VIEWER_CMD"

if [[ -n "$VIEWER_CMD" ]]; then
    printf '%s' "$VIEWER_CMD" > "${IDEALYZE_DIR}/viewer-cmd.tmp"
    mv "${IDEALYZE_DIR}/viewer-cmd.tmp" "${IDEALYZE_DIR}/viewer-cmd"
fi

printf '%s\n%s' "$FILE_PATH" "${LINE_NUMBER:-1}" > "${IDEALYZE_DIR}/current-file"

debug "done"
wait
