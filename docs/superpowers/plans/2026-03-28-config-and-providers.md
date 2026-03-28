# Centralized Config + Multi-Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all hardcoded values into a JSON config system with project/user resolution, and make the hook system provider-pluggable.

**Architecture:** A config loader (`lib/config.sh`) reads JSON from `.idealyze/config.json` (project) then `~/.idealyze/config.json` (user) then `lib/config-defaults.json` (built-in), merging them with jq. A provider interface (`lib/providers/<name>.sh`) encapsulates all provider-specific logic (hook install/remove/check/parse). All scripts source config.sh and use `cfg` function instead of hardcoded values.

**Tech Stack:** bash, jq, osascript

---

### Task 1: Config Defaults + Loader

**Files:**
- Create: `lib/config-defaults.json`
- Create: `lib/config.sh`

- [ ] **Step 1: Create config-defaults.json**

```json
{
  "provider": "claude-code",
  "agent_cmd": "claude",
  "scope": "project",
  "broot_socket": "idealyze",
  "viewer": {
    "mode": "raw",
    "poll_interval": 0.3,
    "highlight_color": "40;40;160",
    "highlight_color_source": "51;51;51",
    "bat_style": "numbers,header,grid"
  },
  "layout": {
    "tree_shrink_2pane": 30,
    "tree_shrink_3pane": 13,
    "tree_shrink_restore": 30,
    "resize_step": 10,
    "resize_settle_delay": 0.5,
    "dimension_stabilize_retries": 10
  },
  "updates": {
    "check_timeout": 3,
    "channel": "latest"
  }
}
```

- [ ] **Step 2: Create lib/config.sh**

```bash
#!/usr/bin/env bash
# lib/config.sh — Centralized config loader
# Source this file, then call config_load. Use cfg "key.path" to read values.

IDEALYZE_DIR="${HOME}/.idealyze"
_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RESOLVED_CONFIG=""

config_load() {
    local defaults="${_CONFIG_DIR}/config-defaults.json"
    local user_conf="${IDEALYZE_DIR}/config.json"
    local project_conf="$(pwd)/.idealyze/config.json"

    # Start with defaults
    _RESOLVED_CONFIG=$(cat "$defaults")

    # Merge user config if exists
    if [[ -f "$user_conf" ]] && jq empty "$user_conf" 2>/dev/null; then
        _RESOLVED_CONFIG=$(echo "$_RESOLVED_CONFIG" | jq --slurpfile u "$user_conf" '. * $u[0]')
    fi

    # Merge project config if exists (highest priority)
    if [[ -f "$project_conf" ]] && jq empty "$project_conf" 2>/dev/null; then
        _RESOLVED_CONFIG=$(echo "$_RESOLVED_CONFIG" | jq --slurpfile p "$project_conf" '. * $p[0]')
    fi

    # Override from install metadata channel if present
    if [[ -f "${IDEALYZE_DIR}/.install-meta" ]]; then
        local meta_channel
        meta_channel=$(grep '^channel=' "${IDEALYZE_DIR}/.install-meta" 2>/dev/null | cut -d= -f2)
        if [[ -n "$meta_channel" ]]; then
            _RESOLVED_CONFIG=$(echo "$_RESOLVED_CONFIG" | jq --arg c "$meta_channel" '.updates.channel = $c')
        fi
    fi
}

cfg() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(echo "$_RESOLVED_CONFIG" | jq -r ".${key} // empty" 2>/dev/null)
    echo "${val:-$default}"
}

cfg_int() {
    local key="$1"
    local default="${2:-0}"
    local val
    val=$(echo "$_RESOLVED_CONFIG" | jq -r ".${key} // empty" 2>/dev/null)
    echo "${val:-$default}"
}
```

- [ ] **Step 3: Verify config loader works**

Run:
```bash
source lib/config.sh && config_load && echo "provider=$(cfg provider)" && echo "tree_shrink=$(cfg layout.tree_shrink_2pane)" && echo "mode=$(cfg viewer.mode)"
```
Expected: `provider=claude-code`, `tree_shrink=30`, `mode=raw`

- [ ] **Step 4: Test project override**

