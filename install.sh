#!/usr/bin/env bash
# Idealize installer
# Usage: curl -fsSL https://raw.githubusercontent.com/diananerd/idealize/main/install.sh | bash
#   or:  ./install.sh --project   (install into current directory's .idealyze/)
#
# Installs idealyze CLI and configures Claude Code hooks.
# Requirements: macOS, Ghostty, broot, bat, claude, jq
# Optional: glow (markdown preview)

set -euo pipefail

REPO="diananerd/idealize"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

# --- Install mode ---

INSTALL_MODE="user"
INSTALL_DIR="${HOME}/.idealyze"
BIN_DIR="${HOME}/.local/bin"

if [[ "${1:-}" == "--project" ]]; then
    INSTALL_MODE="project"
    INSTALL_DIR="$(pwd)/.idealyze"
    BIN_DIR="$(pwd)/.idealyze/bin"
    echo "idealize: installing in project mode → ${INSTALL_DIR}"
else
    echo "idealize: installing in user mode → ${INSTALL_DIR}"
    echo "  (use --project to install into the current directory instead)"
fi

# --- Helpers ---

info()  { echo "  $*"; }
warn()  { echo "  warning: $*" >&2; }
fail()  { echo "idealize: error: $*" >&2; exit 1; }

cleanup_partial() {
    echo ""
    warn "installation failed — cleaning up partial install"
    rm -rf "$INSTALL_DIR"
    [[ "$INSTALL_MODE" == "user" ]] && rm -f "${BIN_DIR}/idealyze"
    exit 1
}

trap cleanup_partial EXIT

download() {
    local url="$1" dest="$2"
    local http_code
    http_code=$(curl -fsSL -w '%{http_code}' "$url" -o "$dest" 2>/dev/null) || true
    if [[ ! -f "$dest" ]] || [[ "$http_code" != "200" ]]; then
        fail "failed to download $(basename "$dest") from ${url} (HTTP ${http_code:-unknown})"
    fi
    # Guard against HTML error pages served with 200 (e.g. corporate proxies)
    if head -1 "$dest" | grep -qi '<!doctype\|<html'; then
        fail "downloaded $(basename "$dest") appears to be an HTML page — check your network/proxy"
    fi
}

# --- Pre-flight checks ---

echo "idealize: checking requirements..."

[[ "$(uname -s)" == "Darwin" ]] || fail "idealize requires macOS (uses AppleScript + Ghostty)"

if ! command -v jq &>/dev/null; then
    fail "jq is required for installation. Install it first: brew install jq"
fi

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

echo "idealize: downloading files..."

mkdir -p "$INSTALL_DIR"/{lib,config}
mkdir -p "$BIN_DIR"

info "bin/idealyze"
download "${BASE_URL}/bin/idealyze" "${BIN_DIR}/idealyze"
chmod +x "${BIN_DIR}/idealyze"

LIB_FILES=(layout.applescript hooks.sh viewer.sh viewer-loop.sh tree.sh toggle.sh)
for f in "${LIB_FILES[@]}"; do
    info "lib/${f}"
    download "${BASE_URL}/lib/${f}" "${INSTALL_DIR}/lib/${f}"
done
chmod +x "${INSTALL_DIR}"/lib/*.sh

info "config/broot-sidebar.toml"
download "${BASE_URL}/config/broot-sidebar.toml" "${INSTALL_DIR}/config/broot-sidebar.toml"

# Store install metadata for uninstall
cat > "${INSTALL_DIR}/.install-meta" <<META
mode=${INSTALL_MODE}
bin_dir=${BIN_DIR}
install_dir=${INSTALL_DIR}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

# --- Configure Claude hooks ---

echo "idealize: configuring Claude Code hooks..."

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

# Use absolute path to hooks.sh for reliability
HOOK_CMD="bash ${INSTALL_DIR}/lib/hooks.sh"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    if ! jq empty "$CLAUDE_SETTINGS" 2>/dev/null; then
        warn "${CLAUDE_SETTINGS} contains invalid JSON — skipping hook configuration"
        warn "fix the JSON manually, then re-run the installer"
    elif jq -e --arg cmd "$HOOK_CMD" \
        '.hooks.PostToolUse[]?.hooks[]? | select(.command == $cmd)' \
        "$CLAUDE_SETTINGS" &>/dev/null; then
        info "hooks already configured — skipping"
    else
        cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.bak"
        if ! jq --arg cmd "$HOOK_CMD" '
            .hooks //= {} |
            .hooks.PostToolUse //= [] |
            .hooks.PostToolUse += [{
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [{
                    "type": "command",
                    "command": $cmd
                }]
            }]
        ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp"; then
            rm -f "${CLAUDE_SETTINGS}.tmp"
            fail "failed to update ${CLAUDE_SETTINGS} (backup at ${CLAUDE_SETTINGS}.bak)"
        fi
        mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        info "hooks added (backup: settings.json.bak)"
    fi
else
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    if ! jq -n --arg cmd "$HOOK_CMD" '{
        hooks: {
            PostToolUse: [{
                matcher: "Read|Edit|Write|Glob|Grep",
                hooks: [{
                    type: "command",
                    command: $cmd
                }]
            }]
        }
    }' > "$CLAUDE_SETTINGS"; then
        fail "failed to create ${CLAUDE_SETTINGS}"
    fi
    info "created ${CLAUDE_SETTINGS} with hooks"
fi

# --- Dependency summary ---

echo ""
echo "idealize: dependency check..."

ALL_OK=true
for dep in broot bat claude jq; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "found")
        info "ok: ${dep} (${ver})"
    else
        info "missing: ${dep}"
        ALL_OK=false
    fi
done

if [[ -d "/Applications/Ghostty.app" ]]; then
    info "ok: Ghostty"
else
    info "missing: Ghostty (macOS only)"
    ALL_OK=false
fi

if command -v glow &>/dev/null; then
    info "ok: glow (optional)"
else
    info "skip: glow (optional — viewer will use bat)"
fi

# PATH check (user mode only)
if [[ "$INSTALL_MODE" == "user" && ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    warn "${BIN_DIR} is not in your PATH. Add it:"
    echo ""
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
    echo ""
fi

# Verify binary works
if [[ -x "${BIN_DIR}/idealyze" ]] && "${BIN_DIR}/idealyze" --version &>/dev/null; then
    info "ok: idealyze binary works"
else
    warn "idealyze was installed but does not execute correctly"
fi

# Clear cleanup trap — success
trap - EXIT

echo ""
if [[ "$ALL_OK" == true ]]; then
    echo "idealize: installed! Run 'idealyze' in any project directory."
else
    echo "idealize: installed, but some dependencies are missing."
fi

if [[ "$INSTALL_MODE" == "project" ]]; then
    echo ""
    echo "  Project install: run .idealyze/bin/idealyze from this directory"
    echo "  Uninstall: idealyze uninstall  (or rm -rf .idealyze/)"
fi
