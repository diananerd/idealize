#!/usr/bin/env bash
# Idealize installer
# Usage: curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | sh

set -euo pipefail

REPO="diananerd/idealize"
INSTALL_DIR="${HOME}/.idealyze"
BIN_DIR="${HOME}/.local/bin"

echo "idealize: installing..."

# Create directories
mkdir -p "$INSTALL_DIR"/{lib,config}
mkdir -p "$BIN_DIR"

# Download files (from main branch)
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

echo "  downloading..."

# Core files
curl -fsSL "${BASE_URL}/bin/idealyze" -o "${BIN_DIR}/idealyze"
chmod +x "${BIN_DIR}/idealyze"

# Lib files
for f in layout.applescript hooks.sh viewer.sh tree.sh toggle.sh; do
    curl -fsSL "${BASE_URL}/lib/${f}" -o "${INSTALL_DIR}/lib/${f}"
    chmod +x "${INSTALL_DIR}/lib/${f}" 2>/dev/null || true
done

# Config files
curl -fsSL "${BASE_URL}/config/broot-sidebar.toml" -o "${INSTALL_DIR}/config/broot-sidebar.toml"

# Merge Claude hooks into settings
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="idealyze --hook post-tool-use"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # Check if hook already exists
    if jq -e '.hooks.PostToolUse[]?.hooks[]? | select(.command == "'"$HOOK_CMD"'")' "$CLAUDE_SETTINGS" &>/dev/null; then
        echo "  claude hooks already configured"
    else
        # Merge: add our hook entry to PostToolUse array
        jq --arg cmd "$HOOK_CMD" '
            .hooks //= {} |
            .hooks.PostToolUse //= [] |
            .hooks.PostToolUse += [{
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [{
                    "type": "command",
                    "command": $cmd,
                    "async": true
                }]
            }]
        ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" \
            && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        echo "  claude hooks configured"
    fi
else
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cat > "$CLAUDE_SETTINGS" <<HOOKSEOF
{
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [
                    {
                        "type": "command",
                        "command": "${HOOK_CMD}",
                        "async": true
                    }
                ]
            }
        ]
    }
}
HOOKSEOF
    echo "  claude hooks configured (new settings file)"
fi

# Check dependencies
echo ""
echo "  dependencies:"
for dep in broot bat claude jq; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "found")
        echo "    ✓ ${dep} (${ver})"
    else
        echo "    ✗ ${dep} — required, please install"
    fi
done

# Ghostty check
if [[ -d "/Applications/Ghostty.app" ]]; then
    echo "    ✓ ghostty"
else
    echo "    ✗ ghostty — required (macOS only)"
fi

# Optional: glow
if command -v glow &>/dev/null; then
    echo "    ✓ glow (optional)"
else
    echo "    ○ glow (optional — preview mode will use bat)"
fi

# Check PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠ ${BIN_DIR} is not in your PATH. Add it:"
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
fi

echo ""
echo "idealize: installed! Run 'idealyze' in any project directory."