Run:
```bash
mkdir -p .idealyze && echo '{"viewer":{"mode":"glow"}}' > .idealyze/config.json
source lib/config.sh && config_load && echo "mode=$(cfg viewer.mode)"
rm .idealyze/config.json
```
Expected: `mode=glow`

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh lib/config-defaults.json
git commit -m "feat: add centralized JSON config loader with project/user/default resolution"
```

---

### Task 2: Claude Code Provider

**Files:**
- Create: `lib/providers/claude-code.sh`

- [ ] **Step 1: Create providers directory and claude-code.sh**

```bash
#!/usr/bin/env bash
# lib/providers/claude-code.sh — Claude Code provider
# Implements the provider interface for Claude Code hook integration.

provider_name() { echo "Claude Code"; }

provider_default_agent_cmd() { echo "claude"; }

provider_is_installed() {
    command -v claude &>/dev/null
}

provider_settings_path() {
    local mode="${1:-user}"
    if [[ "$mode" == "project" && -d "$(pwd)/.claude" ]]; then
        echo "$(pwd)/.claude/settings.json"
    else
        echo "${HOME}/.claude/settings.json"
    fi
}

provider_check_hooks() {
    local settings
    settings=$(provider_settings_path "$1")
    [[ -f "$settings" ]] && jq -e '.hooks.PostToolUse[]?.hooks[]? | select(.command | test("hooks\\.sh"))' "$settings" &>/dev/null
}

provider_install_hooks() {
    local hook_cmd="$1"
    local mode="${2:-user}"
    local settings
    settings=$(provider_settings_path "$mode")

    if [[ -f "$settings" ]]; then
        if ! jq empty "$settings" 2>/dev/null; then
            echo "error: ${settings} has invalid JSON" >&2
            return 1
        fi
        if jq -e --arg cmd "$hook_cmd" \
            '.hooks.PostToolUse[]?.hooks[]? | select(.command == $cmd)' \
            "$settings" &>/dev/null; then
            return 0  # already configured
        fi
        cp "$settings" "${settings}.bak"
        jq --arg cmd "$hook_cmd" '
            .hooks //= {} |
            .hooks.PostToolUse //= [] |
            .hooks.PostToolUse += [{
                "matcher": "Read|Edit|Write|Glob|Grep",
                "hooks": [{ "type": "command", "command": $cmd }]
            }]
        ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    else
        mkdir -p "$(dirname "$settings")"
        jq -n --arg cmd "$hook_cmd" '{
            hooks: { PostToolUse: [{
                matcher: "Read|Edit|Write|Glob|Grep",
                hooks: [{ type: "command", command: $cmd }]
            }] }
        }' > "$settings"
    fi
}

provider_remove_hooks() {
    local mode="${1:-user}"
    local settings
    settings=$(provider_settings_path "$mode")
    [[ -f "$settings" ]] || return 0

    cp "$settings" "${settings}.bak"
    jq 'if .hooks.PostToolUse then
        .hooks.PostToolUse |= map(
            select(.hooks | all(.command | test("idealyze|idealize|hooks\\.sh") | not))
        ) |
        if .hooks.PostToolUse | length == 0 then del(.hooks.PostToolUse) else . end |
        if .hooks | length == 0 then del(.hooks) else . end
    else . end' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
}

