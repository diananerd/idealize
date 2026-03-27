#!/usr/bin/env bash
# lib/tree.sh — Send navigation commands to broot sidebar
# Usage: tree.sh select <file_path>
#        tree.sh focus <directory_path>

set -euo pipefail

SOCKET_NAME="idealyze"
ACTION="${1:-}"
TARGET="${2:-}"

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    exit 0
fi

# Check if broot socket exists
if [[ ! -S "/tmp/broot-server-${SOCKET_NAME}.sock" ]]; then
    exit 0
fi

case "$ACTION" in
    select)
        # Navigate to the file's parent directory, then select the file
        # Uses -c flag (required for sending commands) and ; to chain commands
        parent_dir=$(dirname "$TARGET")
        filename=$(basename "$TARGET")
        broot --send "$SOCKET_NAME" -c ":focus ${parent_dir};:select ${filename}" 2>/dev/null || true
        ;;
    focus)
        broot --send "$SOCKET_NAME" -c ":focus ${TARGET}" 2>/dev/null || true
        ;;
    *)
        exit 0
        ;;
esac
