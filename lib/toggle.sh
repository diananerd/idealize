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
        TREE_VISIBLE=$(jq -r '.tree_visible' "$SESSION_FILE")
        TREE_ID=$(jq -r '.panes.tree // ""' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer // ""' "$SESSION_FILE")
        PROJECT_DIR=$(jq -r '.project_dir // ""' "$SESSION_FILE")
        debug "tree_visible=$TREE_VISIBLE tree_id=$TREE_ID viewer_id=$VIEWER_ID"

        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ "$TREE_VISIBLE" == "true" ]]; then
            # Close the tree pane
            debug "closing tree pane"
            [[ "$TREE_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid tree id" >&2; exit 1; }
            osascript -e "
                tell application \"Ghostty\"
                    set treeTerm to first terminal whose id is \"${TREE_ID}\"
                    perform action \"close_surface\" on treeTerm
                end tell
            " >/dev/null 2>"${IDEALYZE_DIR}/osascript-error.log" || true
            jq '.tree_visible = false | .panes.tree = ""' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree hidden"
        else
            # Re-create tree pane by splitting left from viewer
            debug "re-creating tree pane"
            # Resolve broot config path
            BROOT_CONF=""
            if [[ -f "${IDEALYZE_DIR}/config/broot-sidebar.toml" ]]; then
                BROOT_CONF="${IDEALYZE_DIR}/config/broot-sidebar.toml"
            elif [[ -d "$LIB_DIR/../config" ]]; then
                BROOT_CONF="$(cd "$LIB_DIR/../config" && pwd)/broot-sidebar.toml"
            fi
            NEW_TREE_ID=$(osascript -e "
                tell application \"Ghostty\"
                    set cfg to new surface configuration
                    set initial working directory of cfg to \"${PROJECT_DIR}\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    set treeTerm to split viewerTerm direction left with configuration cfg
                    repeat 30 times
                        perform action \"resize_split:left,10\" on treeTerm
                    end repeat
                    input text \"broot --conf ${BROOT_CONF} --listen idealyze ${PROJECT_DIR}\n\" to treeTerm
                    return id of treeTerm
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || {
                echo "idealize: failed to restore tree" >&2; exit 1
            }
            debug "new tree_id=$NEW_TREE_ID"
            jq --arg t "$NEW_TREE_ID" '.tree_visible = true | .panes.tree = $t' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
        fi
        ;;

    render)
        CURRENT_MODE=$(jq -r '.viewer_mode' "$SESSION_FILE")
        VIEWER_ID=$(jq -r '.panes.viewer // ""' "$SESSION_FILE")
        CURRENT_FILE=""
        CURRENT_LINE="1"
        if [[ -f "${IDEALYZE_DIR}/current-file" ]]; then
            CURRENT_FILE=$(sed -n '1p' "${IDEALYZE_DIR}/current-file")
            CURRENT_LINE=$(sed -n '2p' "${IDEALYZE_DIR}/current-file")
            CURRENT_LINE="${CURRENT_LINE:-1}"
        fi
        debug "mode=$CURRENT_MODE file=$CURRENT_FILE line=$CURRENT_LINE viewer_id=$VIEWER_ID"

        [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session" >&2; exit 1; }

        if [[ "$CURRENT_MODE" == "raw" ]]; then
            # Switch to rendered mode
            if command -v glow &>/dev/null; then
                NEW_MODE="glow"
            else
                echo "idealize: glow not installed — rendered mode disabled" >&2
                echo "  install with: brew install glow" >&2
                exit 1
            fi
        else
            # Switch to raw mode
            NEW_MODE="raw"
        fi

        jq --arg m "$NEW_MODE" '.viewer_mode = $m' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

        # Re-render current file with new mode via viewer-cmd
        if [[ -n "$CURRENT_FILE" && -f "$CURRENT_FILE" ]]; then
            VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$CURRENT_FILE" "$CURRENT_LINE" "$NEW_MODE")
            debug "viewer_cmd=$VIEWER_CMD"
            if [[ -n "$VIEWER_CMD" ]]; then
                printf '%s' "$VIEWER_CMD" > "${IDEALYZE_DIR}/viewer-cmd.tmp"
                mv "${IDEALYZE_DIR}/viewer-cmd.tmp" "${IDEALYZE_DIR}/viewer-cmd"
            fi
        fi

        if [[ "$NEW_MODE" == "glow" ]]; then
            echo "idealize: viewer → rendered"
        else
            echo "idealize: viewer → raw"
        fi
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
        echo "Usage: idealyze toggle tree|agent|render" >&2
        exit 1
        ;;
esac
