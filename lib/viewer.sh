#!/usr/bin/env bash
# lib/viewer.sh — Build viewer command for bat or glow
# Usage: viewer.sh <file_path> [line_number] [viewer_mode]
# Outputs: the shell command to run in the viewer pane

set -euo pipefail

FILE_PATH="${1:-}"
LINE_NUMBER="${2:-}"
VIEWER_MODE="${3:-bat}"
LINE_END="${4:-}"
DEBUG_LOG="${HOME}/.idealyze/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[viewr $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

debug "file=$FILE_PATH line=$LINE_NUMBER mode=$VIEWER_MODE"

if [[ -z "$FILE_PATH" ]]; then
    echo "idealize: viewer.sh requires a file path argument" >&2
    exit 1
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    echo "idealize: viewer.sh file not found: $FILE_PATH" >&2
    exit 1
fi

FILE_EXT="${FILE_PATH##*.}"

# Use glow for markdown when in preview mode
if [[ "$VIEWER_MODE" == "glow" && "$FILE_EXT" == "md" ]] && command -v glow &>/dev/null; then
    # Resolve glow style (installed or repo config)
    GLOW_STYLE=""
    if [[ -f "${HOME}/.idealyze/config/glow-style.json" ]]; then
        GLOW_STYLE="-s ${HOME}/.idealyze/config/glow-style.json"
    elif [[ -f "$(cd "$(dirname "$0")/../config" 2>/dev/null && pwd)/glow-style.json" ]]; then
        GLOW_STYLE="-s $(cd "$(dirname "$0")/../config" && pwd)/glow-style.json"
    fi
    CMD="clear && glow ${GLOW_STYLE} -w \$(tput cols) \"${FILE_PATH}\""
    debug "glow cmd: $CMD"
    echo "$CMD"
    exit 0
fi

# Validate LINE_NUMBER is numeric to prevent injection in arithmetic
[[ "$LINE_NUMBER" =~ ^[0-9]+$ ]] || LINE_NUMBER=""

BAT="bat --paging=never --wrap=auto --style=numbers,header,grid --color=always"

# Boost bat's highlight color from dim gray (51,51,51) to vivid blue (40,40,160)
# Must replace both "48;2;51;51;51;" (bg+fg combined) and "48;2;51;51;51m" (bg only)
BOOST="sed $'s/48;2;51;51;51/48;2;40;40;160/g'"

# Build highlight range (single line or multi-line block)
[[ "$LINE_END" =~ ^[0-9]+$ ]] || LINE_END=""
if [[ -n "$LINE_END" && "$LINE_END" -gt "${LINE_NUMBER:-0}" ]]; then
    HIGHLIGHT="${LINE_NUMBER}:${LINE_END}"
else
    HIGHLIGHT="${LINE_NUMBER}"
fi

if [[ -n "$LINE_NUMBER" && "$LINE_NUMBER" != "0" ]]; then
    # Terminal-height window centered on the target line
    CMD="clear && H=\$(tput lines); S=\$(( ${LINE_NUMBER} > H/2 ? ${LINE_NUMBER} - H/2 : 1 )); E=\$(( S + H - 3 )); ${BAT} --highlight-line ${HIGHLIGHT} --line-range \${S}:\${E} \"${FILE_PATH}\" | ${BOOST}"
else
    # No specific line — show full file
    CMD="clear && ${BAT} \"${FILE_PATH}\""
fi

debug "cmd: $CMD"
echo "$CMD"