provider_parse_event() {
    local json="$1"
    local tool_name file_path line_number="" line_end=""

    tool_name=$(printf '%s' "$json" | jq -r '.tool_name // empty')
    [[ -z "$tool_name" ]] && return 1

    case "$tool_name" in
        Read)
            file_path=$(printf '%s' "$json" | jq -r '.tool_input.file_path // empty')
            local read_offset read_limit
            read_offset=$(printf '%s' "$json" | jq -r '.tool_input.offset // 0')
            read_limit=$(printf '%s' "$json" | jq -r '.tool_input.limit // 0')
            if [[ "$read_offset" =~ ^[0-9]+$ && "$read_offset" -gt 0 ]]; then
                if [[ "$read_limit" =~ ^[0-9]+$ && "$read_limit" -gt 0 ]]; then
                    line_number=$(( read_offset + read_limit / 2 ))
                else
                    line_number="$read_offset"
                fi
            fi
            ;;
        Edit)
            file_path=$(printf '%s' "$json" | jq -r '.tool_input.file_path // empty')
            local new_string
            new_string=$(printf '%s' "$json" | jq -r '.tool_input.new_string // empty')
            if [[ -n "$new_string" && -n "$file_path" && -f "$file_path" ]]; then
                local first_line
                first_line=$(printf '%s' "$new_string" | head -1)
                line_number=$(grep -nF -- "$first_line" "$file_path" 2>/dev/null | head -1 | cut -d: -f1 || true)
                local new_line_count
                new_line_count=$(printf '%s' "$new_string" | wc -l | tr -d ' ')
                if [[ -n "$line_number" && "$new_line_count" -gt 1 ]]; then
                    line_end=$(( line_number + new_line_count ))
                fi
            fi
            line_number="${line_number:-1}"
            ;;
        Write)
            file_path=$(printf '%s' "$json" | jq -r '.tool_input.file_path // empty')
            line_number="1"
            ;;
        Grep)
            file_path=$(printf '%s' "$json" | jq -r '.tool_input.path // empty')
            echo "TOOL_NAME=${tool_name}"
            echo "EVENT_PATH=${file_path}"
            echo "TOOL_TYPE=search"
            return 0
            ;;
        Glob)
            file_path=$(printf '%s' "$json" | jq -r '.tool_input.path // empty')
            echo "TOOL_NAME=${tool_name}"
            echo "EVENT_PATH=${file_path}"
            echo "TOOL_TYPE=search"
            return 0
            ;;
        *)
            return 1
            ;;
    esac

    echo "TOOL_NAME=${tool_name}"
    echo "FILE_PATH=${file_path}"
    echo "LINE_NUMBER=${line_number}"
    echo "LINE_END=${line_end}"
    echo "TOOL_TYPE=file"
}
```

- [ ] **Step 2: Verify provider works**

Run:
```bash
source lib/providers/claude-code.sh
provider_name
provider_is_installed && echo "installed" || echo "not installed"
echo '{"tool_name":"Read","tool_input":{"file_path":"README.md","offset":50,"limit":10}}' | {
    json=$(cat)
    provider_parse_event "$json"
}
```
Expected: `Claude Code`, `installed`, and parsed output with `LINE_NUMBER=55`

- [ ] **Step 3: Commit**

```bash
git add lib/providers/claude-code.sh
git commit -m "feat: add Claude Code provider with standard interface"
```

---

### Task 3: Refactor hooks.sh to Use Config + Provider

**Files:**
- Modify: `lib/hooks.sh`

- [ ] **Step 1: Rewrite hooks.sh**

Replace the entire file. Key changes:
- Source `config.sh` and load config
- Source provider based on `cfg provider`
- Use `provider_parse_event` instead of inline Claude JSON parsing
- Use `cfg` for all paths and values
- Project scope filtering uses `cfg scope`

```bash
#!/usr/bin/env bash
# lib/hooks.sh — PostToolUse hook handler
# Dispatches to tree and viewer based on agent events.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

IDEALYZE_DIR="${HOME}/.idealyze"
SESSION_FILE="${IDEALYZE_DIR}/session.json"
DEBUG_LOG="${IDEALYZE_DIR}/debug.log"

# Session guard
[[ -f "$SESSION_FILE" ]] || exit 0

debug() {
    [[ "${IDEALYZE_DEBUG:-}" == "1" ]] && echo "[hooks $(date +%H:%M:%S)] $*" >> "$DEBUG_LOG" || true
}

# Read session state
VIEWER_ID=$(jq -r '.panes.viewer // ""' "$SESSION_FILE")
PROJECT_DIR=$(jq -r '.project_dir // ""' "$SESSION_FILE")
VIEWER_MODE=$(cfg "viewer.mode" "raw")
SCOPE=$(cfg "scope" "project")

[[ -z "$VIEWER_ID" ]] && exit 0
[[ "$VIEWER_ID" =~ ^[a-zA-Z0-9_.@-]+$ ]] || exit 0

# Load provider
PROVIDER=$(cfg "provider" "claude-code")
source "${LIB_DIR}/providers/${PROVIDER}.sh"

# Read hook JSON
HOOK_JSON=$(cat)
debug "stdin: ${HOOK_JSON:0:500}"

# Parse event with provider
PARSED=$(provider_parse_event "$HOOK_JSON") || { debug "parse failed"; exit 0; }
eval "$PARSED"
debug "tool=$TOOL_NAME type=${TOOL_TYPE:-}"

