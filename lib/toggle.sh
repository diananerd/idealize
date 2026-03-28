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

        # Re-render current file with new mode via viewer-cmd (consistent with hooks path)
        if [[ -n "$CURRENT_FILE" && -f "$CURRENT_FILE" ]]; then
            VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$CURRENT_FILE" "$CURRENT_LINE" "$NEW_MODE")
            debug "viewer_cmd=$VIEWER_CMD"
            if [[ -n "$VIEWER_CMD" ]]; then
                printf '%s' "$VIEWER_CMD" > "${IDEALYZE_DIR}/viewer-cmd.tmp"
                mv "${IDEALYZE_DIR}/viewer-cmd.tmp" "${IDEALYZE_DIR}/viewer-cmd"
            fi
        fi

        echo "idealize: viewer mode → ${NEW_MODE}"
        debug "switched to $NEW_MODE"
        ;;

    agent)
        AGENT_ID=$(jq -r '.panes.agent // "" | tostring' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer // "" | tostring' "$SESSION_FILE")
        AGENT_CMD=$(jq -r '.agent_cmd // "claude"' "$SESSION_FILE")
        debug "agent_id=$AGENT_ID viewer_id=$VIEWER_ID agent_cmd=$AGENT_CMD"

        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ -z "$AGENT_ID" ]]; then
            debug "adding agent pane (cmd=$AGENT_CMD)"
            project_dir=$(jq -r '.project_dir' "$SESSION_FILE")
            NEW_IDS=$(osascript -e "
                tell application \"Ghostty\"
                    set cfg to new surface configuration
                    set initial working directory of cfg to \"${project_dir}\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    set agentTerm to split viewerTerm direction right with configuration cfg
                    input text \"${AGENT_CMD}\n\" to agentTerm
                    return id of agentTerm
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || {
                echo "idealize: failed to add agent pane" >&2; exit 1
            }
            debug "new agent_id=$NEW_IDS"
            jq --arg a "$NEW_IDS" '.panes.agent = $a' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: agent pane added (${AGENT_CMD})"
        else
            debug "removing agent pane"
            [[ "$AGENT_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid agent id" >&2; exit 1; }
            osascript -e "
                tell application \"Ghostty\"
                    set agentTerm to first terminal whose id is \"${AGENT_ID}\"
                    perform action \"close_surface\" on agentTerm
                end tell
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || true
            jq '.panes.agent = ""' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: agent pane removed"
        fi
        ;;

    *)
        echo "Usage: idealyze toggle tree|agent|preview" >&2
        exit 1
        ;;
esac
