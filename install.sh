#!/usr/bin/env bash
# Idealize installer
# Usage: curl -fsSL https://idealize.diananerd.com/install | bash
#
# Flags:
#   --user      Install for current user (default)
#   --project   Install into current directory
#   --auto      Non-interactive mode — installs everything including optionals
#   --beta      Install from beta channel instead of stable
#
# Interactive installer with dependency management, colored output, and smart defaults.

set -eo pipefail

REPO="diananerd/idealize"

# Release channel: --beta downloads from beta tag, default is latest (stable)
CHANNEL="latest"
for arg in "$@"; do [[ "$arg" == "--beta" ]] && CHANNEL="beta"; done

BASE_URL="https://raw.githubusercontent.com/${REPO}/${CHANNEL}"

# Parse flags from all args
AUTO=false
ARG_PROJECT=false
ARG_USER=false
for arg in "$@"; do
    case "$arg" in
        --auto) AUTO=true ;;
        --project) ARG_PROJECT=true ;;
        --user) ARG_USER=true ;;
        --beta) ;; # handled by CHANNEL
    esac
done

# --- Colors ---

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RED='\033[31m'
    CYAN='\033[36m'
    BLUE='\033[34m'
    RESET='\033[0m'
else
    BOLD='' DIM='' GREEN='' YELLOW='' RED='' CYAN='' BLUE='' RESET=''
fi

# --- Helpers ---

header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
step()    { echo -e "  ${CYAN}>${RESET} $*"; }
ok()      { echo -e "  ${GREEN}ok${RESET}  $*"; }
skip()    { echo -e "  ${DIM}--${RESET}  $*"; }
missing() { echo -e "  ${RED}!!${RESET}  $*"; }
warn()    { echo -e "  ${YELLOW}!!${RESET}  $*"; }
fail()    { echo -e "\n${RED}error:${RESET} $*" >&2; exit 1; }

_has_tty() { [[ -t 0 ]] || [[ -c /dev/tty ]]; }

ask() {
    local prompt="$1" default="${2:-}" reply
    if [[ "$AUTO" == true ]] || ! _has_tty; then echo "$default"; return; fi
    if [[ -n "$default" ]]; then
        echo -en "  ${CYAN}?${RESET} ${prompt} ${DIM}[${default}]${RESET} " >&2
    else
        echo -en "  ${CYAN}?${RESET} ${prompt} " >&2
    fi
    read -r reply </dev/tty 2>/dev/null || reply=""
    echo "${reply:-$default}"
}

