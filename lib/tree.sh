#!/usr/bin/env bash
# lib/tree.sh — Send navigation commands to broot sidebar
# Usage: tree.sh select <file_path>
#        tree.sh focus <directory_path>

set -euo pipefail

SOCKET_NAME="idealyze"
ACTION="${1:-}"
TARGET="${2:-}"
DEBUG_LOG="${HOME}/.idealyze/debug.log"

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[tree  $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    debug "missing action or target, exiting"
    exit 0
fi

# Check if broot socket exists
if [[ ! -S "/tmp/broot-server-${SOCKET_NAME}.sock" ]]; then
    debug "socket not found: /tmp/broot-server-${SOCKET_NAME}.sock"
    exit 0
fi

debug "action=$ACTION target=$TARGET"

case "$ACTION" in
    select)
        # Navigate to the file's parent directory, then select the file
        # Uses -c flag (required for sending commands) and ; to chain commands
        parent_dir=$(dirname "$TARGET")
        filename=$(basename "$TARGET")
        debug "broot --send $SOCKET_NAME -c ':focus ${parent_dir};:select ${filename}'"
        broot --send "$SOCKET_NAME" -c ":focus ${parent_dir};:select ${filename}" 2>>"$DEBUG_LOG" || debug "broot send failed"
        ;;
    focus)
        debug "broot --send $SOCKET_NAME -c ':focus ${TARGET}'"
        broot --send "$SOCKET_NAME" -c ":focus ${TARGET}" 2>>"$DEBUG_LOG" || debug "broot send failed"
        ;;
    *)
        debug "unknown action: $ACTION"
        exit 0
        ;;
esac
