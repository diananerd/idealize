#!/usr/bin/env bash
# lib/toggle.sh — Toggle tree sidebar or preview mode
# Usage: toggle.sh tree | toggle.sh preview

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[toggl $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "idealize: no active session" >&2
    exit 1
fi

ACTION="${1:-}"
debug "action=$ACTION"

case "$ACTION" in
    tree)
        read -r TREE_VISIBLE VIEWER_ID < <(jq -r '[.tree_visible, (.panes.viewer // "" | tostring)] | @tsv' "$SESSION_FILE")
        debug "tree_visible=$TREE_VISIBLE viewer_id=$VIEWER_ID"

        # Validate VIEWER_ID to prevent AppleScript injection
        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ "$TREE_VISIBLE" == "true" ]]; then
            debug "collapsing tree"
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    -- Shrink tree pane by moving divider left repeatedly (pixels)
                    repeat 30 times
                        perform action \"resize_split:left,20\" on viewerTerm
                    end repeat
                end tell
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || debug "osascript failed: $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null)"
            jq '.tree_visible = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree collapsed"
        else
            debug "restoring tree"
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    repeat 15 times
                        perform action \"resize_split:right,20\" on viewerTerm
                    end repeat
                end tell
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || debug "osascript failed: $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null)"
            jq '.tree_visible = true' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
        fi
        ;;

    preview)
        read -r CURRENT_MODE CURRENT_FILE CURRENT_LINE VIEWER_ID < <(jq -r '[.viewer_mode, (.current_file // ""), (.current_line // 1 | tostring), (.panes.viewer // "" | tostring)] | @tsv' "$SESSION_FILE")
        debug "mode=$CURRENT_MODE file=$CURRENT_FILE line=$CURRENT_LINE viewer_id=$VIEWER_ID"

        # Validate VIEWER_ID
        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ "$CURRENT_MODE" == "bat" ]]; then
            NEW_MODE="glow"
        else
            NEW_MODE="bat"
        fi

        jq --arg m "$NEW_MODE" '.viewer_mode = $m' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
            && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

        # Re-render current file with new mode if one is active
        if [[ -n "$CURRENT_FILE" && -f "$CURRENT_FILE" ]]; then
            VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$CURRENT_FILE" "$CURRENT_LINE" "$NEW_MODE")
            debug "viewer_cmd=$VIEWER_CMD"
            if [[ -n "$VIEWER_CMD" ]]; then
                ESCAPED_CMD=$(printf '%s' "$VIEWER_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
                osascript -e "
                    tell application \"Ghostty\"
                        set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                        input text \"${ESCAPED_CMD}\n\" to viewerTerm
                    end tell
                " 2>"${IDEALYZE_DIR}/osascript-error.log" || debug "osascript failed: $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null)"
            fi
        fi

        echo "idealize: viewer mode → ${NEW_MODE}"
        debug "switched to $NEW_MODE"
        ;;

    *)
        echo "Usage: idealyze toggle tree|preview" >&2
        exit 1
        ;;
esac
