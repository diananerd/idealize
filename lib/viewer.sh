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
