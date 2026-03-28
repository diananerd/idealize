#!/usr/bin/env bash
# lib/viewer-loop.sh — Persistent viewer process for the read pane
# Watches ~/.idealyze/viewer-cmd for new commands and re-renders on resize (SIGWINCH).

set -uo pipefail

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
        # Only allow commands matching: clear && [bat|glow|BAT_HIGHLIGHT_COLOR|H=]...
        if [[ "$CURRENT_CMD" =~ ^clear\ \&\&\ (bat|glow|BAT_HIGHLIGHT_COLOR|H=) ]]; then
            eval "$CURRENT_CMD" 2>/dev/null || true
        else
            debug "rejected command: ${CURRENT_CMD:0:80}"
        fi
    fi
}

# Re-render on terminal resize
trap 'render' WINCH

# Initialize command file
mkdir -p "$IDEALYZE_DIR"
: > "$CMD_FILE"

debug "viewer-loop started"

# Show initial file: prefer README, then first non-hidden file
PROJECT_DIR="${1:-.}"
initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f -iname 'readme*' 2>/dev/null | head -1)
[[ -z "$initial_file" ]] && initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | sort | head -1)
if [[ -n "$initial_file" ]]; then
    # Delay to let layout finish resizing panes
    sleep 1
    CURRENT_CMD="clear && bat --paging=never --wrap=auto --style=numbers,header,grid --color=always '${initial_file//\'/\'\\\'\'}'"
    render
else
    echo "idealize: no files found in project root"
fi

# Poll for new commands from hooks
while true; do
    if [[ -f "$CMD_FILE" ]]; then
        # Atomic read-and-clear: mv then read to avoid race conditions
        if mv "$CMD_FILE" "${CMD_FILE}.processing" 2>/dev/null; then
            new_cmd=$(cat "${CMD_FILE}.processing" 2>/dev/null)
            rm -f "${CMD_FILE}.processing"
            if [[ -n "$new_cmd" ]]; then
                CURRENT_CMD="$new_cmd"
                debug "new cmd: ${CURRENT_CMD:0:100}"
                render
            fi
        fi
    fi
    sleep 0.3
done
