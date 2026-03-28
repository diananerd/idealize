#!/usr/bin/env bash
# lib/viewer.sh — Build viewer command for bat or glow
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

FILE_PATH="${1:-}"
LINE_NUMBER="${2:-}"
VIEWER_MODE="${3:-$(cfg viewer.mode raw)}"
LINE_END="${4:-}"

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

FILE_EXT="${FILE_PATH##*.}"

# Glow for markdown in rendered mode
if [[ "$VIEWER_MODE" == "glow" && "$FILE_EXT" == "md" ]] && command -v glow &>/dev/null; then
    GLOW_STYLE=""
    if [[ -f "${HOME}/.idealyze/config/glow-style.json" ]]; then
        GLOW_STYLE="-s ${HOME}/.idealyze/config/glow-style.json"
    elif [[ -f "${LIB_DIR}/../config/glow-style.json" ]]; then
        GLOW_STYLE="-s $(cd "${LIB_DIR}/../config" && pwd)/glow-style.json"
    fi
    echo "clear && glow ${GLOW_STYLE} -w \$(tput cols) \"${FILE_PATH}\""
    exit 0
fi

[[ "$LINE_NUMBER" =~ ^[0-9]+$ ]] || LINE_NUMBER=""
[[ "$LINE_END" =~ ^[0-9]+$ ]] || LINE_END=""

BAT_STYLE=$(cfg "viewer.bat_style" "numbers,header,grid")
BAT="bat --paging=never --wrap=auto --style=${BAT_STYLE} --color=always"

HL_FROM=$(cfg "viewer.highlight_color_source" "51;51;51")
HL_TO=$(cfg "viewer.highlight_color" "40;40;160")
BOOST="sed $'s/48;2;${HL_FROM}/48;2;${HL_TO}/g'"

if [[ -n "$LINE_END" && "$LINE_END" -gt "${LINE_NUMBER:-0}" ]]; then
    HIGHLIGHT="${LINE_NUMBER}:${LINE_END}"
else
    HIGHLIGHT="${LINE_NUMBER}"
fi

if [[ -n "$LINE_NUMBER" && "$LINE_NUMBER" != "0" ]]; then
    echo "clear && H=\$(tput lines); S=\$(( ${LINE_NUMBER} > H/2 ? ${LINE_NUMBER} - H/2 : 1 )); E=\$(( S + H - 3 )); ${BAT} --highlight-line ${HIGHLIGHT} --line-range \${S}:\${E} \"${FILE_PATH}\" | ${BOOST}"
else
    echo "clear && ${BAT} --line-range 1:\$(tput lines) \"${FILE_PATH}\""
fi
