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
    echo "[tree  $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG"
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
        filename=$(basename "$TARGET")
        debug "broot --send $SOCKET_NAME -c ':escape;${filename}'"
        broot --send "$SOCKET_NAME" -c ":escape;${filename}" 2>>"$DEBUG_LOG" || debug "broot send failed"
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
