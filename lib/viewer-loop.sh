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
        # Only allow commands starting with known safe prefixes
        if [[ "$CURRENT_CMD" == clear* ]]; then
            eval "$CURRENT_CMD" || echo "idealize: viewer render failed" >&2
        else
            debug "rejected unsafe command: ${CURRENT_CMD:0:80}"
            echo "idealize: viewer rejected unexpected command format" >&2
        fi
    fi
}

# Re-render on terminal resize
trap 'render' WINCH

# Initialize command file
mkdir -p "$IDEALYZE_DIR"
echo "" > "$CMD_FILE"

debug "viewer-loop started"

# Show initial file: prefer README, then first non-hidden file
PROJECT_DIR="${1:-.}"
initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f -iname 'readme*' | head -1)
[[ -z "$initial_file" ]] && initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f ! -name '.*' | sort | head -1)
if [[ -n "$initial_file" ]]; then
    # Delay to let layout finish resizing panes
    sleep 1
    CURRENT_CMD="clear && bat --paging=never --wrap=auto --terminal-width=\$(tput cols) --style=numbers,header,grid --color=always --line-range 1:\$(tput lines) \"${initial_file}\""
    render
else
    echo "idealize: no files found in project root"
fi

# Disable errexit for the loop — individual render failures should not kill the viewer
set +e

# Poll for new commands from hooks
while true; do
    if [[ -f "$CMD_FILE" ]]; then
        new_cmd=$(cat "$CMD_FILE" 2>/dev/null)
        if [[ -n "$new_cmd" ]]; then
            CURRENT_CMD="$new_cmd"
            debug "new cmd: ${CURRENT_CMD:0:100}"
            render
            # Clear the file after reading
            : > "$CMD_FILE"
        fi
    fi
    sleep 0.3
done
