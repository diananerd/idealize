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
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || {
                echo "idealize: failed to collapse tree — $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null || echo 'unknown osascript error')" >&2
                exit 1
            }
            if ! jq '.tree_visible = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp"; then
                echo "idealize: failed to update session file" >&2
                exit 1
            fi
            mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
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
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || {
                echo "idealize: failed to restore tree — $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null || echo 'unknown osascript error')" >&2
                exit 1
            }
            if ! jq '.tree_visible = true' "$SESSION_FILE" > "${SESSION_FILE}.tmp"; then
                echo "idealize: failed to update session file" >&2
                exit 1
            fi
            mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
        fi
        ;;

    preview)
        read -r CURRENT_MODE VIEWER_ID < <(jq -r '[.viewer_mode, (.panes.viewer // "" | tostring)] | @tsv' "$SESSION_FILE")
        # Read current file/line from the IPC file (hooks.sh writes here, not session.json)
        CURRENT_FILE=""
        CURRENT_LINE="1"
        if [[ -f "${IDEALYZE_DIR}/current-file" ]]; then
            CURRENT_FILE=$(sed -n '1p' "${IDEALYZE_DIR}/current-file")
            CURRENT_LINE=$(sed -n '2p' "${IDEALYZE_DIR}/current-file")
            CURRENT_LINE="${CURRENT_LINE:-1}"
        fi
        debug "mode=$CURRENT_MODE file=$CURRENT_FILE line=$CURRENT_LINE viewer_id=$VIEWER_ID"

        # Validate VIEWER_ID
        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ "$CURRENT_MODE" == "bat" ]]; then
            NEW_MODE="glow"
        else
            NEW_MODE="bat"
        fi

        if ! jq --arg m "$NEW_MODE" '.viewer_mode = $m' "$SESSION_FILE" > "${SESSION_FILE}.tmp"; then
            echo "idealize: failed to update viewer mode in session" >&2
            exit 1
        fi
        mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

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
                " 2>"${IDEALYZE_DIR}/osascript-error.log" || {
                    echo "idealize: failed to send viewer command — $(cat "${IDEALYZE_DIR}/osascript-error.log" 2>/dev/null || echo 'unknown osascript error')" >&2
                    exit 1
                }
            fi
        fi

        echo "idealize: viewer mode → ${NEW_MODE}"
        debug "switched to $NEW_MODE"
        ;;

    claude)
        CLAUDE_ID=$(jq -r '.panes.claude // "" | tostring' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer // "" | tostring' "$SESSION_FILE")
        debug "claude_id=$CLAUDE_ID viewer_id=$VIEWER_ID"

        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ -z "$CLAUDE_ID" ]]; then
            # Add Claude pane: split right from viewer
            debug "adding claude pane"
            project_dir=$(jq -r '.project_dir' "$SESSION_FILE")
            NEW_IDS=$(osascript -e "
                tell application \"Ghostty\"
                    set cfg to new surface configuration
                    set initial working directory of cfg to \"${project_dir}\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    set claudeTerm to split viewerTerm direction right with configuration cfg
                    input text \"claude\n\" to claudeTerm
                    return id of claudeTerm
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || {
                echo "idealize: failed to add claude pane" >&2; exit 1
            }
            debug "new claude_id=$NEW_IDS"
            jq --arg c "$NEW_IDS" '.panes.claude = $c' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: claude pane added"
        else
            # Remove Claude pane: close it
            debug "removing claude pane"
            [[ "$CLAUDE_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid claude id" >&2; exit 1; }
            osascript -e "
                tell application \"Ghostty\"
                    set claudeTerm to first terminal whose id is \"${CLAUDE_ID}\"
                    perform action \"close_surface\" on claudeTerm
                end tell
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || true
            jq '.panes.claude = ""' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: claude pane removed"
        fi
        ;;

    *)
        echo "Usage: idealyze toggle tree|claude|preview" >&2
        exit 1
        ;;
esac