ask_yn() {
    local prompt="$1" default="${2:-y}" reply
    if [[ "$AUTO" == true ]] || ! _has_tty; then [[ "$default" == "y" ]]; return; fi
    if [[ "$default" == "y" ]]; then
        echo -en "  ${CYAN}?${RESET} ${prompt} ${DIM}[Y/n]${RESET} " >&2
    else
        echo -en "  ${CYAN}?${RESET} ${prompt} ${DIM}[y/N]${RESET} " >&2
    fi
    read -r reply </dev/tty 2>/dev/null || reply=""
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# --- Banner ---

echo ""
echo -e "${BOLD}  idealize${RESET} ${DIM}— terminal IDE companion for AI coding agents${RESET}"
echo -e "${DIM}  https://github.com/diananerd/idealize${RESET}"
echo ""

# --- System checks ---

[[ "$(uname -s)" == "Darwin" ]] || fail "idealize requires macOS"
command -v curl &>/dev/null || fail "curl is required"
command -v jq &>/dev/null || fail "jq is required (brew install jq)"

# --- Install mode ---

header "Install location"

if [[ "$ARG_PROJECT" == true ]]; then
    INSTALL_MODE="project"
elif [[ "$ARG_USER" == true ]] || [[ "$AUTO" == true ]]; then
    INSTALL_MODE="user"
else
    echo ""
    echo -e "  ${BOLD}1${RESET}) User install ${DIM}— available everywhere (~/.idealyze)${RESET}"
    echo -e "  ${BOLD}2${RESET}) Project install ${DIM}— this directory only (.idealyze/)${RESET}"
    echo ""
    mode_choice=$(ask "Choose [1/2]" "1")
    if [[ "$mode_choice" == "2" ]]; then
        INSTALL_MODE="project"
    else
        INSTALL_MODE="user"
    fi
fi

if [[ "$INSTALL_MODE" == "project" ]]; then
    INSTALL_DIR="$(pwd)/.idealyze"
    BIN_DIR="$(pwd)/.idealyze/bin"
    step "project: ${BOLD}${INSTALL_DIR}${RESET}"
else
    INSTALL_MODE="user"
    INSTALL_DIR="${HOME}/.idealyze"
    BIN_DIR="${HOME}/.local/bin"
    step "user: ${BOLD}${INSTALL_DIR}${RESET}"
fi

# Writable check
mkdir -p "$BIN_DIR" 2>/dev/null || fail "cannot write to ${BIN_DIR}"
mkdir -p "$INSTALL_DIR" 2>/dev/null || fail "cannot write to ${INSTALL_DIR}"

# Connectivity check
step "checking connectivity..."
if ! curl -fsSL --max-time 5 "${BASE_URL}/bin/idealyze" -o /dev/null 2>/dev/null; then
    fail "cannot reach GitHub — check your network"
fi
ok "GitHub reachable"

# --- Cleanup trap ---

cleanup_partial() {
    echo ""
    warn "installation interrupted — cleaning up"
    rm -rf "$INSTALL_DIR"
    [[ "$INSTALL_MODE" == "user" ]] && rm -f "${BIN_DIR}/idealyze"
    exit 1
}
trap cleanup_partial EXIT

# --- Dependency check ---

header "Checking dependencies"

HAS_BREW=false
command -v brew &>/dev/null && HAS_BREW=true

REQUIRED_DEPS=(jq broot bat)
OPTIONAL_DEPS=(glow)
MISSING_REQUIRED=()
MISSING_OPTIONAL=()

# Check Ghostty
if [[ -d "/Applications/Ghostty.app" ]]; then
    ok "Ghostty ${DIM}(required)${RESET}"
else
    missing "Ghostty ${DIM}— download from https://ghostty.org${RESET}"
    MISSING_REQUIRED+=("Ghostty")
fi

# Check required deps
for dep in "${REQUIRED_DEPS[@]}"; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "installed")
        ok "${dep} ${DIM}${ver}${RESET}"
    else
        missing "${dep} ${DIM}(required)${RESET}"
        MISSING_REQUIRED+=("$dep")
    fi
done

# Check optional deps
for dep in "${OPTIONAL_DEPS[@]}"; do
    if command -v "$dep" &>/dev/null; then
        ver=$("$dep" --version 2>/dev/null | head -1 || echo "installed")
        ok "${dep} ${DIM}${ver} (optional)${RESET}"
    else
        skip "${dep} ${DIM}(optional — enables rendered markdown preview)${RESET}"
        MISSING_OPTIONAL+=("$dep")
    fi
done

# --- Install missing required deps ---

brew_installable=()
if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
    for dep in "${MISSING_REQUIRED[@]}"; do
        [[ "$dep" != "Ghostty" ]] && brew_installable+=("$dep")
    done
fi

