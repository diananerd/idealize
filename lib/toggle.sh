#!/usr/bin/env bash
# lib/toggle.sh — Toggle tree sidebar or preview mode
# Usage: toggle.sh tree | toggle.sh preview

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[toggl $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

# Send WINCH to viewer-loop to force re-render after pane size changes
notify_viewer_resize() {
    local pid_file="${IDEALYZE_DIR}/viewer-loop.pid"
    if [[ -f "$pid_file" ]]; then
        local vpid
        vpid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$vpid" ]] && kill -0 "$vpid" 2>/dev/null; then
            # Small delay for pane resize to settle, then signal
            (sleep "$(cfg layout.resize_settle_delay 0.5)" && kill -WINCH "$vpid" 2>/dev/null) &
        fi
    fi
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
        WIN_ID=$(jq -r '.panes.window // ""' "$SESSION_FILE")
        PROJECT_DIR=$(jq -r '.project_dir // ""' "$SESSION_FILE")
        debug "tree_visible=$TREE_VISIBLE tree_id=$TREE_ID viewer_id=$VIEWER_ID win=$WIN_ID"

        [[ "$WIN_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session (no window)" >&2; exit 1; }

        if [[ "$TREE_VISIBLE" == "true" ]]; then
            debug "closing tree pane"
            [[ "$TREE_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid tree id" >&2; exit 1; }
            # Close tree, then re-read viewer ID from Ghostty (IDs may change after close)
            NEW_VIEWER_ID=$(osascript -e "
                tell application \"Ghostty\"
                    set treeTerm to first terminal whose id is \"${TREE_ID}\"
                    perform action \"close_surface\" on treeTerm
                    delay 0.3
                    set w to first window whose id is \"${WIN_ID}\"
                    return id of terminal 1 of selected tab of w
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || true
            debug "new viewer_id after tree close: $NEW_VIEWER_ID"
            if [[ -n "$NEW_VIEWER_ID" ]]; then
                jq --arg v "$NEW_VIEWER_ID" '.tree_visible = false | .panes.tree = "" | .panes.viewer = $v' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            else
                jq '.tree_visible = false | .panes.tree = ""' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            fi
            echo "idealize: tree hidden"
            notify_viewer_resize
        else
            debug "re-creating tree pane"
            # Re-read viewer ID fresh from Ghostty
            VIEWER_ID=$(osascript -e "
                tell application \"Ghostty\"
                    set w to first window whose id is \"${WIN_ID}\"
                    return id of terminal 1 of selected tab of w
                end tell
            " 2>/dev/null) || true
            debug "fresh viewer_id: $VIEWER_ID"
            [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: cannot find viewer pane" >&2; exit 1; }

            BROOT_CONF=""
            if [[ -f "${IDEALYZE_DIR}/config/broot-sidebar.toml" ]]; then
                BROOT_CONF="${IDEALYZE_DIR}/config/broot-sidebar.toml"
            elif [[ -d "$LIB_DIR/../config" ]]; then
                BROOT_CONF="$(cd "$LIB_DIR/../config" && pwd)/broot-sidebar.toml"
            fi
            shrink_restore=$(cfg_int "layout.tree_shrink_restore" "30")
            step=$(cfg_int "layout.resize_step" "10")
            broot_socket=$(cfg "broot_socket" "idealyze")
            RESULT=$(osascript -e "
                tell application \"Ghostty\"
                    set cfg to new surface configuration
                    set initial working directory of cfg to \"${PROJECT_DIR}\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    set treeTerm to split viewerTerm direction left with configuration cfg
                    repeat ${shrink_restore} times
                        perform action \"resize_split:left,${step}\" on treeTerm
                    end repeat
                    input text \"broot --conf ${BROOT_CONF} --listen ${broot_socket} ${PROJECT_DIR}\n\" to treeTerm
                    return (id of treeTerm) & \"|\" & (id of viewerTerm)
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || {
                echo "idealize: failed to restore tree" >&2; exit 1
            }
            NEW_TREE_ID="${RESULT%%|*}"
            NEW_VIEWER_ID="${RESULT##*|}"
            debug "new tree_id=$NEW_TREE_ID viewer_id=$NEW_VIEWER_ID"
            jq --arg t "$NEW_TREE_ID" --arg v "$NEW_VIEWER_ID" '.tree_visible = true | .panes.tree = $t | .panes.viewer = $v' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: tree restored"
            notify_viewer_resize
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
        AGENT_ID=$(jq -r '.panes.agent // ""' "$SESSION_FILE")
        WIN_ID=$(jq -r '.panes.window // ""' "$SESSION_FILE")
        AGENT_CMD=$(cfg "agent_cmd" "claude")
        debug "agent_id=$AGENT_ID win=$WIN_ID agent_cmd=$AGENT_CMD"

        [[ "$WIN_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid session (no window)" >&2; exit 1; }

        if [[ -z "$AGENT_ID" ]]; then
            debug "adding agent pane (cmd=$AGENT_CMD)"
            project_dir=$(jq -r '.project_dir' "$SESSION_FILE")
            # Read fresh viewer ID from Ghostty
            VIEWER_ID=$(osascript -e "
                tell application \"Ghostty\"
                    set w to first window whose id is \"${WIN_ID}\"
                    -- Get the last terminal (rightmost = viewer when no agent)
                    set terms to terminals of selected tab of w
                    return id of last item of terms
                end tell
            " 2>/dev/null) || true
            debug "fresh viewer_id=$VIEWER_ID"
            [[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: cannot find viewer pane" >&2; exit 1; }

            RESULT=$(osascript -e "
                tell application \"Ghostty\"
                    set cfg to new surface configuration
                    set initial working directory of cfg to \"${project_dir}\"
                    set viewerTerm to first terminal whose id is \"${VIEWER_ID}\"
                    set agentTerm to split viewerTerm direction right with configuration cfg
                    input text \"${AGENT_CMD}\n\" to agentTerm
                    return (id of agentTerm) & \"|\" & (id of viewerTerm)
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || {
                echo "idealize: failed to add agent pane" >&2; exit 1
            }
            NEW_AGENT_ID="${RESULT%%|*}"
            NEW_VIEWER_ID="${RESULT##*|}"
            debug "new agent_id=$NEW_AGENT_ID viewer_id=$NEW_VIEWER_ID"
            jq --arg a "$NEW_AGENT_ID" --arg v "$NEW_VIEWER_ID" '.panes.agent = $a | .panes.viewer = $v' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            echo "idealize: agent pane added (${AGENT_CMD})"
            notify_viewer_resize
        else
            debug "removing agent pane"
            [[ "$AGENT_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { echo "idealize: invalid agent id" >&2; exit 1; }
            NEW_VIEWER_ID=$(osascript -e "
                tell application \"Ghostty\"
                    set agentTerm to first terminal whose id is \"${AGENT_ID}\"
                    perform action \"close_surface\" on agentTerm
                    delay 0.3
                    set w to first window whose id is \"${WIN_ID}\"
                    -- After closing agent, the last terminal is viewer
                    set terms to terminals of selected tab of w
                    return id of last item of terms
                end tell
            " 2>"${IDEALYZE_DIR}/osascript-error.log") || true
            debug "viewer_id after agent close: $NEW_VIEWER_ID"
            if [[ -n "$NEW_VIEWER_ID" ]]; then
                jq --arg v "$NEW_VIEWER_ID" '.panes.agent = "" | .panes.viewer = $v' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            else
                jq '.panes.agent = ""' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
            fi
            echo "idealize: agent pane removed"
            notify_viewer_resize
        fi
        ;;

    *)
        echo "Usage: idealyze toggle tree|agent|render" >&2
        exit 1
        ;;
esac