# Scope filter
if [[ "$SCOPE" != "global" && -n "$PROJECT_DIR" ]]; then
    local_path="${FILE_PATH:-${EVENT_PATH:-}}"
    if [[ -n "$local_path" && "$local_path" != "$PROJECT_DIR"* ]]; then
        debug "skipped: $local_path outside $PROJECT_DIR"
        exit 0
    fi
fi

# Search tools (Grep/Glob) — update tree only
if [[ "${TOOL_TYPE:-}" == "search" ]]; then
    if [[ -n "${EVENT_PATH:-}" ]]; then
        if [[ -d "$EVENT_PATH" ]]; then
            "$LIB_DIR/tree.sh" focus "$EVENT_PATH" &
        elif [[ -f "$EVENT_PATH" ]]; then
            "$LIB_DIR/tree.sh" select "$EVENT_PATH" &
        fi
    fi
    wait
    exit 0
fi

# File tools — update tree + viewer
[[ -z "${FILE_PATH:-}" || ! -f "${FILE_PATH:-}" ]] && exit 0

"$LIB_DIR/tree.sh" select "$FILE_PATH" &

VIEWER_CMD=$("$LIB_DIR/viewer.sh" "$FILE_PATH" "${LINE_NUMBER:-}" "$VIEWER_MODE" "${LINE_END:-}")
debug "viewer_cmd: $VIEWER_CMD"

if [[ -n "$VIEWER_CMD" ]]; then
    printf '%s' "$VIEWER_CMD" > "${IDEALYZE_DIR}/viewer-cmd.tmp"
    mv "${IDEALYZE_DIR}/viewer-cmd.tmp" "${IDEALYZE_DIR}/viewer-cmd"
fi

printf '%s\n%s' "$FILE_PATH" "${LINE_NUMBER:-1}" > "${IDEALYZE_DIR}/current-file"

debug "done"
wait
```

- [ ] **Step 2: Test hook with provider**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"'$(pwd)/README.md'"}}' | IDEALYZE_DEBUG=1 bash lib/hooks.sh
tail -5 ~/.idealyze/debug.log
```
Expected: hook processes and writes viewer-cmd

- [ ] **Step 3: Commit**

```bash
git add lib/hooks.sh
git commit -m "refactor: hooks.sh uses config loader and provider interface"
```

---

### Task 4: Refactor viewer.sh to Use Config

**Files:**
- Modify: `lib/viewer.sh`

- [ ] **Step 1: Rewrite viewer.sh to read from config**

Key changes:
- Source config.sh
- Read `viewer.highlight_color`, `viewer.highlight_color_source`, `viewer.bat_style` from config
- Remove hardcoded color values

```bash
#!/usr/bin/env bash
# lib/viewer.sh — Build viewer command for bat or glow
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

FILE_PATH="${1:-}"
LINE_NUMBER="${2:-}"
VIEWER_MODE="${3:-$(cfg viewer.mode raw)}"
LINE_END="${4:-}"

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

FILE_EXT="${FILE_PATH##*.}"

# Glow for markdown in rendered mode
if [[ "$VIEWER_MODE" == "glow" && "$FILE_EXT" == "md" ]] && command -v glow &>/dev/null; then
    GLOW_STYLE=""
    if [[ -f "${HOME}/.idealyze/config/glow-style.json" ]]; then
        GLOW_STYLE="-s ${HOME}/.idealyze/config/glow-style.json"
    elif [[ -f "${LIB_DIR}/../config/glow-style.json" ]]; then
        GLOW_STYLE="-s $(cd "${LIB_DIR}/../config" && pwd)/glow-style.json"
    fi
    echo "clear && glow ${GLOW_STYLE} -w \$(tput cols) \"${FILE_PATH}\""
    exit 0
fi

[[ "$LINE_NUMBER" =~ ^[0-9]+$ ]] || LINE_NUMBER=""
[[ "$LINE_END" =~ ^[0-9]+$ ]] || LINE_END=""

BAT_STYLE=$(cfg "viewer.bat_style" "numbers,header,grid")
BAT="bat --paging=never --wrap=auto --style=${BAT_STYLE} --color=always"

HL_FROM=$(cfg "viewer.highlight_color_source" "51;51;51")
HL_TO=$(cfg "viewer.highlight_color" "40;40;160")
BOOST="sed $'s/48;2;${HL_FROM}/48;2;${HL_TO}/g'"

if [[ -n "$LINE_END" && "$LINE_END" -gt "${LINE_NUMBER:-0}" ]]; then
    HIGHLIGHT="${LINE_NUMBER}:${LINE_END}"
else
    HIGHLIGHT="${LINE_NUMBER}"
fi

if [[ -n "$LINE_NUMBER" && "$LINE_NUMBER" != "0" ]]; then
    echo "clear && H=\$(tput lines); S=\$(( ${LINE_NUMBER} > H/2 ? ${LINE_NUMBER} - H/2 : 1 )); E=\$(( S + H - 3 )); ${BAT} --highlight-line ${HIGHLIGHT} --line-range \${S}:\${E} \"${FILE_PATH}\" | ${BOOST}"
else
    echo "clear && ${BAT} \"${FILE_PATH}\""
fi
```