if [[ ${#brew_installable[@]} -gt 0 ]]; then
    echo ""
    if [[ "$HAS_BREW" == true ]]; then
        if ask_yn "Install missing required dependencies via brew? (${brew_installable[*]})" "y"; then
            for dep in "${brew_installable[@]}"; do
                step "installing ${BOLD}${dep}${RESET}..."
                if brew install "$dep" </dev/null >/dev/null 2>&1; then
                    ok "${dep} installed"
                    # Remove from missing list
                    MISSING_REQUIRED=("${MISSING_REQUIRED[@]/$dep/}")
                else
                    warn "failed to install ${dep}"
                fi
            done
        fi
    else
        warn "brew not found — install missing deps manually: ${brew_installable[*]}"
    fi
fi

# --- Install missing optional deps ---

if [[ "${#MISSING_OPTIONAL[@]}" -gt 0 && "$HAS_BREW" == true ]]; then
    opt_default="n"
    [[ "$AUTO" == true ]] && opt_default="y"
    if ask_yn "Install optional dependencies? (${MISSING_OPTIONAL[*]})" "$opt_default"; then
        for dep in "${MISSING_OPTIONAL[@]}"; do
            step "installing ${BOLD}${dep}${RESET}..."
            if brew install "$dep" </dev/null >/dev/null 2>&1; then
                ok "${dep} installed"
            else
                warn "failed to install ${dep} — skipping"
            fi
        done
    fi
fi

# --- Abort if critical deps still missing ---

# Recheck after install attempts
still_missing=()
for dep in jq broot bat; do
    command -v "$dep" &>/dev/null || still_missing+=("$dep")
done
[[ ! -d "/Applications/Ghostty.app" ]] && still_missing+=("Ghostty")

if [[ ${#still_missing[@]} -gt 0 ]]; then
    echo ""
    warn "still missing: ${still_missing[*]}"
    if [[ "$AUTO" != true ]] && ! ask_yn "Continue installing idealyze anyway?" "n"; then
        echo -e "\n${DIM}  Install dependencies first, then re-run the installer.${RESET}"
        trap - EXIT
        exit 0
    fi
fi

# --- Download ---

header "Downloading idealyze"

download() {
    local url="$1" dest="$2" label="$3"
    local http_code
    http_code=$(curl -fsSL -w '%{http_code}' "$url" -o "$dest" 2>/dev/null) || true
    if [[ ! -f "$dest" ]] || [[ "$http_code" != "200" ]]; then
        fail "failed to download ${label} (HTTP ${http_code:-unknown})"
    fi
    if head -1 "$dest" 2>/dev/null | grep -qi '<!doctype\|<html'; then
        fail "${label} appears to be an HTML page — check your network/proxy"
    fi
    ok "${label}"
}

mkdir -p "$INSTALL_DIR"/{lib,config}
mkdir -p "$BIN_DIR"

download "${BASE_URL}/bin/idealyze" "${BIN_DIR}/idealyze" "bin/idealyze"
chmod +x "${BIN_DIR}/idealyze"

LIB_FILES=(layout.applescript hooks.sh viewer.sh viewer-loop.sh tree.sh toggle.sh)
for f in "${LIB_FILES[@]}"; do
    download "${BASE_URL}/lib/${f}" "${INSTALL_DIR}/lib/${f}" "lib/${f}"
done
chmod +x "${INSTALL_DIR}"/lib/*.sh

download "${BASE_URL}/config/broot-sidebar.toml" "${INSTALL_DIR}/config/broot-sidebar.toml" "config/broot-sidebar.toml"
download "${BASE_URL}/config/glow-style.json" "${INSTALL_DIR}/config/glow-style.json" "config/glow-style.json"

# Config loader
download "${BASE_URL}/lib/config.sh" "${INSTALL_DIR}/lib/config.sh" "lib/config.sh"
download "${BASE_URL}/lib/config-defaults.json" "${INSTALL_DIR}/lib/config-defaults.json" "lib/config-defaults.json"

# Providers
mkdir -p "${INSTALL_DIR}/lib/providers"
download "${BASE_URL}/lib/providers/claude-code.sh" "${INSTALL_DIR}/lib/providers/claude-code.sh" "lib/providers/claude-code.sh"
chmod +x "${INSTALL_DIR}/lib/providers/"*.sh

# Store install metadata
cat > "${INSTALL_DIR}/.install-meta" <<META
mode=${INSTALL_MODE}
channel=${CHANNEL}
bin_dir=${BIN_DIR}
install_dir=${INSTALL_DIR}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

# --- Configure hooks ---

header "Configuring hooks"

# Source the provider for hook configuration
source "${INSTALL_DIR}/lib/providers/claude-code.sh"

if provider_is_installed; then
    ok "$(provider_name) detected"
    if ask_yn "Set up $(provider_name) hooks? (required for file tracking)" "y"; then
        HOOK_CMD="bash ${INSTALL_DIR}/lib/hooks.sh"
        if [[ "$INSTALL_MODE" == "project" && -d ".claude" ]]; then
            hook_mode="project"
            step "using project-level settings"
        else
            hook_mode="user"
        fi
        if provider_install_hooks "$HOOK_CMD" "$hook_mode"; then
            ok "hooks configured"
        else
            warn "failed to configure hooks"
        fi
    else
        skip "hooks — skipped"
    fi
else
    skip "$(provider_name) not found — install it later and run 'idealyze doctor'"
fi

# --- Ghostty config ---

header "Ghostty configuration"

ghostty_conf="${HOME}/.config/ghostty/config"
if [[ -f "$ghostty_conf" ]] && grep -q 'confirm-close-surface.*=.*false' "$ghostty_conf"; then
    ok "close confirmation already disabled"
else
    if ask_yn "Disable close confirmation in Ghostty? (recommended for toggling panes)" "y"; then
        mkdir -p "$(dirname "$ghostty_conf")"
        if [[ -f "$ghostty_conf" ]] && grep -q 'confirm-close-surface' "$ghostty_conf"; then
            sed -i '' 's/^confirm-close-surface.*/confirm-close-surface = false/' "$ghostty_conf"
        else
            echo "confirm-close-surface = false" >> "$ghostty_conf"
        fi
        # Reload running Ghostty windows so the change takes effect immediately
        osascript -e 'tell application "Ghostty"
            if (count of windows) > 0 then
                repeat with w in windows
                    perform action "reload_config" on terminal 1 of selected tab of w
                end repeat
            end if
        end tell' &>/dev/null || true
        ok "confirm-close-surface = false (applied)"
    else
        skip "close confirmation — kept as default"
    fi
fi

# --- PATH check ---

if [[ "$INSTALL_MODE" == "user" && ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    header "PATH setup"
    warn "${BIN_DIR} is not in your PATH"
    echo ""
    echo -e "  Add this to your shell profile ${DIM}(~/.zshrc or ~/.bashrc)${RESET}:"
    echo ""
    echo -e "    ${BOLD}export PATH=\"${BIN_DIR}:\$PATH\"${RESET}"
    echo ""
fi

# --- Verify ---

header "Verifying installation"

if [[ -x "${BIN_DIR}/idealyze" ]] && "${BIN_DIR}/idealyze" --version &>/dev/null; then
    ver=$("${BIN_DIR}/idealyze" --version 2>/dev/null)
    ok "${ver}"
else
    warn "binary installed but not working — check ${BIN_DIR}/idealyze"
fi

# Clear cleanup trap — success
trap - EXIT

# --- Done ---

echo ""
echo -e "${GREEN}${BOLD}  Done!${RESET}"
echo ""
if [[ "$INSTALL_MODE" == "project" ]]; then
    # Create a convenience wrapper in the project root
    if [[ ! -f "./idealyze" ]]; then
        cat > "./idealyze" <<'WRAPPER'
#!/usr/bin/env bash
exec "$(dirname "$0")/.idealyze/bin/idealyze" "$@"
WRAPPER
        chmod +x "./idealyze"
    fi
    echo -e "  Run ${BOLD}./idealyze${RESET} from this directory"
    echo -e "  ${DIM}Uninstall: ./idealyze uninstall${RESET}"
else
    echo -e "  Run ${BOLD}idealyze${RESET} in any project directory"
    echo -e "  ${DIM}Uninstall: idealyze uninstall${RESET}"
fi
echo ""

