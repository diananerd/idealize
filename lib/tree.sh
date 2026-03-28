#!/usr/bin/env bash
# lib/tree.sh — Send navigation commands to broot sidebar
# Usage: tree.sh select <file_path>
#        tree.sh focus <directory_path>

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

SOCKET_NAME=$(cfg "broot_socket" "idealyze")
ACTION="${1:-}"
TARGET="${2:-}"
DEBUG_LOG="${HOME}/.idealyze/debug.log"

debug() {
    [[ -d "${HOME}/.idealyze" ]] && echo "[tree  $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    echo "idealize: tree.sh requires action and target arguments" >&2
    exit 1
fi

# Check if broot socket exists
if [[ ! -S "/tmp/broot-server-${SOCKET_NAME}.sock" ]]; then
    debug "socket not found: /tmp/broot-server-${SOCKET_NAME}.sock"
    echo "idealize: broot sidebar not running (socket not found)" >&2
    exit 1
fi

debug "action=$ACTION target=$TARGET"

case "$ACTION" in
    select)
        filename=$(basename "$TARGET")
        debug "broot --send $SOCKET_NAME -c ':escape;${filename}'"
        broot --send "$SOCKET_NAME" -c ":escape;${filename}" 2>>"$DEBUG_LOG" || { echo "idealize: broot select failed for $TARGET" >&2; exit 1; }
        ;;
    focus)
        debug "broot --send $SOCKET_NAME -c ':focus ${TARGET}'"
        broot --send "$SOCKET_NAME" -c ":focus ${TARGET}" 2>>"$DEBUG_LOG" || { echo "idealize: broot focus failed for $TARGET" >&2; exit 1; }
        ;;
    *)
        echo "idealize: tree.sh unknown action: $ACTION (expected: select|focus)" >&2
        exit 1
        ;;
esac