- [ ] **Step 2: Test viewer generates correct command**

Run:
```bash
bash lib/viewer.sh README.md 10 raw
```
Expected: `clear && H=$(tput lines)... bat ... --highlight-line 10 ...`

- [ ] **Step 3: Commit**

```bash
git add lib/viewer.sh
git commit -m "refactor: viewer.sh reads colors and styles from config"
```

---

### Task 5: Refactor viewer-loop.sh to Use Config

**Files:**
- Modify: `lib/viewer-loop.sh`

- [ ] **Step 1: Update viewer-loop.sh**

Key changes: read `viewer.poll_interval` and `layout.dimension_stabilize_retries` from config.

Replace the polling sleep and stabilization loop:

```bash
# At top, after shebang:
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

POLL_INTERVAL=$(cfg "viewer.poll_interval" "0.3")
STABILIZE_RETRIES=$(cfg "layout.dimension_stabilize_retries" "10")
```

Replace `sleep 0.3` with `sleep "$POLL_INTERVAL"`.

Replace stabilization loop `for _ in 1 2 3 4 5 6 7 8 9 10` with:
```bash
for _ in $(seq 1 "$STABILIZE_RETRIES"); do
```

- [ ] **Step 2: Commit**

```bash
git add lib/viewer-loop.sh
git commit -m "refactor: viewer-loop.sh reads timing from config"
```

---

### Task 6: Refactor layout.applescript to Accept Config Args

**Files:**
- Modify: `lib/layout.applescript`

- [ ] **Step 1: Update applescript to accept shrink/step as args**

Change the script to accept 6 args: `project_dir lib_dir broot_conf agent_cmd shrink_count resize_step`

Replace hardcoded `repeat 13 times` / `repeat 30 times` and `resize_split:left,10` with the passed values.

The `agent_cmd` arg is `"no-agent"` for 2-pane, or the actual command for 3-pane.

```applescript
-- Usage: osascript layout.applescript <project_dir> <lib_dir> <broot_conf> <agent_cmd> <shrink_count> <resize_step>
on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv
    set agentCmd to item 4 of argv
    set shrinkCount to (item 5 of argv) as integer
    set resizeStep to (item 6 of argv) as integer
    set brootSocket to item 7 of argv

    tell application "Ghostty"
        activate
        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        if agentCmd is not "no-agent" then
            set win to new window with configuration cfg
            set agentTerminal to terminal 1 of selected tab of win
            set viewerTerminal to split agentTerminal direction left with configuration cfg
            set treeTerminal to split viewerTerminal direction left with configuration cfg
            perform action "equalize_splits" on treeTerminal
            repeat shrinkCount times
                perform action ("resize_split:left," & resizeStep) on treeTerminal
            end repeat
            -- ... rest same but use brootSocket variable for --listen
            input text "broot --conf " & brootConf & " --listen " & brootSocket & " " & projectDir & "\n" to treeTerminal
            input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal
            input text agentCmd & "\n" to agentTerminal
            -- ... return JSON
        else
            -- 2-pane version, same pattern with shrinkCount and resizeStep
        end if
    end tell
end run
```

- [ ] **Step 2: Update bin/idealyze launch() to pass config values**

In `launch()`, read values from config and pass to applescript:

