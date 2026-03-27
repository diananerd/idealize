#!/usr/bin/env bash
# lib/toggle.sh — Toggle tree sidebar or preview mode
# Usage: toggle.sh tree | toggle.sh preview

set -euo pipefail

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "idealize: no active session" >&2
    exit 1
fi

ACTION="${1:-}"

case "$ACTION" in
    tree)
        TREE_VISIBLE=$(jq -r '.tree_visible' "$SESSION_FILE")
        TREE_ID=$(jq -r '.panes.tree' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer' "$SESSION_FILE")

        if [[ "$TREE_VISIBLE" == "true" ]]; then
            # Collapse: resize tree to minimum via perform action (pixel-based)
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                    -- Shrink tree pane by moving divider left repeatedly (pixels)
                    repeat 30 times
                        perform action \"resize_split:left,20\" on viewerTerm
                    end repeat
                end tell
            "
            jq '.tree_visible = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree collapsed"
        else
            # Restore: resize tree back to ~18% (pixel-based)
            osascript -e "
                tell application \"Ghostty\"
                    set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                    repeat 15 times
                        perform action \"resize_split:right,20\" on viewerTerm
                    end repeat
                end tell
            "
            jq '.tree_visible = true' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
        fi
        ;;

    preview)
        CURRENT_MODE=$(jq -r '.viewer_mode' "$SESSION_FILE")
        CURRENT_FILE=$(jq -r '.current_file // empty' "$SESSION_FILE")
        CURRENT_LINE=$(jq -r '.current_line // "1"' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer' "$SESSION_FILE")

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
            if [[ -n "$VIEWER_CMD" ]]; then
                ESCAPED_CMD=$(printf '%s' "$VIEWER_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
                osascript -e "
                    tell application \"Ghostty\"
                        set viewerTerm to first terminal whose id is (${VIEWER_ID} as integer)
                        input text \"${ESCAPED_CMD}\n\" to viewerTerm
                    end tell
                " 2>/dev/null || true
            fi
        fi

        echo "idealize: viewer mode → ${NEW_MODE}"
        ;;

    *)
        echo "Usage: idealyze toggle tree|preview" >&2
        exit 1
        ;;
esac
