#!/usr/bin/env bash
# Idealize installer
# Usage: curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | bash
#
# Installs idealyze CLI and configures Claude Code hooks.
# Requirements: macOS, Ghostty, broot, bat, claude, jq
# Optional: glow (markdown preview)

set -euo pipefail

REPO="diananerd/idealize"
INSTALL_DIR="${HOME}/.idealyze"
BIN_DIR="${HOME}/.local/bin"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

# --- Helpers ---

info()  { echo "  $*"; }
warn()  { echo "  ⚠ $*" >&2; }
fail()  { echo "idealize: error: $*" >&2; exit 1; }

cleanup_partial() {
    echo ""
    warn "installation failed — cleaning up partial install"
    rm -rf "$INSTALL_DIR"
    rm -f "${BIN_DIR}/idealyze"
    exit 1
}

download() {
    local url="$1" dest="$2"
    if ! curl -fsSL "$url" -o "$dest"; then
        fail "failed to download $(basename "$dest") from ${url}"
    fi
}

# --- Pre-flight checks ---

echo "idealize: checking requirements..."

# Must be macOS
[[ "$(uname -s)" == "Darwin" ]] || fail "idealize requires macOS (uses AppleScript + Ghostty)"

# jq is needed during install for hook configuration
if ! command -v jq &>/dev/null; then
    fail "jq is required for installation. Install it first: brew install jq"
fi

# Check critical runtime dependencies and warn (don't block install)
missing=()
for dep in broot bat claude; do
    command -v "$dep" &>/dev/null || missing+=("$dep")
done

if [[ ! -d "/Applications/Ghostty.app" ]]; then
    missing+=("Ghostty.app")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    warn "missing runtime dependencies: ${missing[*]}"
    warn "idealyze will not run until these are installed"
    echo ""
fi

# --- Download ---

trap cleanup_partial ERR

echo "idealize: downloading files..."

mkdir -p "$INSTALL_DIR"/{lib,config}
mkdir -p "$BIN_DIR"

# Binary
info "bin/idealyze"
download "${BASE_URL}/bin/idealyze" "${BIN_DIR}/idealyze"
chmod +x "${BIN_DIR}/idealyze"

# Lib files
LIB_FILES=(layout.applescript hooks.sh viewer.sh viewer-loop.sh tree.sh toggle.sh)
for f in "${LIB_FILES[@]}"; do
    info "lib/${f}"
    download "${BASE_URL}/lib/${f}" "${INSTALL_DIR}/lib/${f}"
done
chmod +x "${INSTALL_DIR}"/lib/*.sh

# Config
info "config/broot-sidebar.toml"
download "${BASE_URL}/config/broot-sidebar.toml" "${INSTALL_DIR}/config/broot-sidebar.toml"

trap - ERR

# --- Configure Claude hooks ---

echo "idealize: configuring Claude Code hooks..."

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="idealyze --hook post-tool-use"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    if jq -e '.hooks.PostToolUse[]?.hooks[]? | select(.command == "'"$HOOK_CMD"'")' "$CLAUDE_SETTINGS" &>/dev/null; then
        info "hooks already configured — skipping"
    else
        if ! jq --arg cmd "$HOOK_CMD" '
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
        ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp"; then
            rm -f "${CLAUDE_SETTINGS}.tmp"
            fail "failed to update ${CLAUDE_SETTINGS}"
        fi
        mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        info "hooks added to existing settings"
    fi
else
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    jq -n --arg cmd "$HOOK_CMD" '{
        hooks: {
            PostToolUse: [{
                matcher: "Read|Edit|Write|Glob|Grep",
                hooks: [{
                    type: "command",
                    command: $cmd,
                    async: true
                }]
            }]
        }
    }' > "$CLAUDE_SETTINGS"
    info "created ${CLAUDE_SETTINGS} with hooks"
fi

# --- Summary ---

echo ""
echo "idealize: checking dependencies..."

ALL_OK=true
for dep in broot bat claude jq; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "found")
        info "✓ ${dep} (${ver})"
    else
        info "✗ ${dep} — required, please install"
        ALL_OK=false
    fi
done

if [[ -d "/Applications/Ghostty.app" ]]; then
    info "✓ Ghostty"
else
    info "✗ Ghostty — required (macOS only)"
    ALL_OK=false
fi

if command -v glow &>/dev/null; then
    info "○ glow (optional, installed)"
else
    info "○ glow (optional — viewer will use bat)"
fi

# PATH check
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    warn "${BIN_DIR} is not in your PATH. Add it to your shell profile:"
    echo ""
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
    echo ""
fi

echo ""
if [[ "$ALL_OK" == true ]]; then
    echo "idealize: installed! Run 'idealyze' in any project directory."
else
    echo "idealize: installed, but some dependencies are missing."
    echo "         Install them before running idealyze."
fi