```bash
local shrink step broot_socket agent_cmd
agent_cmd="${IDEALYZE_AGENT_CMD:-$(cfg agent_cmd claude)}"
broot_socket=$(cfg "broot_socket" "idealyze")

if [[ -n "${IDEALYZE_WITH_AGENT:-}" ]]; then
    shrink=$(cfg_int "layout.tree_shrink_3pane" "13")
else
    shrink=$(cfg_int "layout.tree_shrink_2pane" "30")
    agent_cmd="no-agent"
fi
step=$(cfg_int "layout.resize_step" "10")

pane_json=$(osascript "${LIB_DIR}/layout.applescript" \
    "$project_dir" "$LIB_DIR" "${CONFIG_DIR}/broot-sidebar.toml" \
    "$agent_cmd" "$shrink" "$step" "$broot_socket")
```

- [ ] **Step 3: Commit**

```bash
git add lib/layout.applescript bin/idealyze
git commit -m "refactor: layout accepts config values as args, no hardcoded constants"
```

---

### Task 7: Refactor toggle.sh to Use Config + Provider

**Files:**
- Modify: `lib/toggle.sh`

- [ ] **Step 1: Source config and use cfg values**

At top of file:
```bash
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load
```

Replace hardcoded values:
- `repeat 30 times` → use `$(cfg_int layout.tree_shrink_restore 30)` passed to osascript
- `resize_split:left,10` → use `$(cfg_int layout.resize_step 10)` passed to osascript
- `sleep 0.5` → use `$(cfg layout.resize_settle_delay 0.5)`
- `--listen idealyze` → use `$(cfg broot_socket idealyze)`
- `.agent_cmd // "claude"` → use `$(cfg agent_cmd claude)`

- [ ] **Step 2: Commit**

```bash
git add lib/toggle.sh
git commit -m "refactor: toggle.sh reads layout and provider values from config"
```

---

### Task 8: Refactor tree.sh to Use Config

**Files:**
- Modify: `lib/tree.sh`

- [ ] **Step 1: Source config, use broot_socket from config**

```bash
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/config.sh"
config_load

SOCKET_NAME=$(cfg "broot_socket" "idealyze")
```

- [ ] **Step 2: Commit**

```bash
git add lib/tree.sh
git commit -m "refactor: tree.sh reads broot socket name from config"
```

---

### Task 9: Refactor bin/idealyze to Use Config + Provider

**Files:**
- Modify: `bin/idealyze`

- [ ] **Step 1: Source config at top**

After the LIB_DIR/CONFIG_DIR resolution:
```bash
source "${LIB_DIR}/config.sh"
config_load
```

- [ ] **Step 2: Replace all hardcoded values in launch/stop/uninstall/doctor/update**

Key replacements:
- `IDEALYZE_SCOPE:-project` → `cfg scope project`
- `IDEALYZE_AGENT_CMD:-claude` → `cfg agent_cmd claude`
- `/tmp/broot-server-idealyze.sock` → `/tmp/broot-server-$(cfg broot_socket idealyze).sock`
- `viewer_mode: "raw"` → `viewer_mode: "$(cfg viewer.mode raw)"`
- `--max-time 3` → `--max-time $(cfg_int updates.check_timeout 3)`
- Channel references → `cfg updates.channel latest`

- [ ] **Step 3: Refactor doctor to use provider**

```bash
PROVIDER=$(cfg "provider" "claude-code")
source "${LIB_DIR}/providers/${PROVIDER}.sh"

# In hooks section:
if provider_is_installed; then
    ok "$(provider_name) installed"
    if provider_check_hooks; then
        ok "hooks configured"
    else
        bad "hooks not configured"
    fi
else
    skip "$(provider_name) not installed"
fi
```

- [ ] **Step 4: Refactor uninstall to use provider**

```bash
PROVIDER=$(cfg "provider" "claude-code")
source "${LIB_DIR}/providers/${PROVIDER}.sh"
provider_remove_hooks
```

- [ ] **Step 5: Add pre-flight checks to launch**

```bash
check_preflight() {
    local errors=()
    [[ "$(uname -s)" != "Darwin" ]] && errors+=("macOS required")
    [[ ! -d "/Applications/Ghostty.app" ]] && errors+=("Ghostty not found")
    command -v jq &>/dev/null || errors+=("jq not found")
    command -v broot &>/dev/null || errors+=("broot not found")
    command -v bat &>/dev/null || errors+=("bat not found")
    command -v osascript &>/dev/null || errors+=("osascript not found (macOS only)")
    command -v curl &>/dev/null || errors+=("curl not found")

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "idealize: preflight failed:" >&2
        for e in "${errors[@]}"; do echo "  - $e" >&2; done
        echo "  run 'idealyze doctor' to fix" >&2
        exit 1
    fi
}
```

