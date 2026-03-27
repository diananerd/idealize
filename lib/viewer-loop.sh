#!/usr/bin/env bash
# lib/viewer-loop.sh — Persistent viewer process for the read pane
# Watches ~/.idealyze/viewer-cmd for new commands and re-renders on resize (SIGWINCH).

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
CMD_FILE="${IDEALYZE_DIR}/viewer-cmd"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[vloop $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

# Current state
CURRENT_CMD=""

render() {
    if [[ -n "$CURRENT_CMD" ]]; then
        eval "$CURRENT_CMD"
    fi
}

# Re-render on terminal resize
trap 'render' WINCH

# Initialize command file
mkdir -p "$IDEALYZE_DIR"
echo "" > "$CMD_FILE"

debug "viewer-loop started"

# Show initial file: first non-hidden file in project root
PROJECT_DIR="${1:-.}"
initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f ! -name '.*' | sort | head -1)
if [[ -n "$initial_file" ]]; then
    CURRENT_CMD="clear && bat --paging=never --style=numbers,header,grid --color=always \"${initial_file}\""
    render
else
    echo "idealize: no files found in project root"
fi

# Poll for new commands from hooks
while true; do
    if [[ -f "$CMD_FILE" ]]; then
        new_cmd=$(cat "$CMD_FILE" 2>/dev/null)
        if [[ -n "$new_cmd" && "$new_cmd" != "$CURRENT_CMD" ]]; then
            CURRENT_CMD="$new_cmd"
            debug "new cmd: ${CURRENT_CMD:0:100}"
            render
            # Clear the file after reading
            : > "$CMD_FILE"
        fi
    fi
    sleep 0.3
done
