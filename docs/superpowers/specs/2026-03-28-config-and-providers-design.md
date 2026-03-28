# Centralized Config + Multi-Provider Architecture

## Problem

All config values are hardcoded across scripts. Claude Code is baked in as the only provider. Adding a new provider (aider, codex, etc) requires touching every file.

## Design

### Config System

A JSON config file with 3-level resolution:

1. **Project**: `.idealyze/config.json` in current working directory
2. **User**: `~/.idealyze/config.json`
3. **Defaults**: hardcoded fallbacks in `lib/config.sh`

Project overrides user, user overrides defaults. Configs merge at the top level — a project config only needs to specify the keys it wants to override.

**Config file** (`config.json`):

```json
{
  "provider": "claude-code",
  "scope": "project",
  "agent_cmd": "claude",
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

### Config Loader (`lib/config.sh`)

A single sourceable script that all other scripts use. Provides:

- `config_get KEY [DEFAULT]` — reads a key using jq dot notation (e.g. `viewer.mode`)
- `config_load` — called once at startup, merges project + user + defaults into a resolved JSON in memory
- Exports `IDEALYZE_CONFIG` (the resolved JSON string) so child processes inherit it

```bash
# Usage in any script:
source "${LIB_DIR}/config.sh"
config_load

mode=$(config_get "viewer.mode" "raw")
shrink=$(config_get "layout.tree_shrink_2pane" "30")
provider=$(config_get "provider" "claude-code")
```

The loader merges with `jq`:
```bash
# defaults * user * project (right wins)
jq -s '.[0] * .[1] * .[2]' defaults.json user.json project.json
```

### Provider System

Each provider is a shell script in `lib/providers/` that implements a standard interface:

```bash
# lib/providers/claude-code.sh

provider_name() { echo "claude-code"; }
provider_agent_cmd() { echo "claude"; }

# Install hooks into the provider's settings
provider_install_hooks() {
    local hook_cmd="$1"  # e.g. "bash /path/to/hooks.sh"
    # Writes to ~/.claude/settings.json
}

# Remove hooks from the provider's settings
provider_remove_hooks() {
    # Removes from ~/.claude/settings.json
}

# Check if hooks are configured
provider_check_hooks() {
    # Returns 0 if configured, 1 if not
}

# Parse a hook event JSON into standardized fields
# Reads from stdin, writes env vars to stdout
provider_parse_event() {
    local json="$1"
    # Extracts: TOOL_NAME, FILE_PATH, LINE_NUMBER, LINE_END, EVENT_PATH
    # Output format: KEY=VALUE lines (eval-able)
}

# Provider-specific settings file path
provider_settings_path() {
    local mode="$1"  # "user" or "project"
    if [[ "$mode" == "project" ]]; then
        echo "$(pwd)/.claude/settings.json"
    else
        echo "${HOME}/.claude/settings.json"
    fi
}

# Check if the provider CLI is installed
provider_is_installed() {
    command -v claude &>/dev/null
}
```

### How hooks.sh Changes

Currently hooks.sh hardcodes Claude JSON parsing. With providers:

```bash
source "${LIB_DIR}/config.sh"
config_load

PROVIDER=$(config_get "provider" "claude-code")
source "${LIB_DIR}/providers/${PROVIDER}.sh"

# Read hook JSON
HOOK_JSON=$(cat)

# Parse with provider-specific logic
eval "$(provider_parse_event "$HOOK_JSON")"

# Now TOOL_NAME, FILE_PATH, LINE_NUMBER, LINE_END are set
# Rest of hooks.sh works the same (viewer, tree updates)
```

### How install.sh Changes

```bash
# After config is set up
PROVIDER=$(config_get "provider" "claude-code")
source "providers/${PROVIDER}.sh"

if provider_is_installed; then
    ok "$(provider_name) detected"
    provider_install_hooks "$HOOK_CMD"
else
    skip "$(provider_name) not found — hooks skipped"
fi
```

### How uninstall Changes

```bash
PROVIDER=$(config_get "provider" "claude-code")
source "providers/${PROVIDER}.sh"
provider_remove_hooks
```

### How doctor Changes

```bash
PROVIDER=$(config_get "provider" "claude-code")
source "providers/${PROVIDER}.sh"

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

### File Layout

```
lib/
  config.sh                  # Config loader (config_get, config_load)
  config-defaults.json       # Default values
  providers/
    claude-code.sh           # Claude Code provider
config/
  broot-sidebar.toml         # broot config (unchanged)
  glow-style.json            # glow style (unchanged)
```

### What Moves to Config

| Current hardcoded | Config key | Default |
|---|---|---|
| `"claude"` agent default | `agent_cmd` | `"claude"` |
| `"project"` scope | `scope` | `"project"` |
| `"raw"` viewer mode | `viewer.mode` | `"raw"` |
| `0.3` poll interval | `viewer.poll_interval` | `0.3` |
| `40;40;160` highlight | `viewer.highlight_color` | `"40;40;160"` |
| `51;51;51` source color | `viewer.highlight_color_source` | `"51;51;51"` |
| `numbers,header,grid` | `viewer.bat_style` | `"numbers,header,grid"` |
| `30` 2-pane shrink | `layout.tree_shrink_2pane` | `30` |
| `13` 3-pane shrink | `layout.tree_shrink_3pane` | `13` |
| `10` resize step px | `layout.resize_step` | `10` |
| `30` tree restore | `layout.tree_shrink_restore` | `30` |
| `0.5` resize settle | `layout.resize_settle_delay` | `0.5` |
| `10` dim stabilize | `layout.dimension_stabilize_retries` | `10` |
| `3` version timeout | `updates.check_timeout` | `3` |
| `"latest"` channel | `updates.channel` | `"latest"` |
| `"claude-code"` provider | `provider` | `"claude-code"` |
| `"idealyze"` socket | `broot_socket` | `"idealyze"` |

### AppleScript and Config

layout.applescript receives numeric values as arguments from `bin/idealyze`, which reads them from config. The applescript itself stays hardcoded-free:

```bash
# in bin/idealyze launch()
shrink=$(config_get "layout.tree_shrink_2pane" "30")
step=$(config_get "layout.resize_step" "10")
osascript "${LIB_DIR}/layout.applescript" "$project_dir" "$LIB_DIR" "$broot_conf" "$agent_cmd" "$shrink" "$step"
```

### Migration

Existing installs without `config.json` work unchanged — defaults match current behavior. The config file is optional and only needed to customize.

### What This Does NOT Change

- Session file format (`session.json`) — stays the same
- IPC mechanism (viewer-cmd file, broot socket) — stays the same
- Viewer loop architecture — stays the same
- Toggle mechanics — stays the same
- The hook event flow — stays the same, just provider parses the JSON

### Adding a New Provider

To add aider support, create `lib/providers/aider.sh` implementing the interface, then:

```bash
idealyze --provider aider
# or in config.json: "provider": "aider"
```

No other files need to change.