- [ ] **Step 6: Commit**

```bash
git add bin/idealyze
git commit -m "refactor: bin/idealyze uses config + provider, adds preflight checks"
```

---

### Task 10: Refactor install.sh to Use Provider

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add config-defaults.json and providers to download list**

```bash
download "${BASE_URL}/lib/config.sh" "${INSTALL_DIR}/lib/config.sh" "lib/config.sh"
download "${BASE_URL}/lib/config-defaults.json" "${INSTALL_DIR}/lib/config-defaults.json" "lib/config-defaults.json"
mkdir -p "${INSTALL_DIR}/lib/providers"
download "${BASE_URL}/lib/providers/claude-code.sh" "${INSTALL_DIR}/lib/providers/claude-code.sh" "lib/providers/claude-code.sh"
chmod +x "${INSTALL_DIR}/lib/providers/"*.sh
```

- [ ] **Step 2: Use provider for hook configuration**

```bash
source "${INSTALL_DIR}/lib/providers/claude-code.sh"

if provider_is_installed; then
    ok "$(provider_name) detected"
    if ask_yn "Configure $(provider_name) hooks?" "y"; then
        if provider_install_hooks "$HOOK_CMD" "$INSTALL_MODE"; then
            ok "hooks configured"
        else
            warn "failed to configure hooks"
        fi
    fi
else
    skip "$(provider_name) not found — hook configuration skipped"
fi
```

- [ ] **Step 3: Add comprehensive pre-flight checks**

```bash
# System checks
[[ "$(uname -s)" == "Darwin" ]] || fail "idealize requires macOS"
command -v curl &>/dev/null || fail "curl is required"
command -v jq &>/dev/null || fail "jq is required (brew install jq)"

# Writable check
if [[ "$INSTALL_MODE" == "user" ]]; then
    mkdir -p "$BIN_DIR" 2>/dev/null || fail "cannot write to ${BIN_DIR}"
    mkdir -p "$INSTALL_DIR" 2>/dev/null || fail "cannot write to ${INSTALL_DIR}"
fi

# Connectivity check
if ! curl -fsSL --max-time 5 "https://raw.githubusercontent.com/${REPO}/main/bin/idealyze" -o /dev/null 2>/dev/null; then
    fail "cannot reach GitHub — check your network"
fi
```

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "refactor: install.sh uses provider interface, adds pre-flight checks"
```

---

### Task 11: Update Docs and Test E2E

**Files:**
- Modify: `docs/design.md`
- Modify: `README.md`

- [ ] **Step 1: Update design.md with config and provider architecture**

Add sections for config system and provider interface.

- [ ] **Step 2: Update README with config customization section**

Add example of `~/.idealyze/config.json` for customization.

- [ ] **Step 3: E2E test — local**

```bash
./bin/idealyze doctor
./bin/idealyze
./bin/idealyze toggle tree && sleep 1 && ./bin/idealyze toggle tree
./bin/idealyze toggle agent && sleep 1 && ./bin/idealyze toggle agent
./bin/idealyze toggle render && sleep 1 && ./bin/idealyze toggle render
./bin/idealyze stop
```

- [ ] **Step 4: E2E test — config override**

```bash
mkdir -p .idealyze
echo '{"layout":{"tree_shrink_2pane":20}}' > .idealyze/config.json
./bin/idealyze  # tree should be wider
./bin/idealyze stop
rm .idealyze/config.json
```

- [ ] **Step 5: Commit**

```bash
git add docs/ README.md
git commit -m "docs: update for config system and provider architecture"
```

---

### Task 12: Merge and Tag Beta

- [ ] **Step 1: Merge dev to main**

```bash
git checkout main && git merge dev && git push
```

- [ ] **Step 2: Tag beta**

```bash
git tag -f beta && git push origin beta --force
```

- [ ] **Step 3: E2E test from remote**

Full uninstall → install from beta → doctor → launch → toggles → stop → uninstall
