#!/usr/bin/env bash
# lib/viewer-loop.sh — Persistent viewer process for the read pane
# Watches ~/.idealyze/viewer-cmd for new commands and re-renders on resize (SIGWINCH).

set -uo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

POLL_INTERVAL=$(cfg "viewer.poll_interval" "0.3")
STABILIZE_RETRIES=$(cfg "layout.dimension_stabilize_retries" "10")

IDEALYZE_DIR="${HOME}/.idealyze"
CMD_FILE="${IDEALYZE_DIR}/viewer-cmd"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[vloop $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

# Current state
CURRENT_CMD=""
RENDER_REQUESTED=false

render() {
    if [[ -n "$CURRENT_CMD" ]]; then
        debug "render: ${CURRENT_CMD:0:80}"
        if [[ "$CURRENT_CMD" =~ ^clear\ \&\&\ (bat|glow|BAT_HIGHLIGHT_COLOR|H=) ]]; then
            eval "$CURRENT_CMD" 2>/dev/null || debug "render eval failed"
        else
            debug "rejected: ${CURRENT_CMD:0:80}"
        fi
    fi
}

on_winch() {
    debug "WINCH received"
    RENDER_REQUESTED=true
}

# Re-render on terminal resize
trap 'on_winch' WINCH

# Cleanup on exit
trap 'rm -f "${IDEALYZE_DIR}/viewer-loop.pid"; exit' EXIT INT TERM

# Initialize
mkdir -p "$IDEALYZE_DIR"
: > "$CMD_FILE"

echo $$ > "${IDEALYZE_DIR}/viewer-loop.pid"
debug "viewer-loop started (pid=$$, pid_file=${IDEALYZE_DIR}/viewer-loop.pid)"
debug "pid file exists: $(ls -la "${IDEALYZE_DIR}/viewer-loop.pid" 2>&1)"

# Show initial file: prefer README, then first non-hidden file
PROJECT_DIR="${1:-.}"
initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f -iname 'readme*' 2>/dev/null | head -1)
[[ -z "$initial_file" ]] && initial_file=$(find "$PROJECT_DIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | sort | head -1)
if [[ -n "$initial_file" ]]; then
    # Wait for pane dimensions to stabilize
    prev_cols=0
    for _ in $(seq 1 "$STABILIZE_RETRIES"); do
        cur_cols=$(tput cols 2>/dev/null || echo 0)
        [[ "$cur_cols" == "$prev_cols" && "$cur_cols" -gt 0 ]] && break
        prev_cols="$cur_cols"
        sleep "$POLL_INTERVAL"
    done
    debug "initial render: cols=$(tput cols 2>/dev/null) lines=$(tput lines 2>/dev/null) file=$initial_file"
    CURRENT_CMD="clear && bat --paging=never --wrap=auto --style=numbers,header,grid --color=always '${initial_file//\'/\'\\\'\'}'"
    render
else
    echo "idealize: no files found in project root"
fi

# Main loop — poll for commands + handle deferred WINCH renders
while true; do
    # Check for new viewer command
    if [[ -f "$CMD_FILE" ]]; then
        if mv "$CMD_FILE" "${CMD_FILE}.processing" 2>/dev/null; then
            new_cmd=$(cat "${CMD_FILE}.processing" 2>/dev/null)
            rm -f "${CMD_FILE}.processing"
            if [[ -n "$new_cmd" ]]; then
                CURRENT_CMD="$new_cmd"
                debug "new cmd: ${CURRENT_CMD:0:100}"
                render
                RENDER_REQUESTED=false
            fi
        fi
    fi

    # Handle deferred WINCH render (signal sets flag, loop does the render)
    if [[ "$RENDER_REQUESTED" == true ]]; then
        RENDER_REQUESTED=false
        debug "deferred WINCH render: cols=$(tput cols 2>/dev/null)"
        render
    fi

    # Interruptible sleep: use background sleep + wait so WINCH can wake us
    sleep "$POLL_INTERVAL" &
    wait $! 2>/dev/null || true
done
