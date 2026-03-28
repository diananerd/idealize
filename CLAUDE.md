# Idealize — Development Guide

## What is this?

Idealize is a terminal IDE companion for AI coding agents. It creates a Ghostty window with a file tree (broot) and code viewer (bat/glow) that react in real time to agent file operations via hooks. It's agent-agnostic — currently ships with a Claude Code provider, but the architecture supports any agent.

## Project Structure

```
bin/idealyze              CLI entry point (bash)
lib/
  config.sh               Config loader (cfg/cfg_int functions)
  config-defaults.json    Default config values
  hooks.sh                PostToolUse hook handler
  viewer.sh               Builds bat/glow render commands
  viewer-loop.sh          Persistent process in viewer pane (polls + WINCH)
  tree.sh                 Sends commands to broot via socket IPC
  toggle.sh               Toggle tree/agent/render
  layout.applescript      Creates Ghostty panes via AppleScript
  providers/
    claude-code.sh        Claude Code provider (hook install/remove/parse)
config/
  broot-sidebar.toml      broot sidebar config
  glow-style.json         Custom glow style for clean markdown rendering
install.sh                Interactive installer (curl|bash safe)
docs/
  design.md               Architecture and IPC model
  releasing.md            Release channels and workflow
```

## Development Workflow

**CRITICAL: Always follow this exact cycle. No exceptions.**

### 1. Work on `dev` branch

```bash
git checkout dev
# make changes
git add ... && git commit -m "..."
git push
```

### 2. Merge to main and tag beta

```bash
git checkout main && git merge dev && git push
git tag -f beta && git push origin beta --force
```

### 3. Wait for GitHub CDN (~3 min)

```bash
sleep 180
curl -fsSL "https://raw.githubusercontent.com/diananerd/idealize/beta/bin/idealyze" | grep '^VERSION='
```

### 4. Full cleanup

```bash
rm -rf ~/.idealyze; rm -f ~/.local/bin/idealyze
rm -f ~/.config/ghostty/config; rmdir ~/.config/ghostty 2>/dev/null
brew uninstall broot bat glow 2>/dev/null; true
jq 'del(.hooks)' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
pkill -f viewer-loop 2>/dev/null; true
```

### 5. Install from beta and test

```bash
curl -fsSL --resolve "idealize.diananerd.com:443:$(dig idealize.diananerd.com @1.1.1.1 +short | head -1)" "https://idealize.diananerd.com/install?channel=beta" | bash -s -- --auto --beta
```

### 6. E2E test (ALL of these, every time)

```bash
idealyze --version
idealyze doctor
idealyze                              # launch 2-pane
idealyze toggle tree                  # hide
idealyze toggle tree                  # restore
idealyze toggle agent                 # add
idealyze toggle agent                 # remove
idealyze toggle render                # to glow
idealyze toggle render                # back to raw
# hooks
echo '{"tool_name":"Read","tool_input":{"file_path":"'$(pwd)/README.md'"}}' | bash ~/.idealyze/lib/hooks.sh
# combos
idealyze toggle tree && sleep 0.5 && idealyze toggle agent
idealyze toggle agent && sleep 0.5 && idealyze toggle tree
# lifecycle
idealyze stop
idealyze stop                         # double stop (should be graceful)
idealyze                              # relaunch
idealyze stop
# uninstall
idealyze uninstall --yes
# verify clean
ls ~/.idealyze                        # should not exist
ls ~/.local/bin/idealyze              # should not exist
jq '.hooks' ~/.claude/settings.json   # should be null
cat ~/.config/ghostty/config          # should not exist
ps aux | grep viewer-loop             # should be 0
```

### 7. If beta passes, promote to latest

```bash
git tag -f latest && git push origin latest --force
```

### 8. Wait for CDN, cleanup, repeat E2E from prod

Same as steps 3-6 but install from prod (no --beta flag).

### 9. Rebase dev from main

```bash
git checkout dev && git rebase main && git push
```

## Config System

JSON config with 3-level resolution: project (`.idealyze/config.json`) > user (`~/.idealyze/config.json`) > defaults (`lib/config-defaults.json`).

Use `cfg "key.path" "default"` and `cfg_int "key.path" "default"` to read values. All scripts source `lib/config.sh` first.

## Provider System

Each provider implements: `provider_name`, `provider_is_installed`, `provider_settings_path`, `provider_check_hooks`, `provider_install_hooks`, `provider_remove_hooks`, `provider_parse_event`.

To add a new provider: create `lib/providers/<name>.sh` implementing the interface.

## Key Conventions

- **No hardcoded values** — everything comes from config
- **No Claude-specific code outside providers/** — the rest of the codebase is agent-agnostic
- **Hooks only touch their own entries** — install adds, uninstall removes only idealyze hooks
- **All toggles refresh IDs from Ghostty** — never trust stale IDs in session.json
- **WINCH is debounced** — 150ms wait before re-rendering to avoid flicker
- **viewer-loop uses `sleep & wait`** — makes sleep interruptible by signals
- **`set -uo pipefail`** in most scripts, **no `-e`** in hooks.sh (must not die silently)
- **Debug logging gated** behind `IDEALYZE_DEBUG=1` to avoid unbounded log growth
- **`curl | bash` via bootstrapper** — `/install` endpoint serves a bootstrapper that downloads to temp file then executes, preventing stdin consumption

## Testing Hooks Locally

```bash
# Simulate Read
echo '{"tool_name":"Read","tool_input":{"file_path":"'$(pwd)/README.md'"}}' | IDEALYZE_DEBUG=1 bash lib/hooks.sh

# Simulate Edit
echo '{"tool_name":"Edit","tool_input":{"file_path":"'$(pwd)/README.md'","new_string":"# Title"}}' | IDEALYZE_DEBUG=1 bash lib/hooks.sh

# Check debug log
tail -20 ~/.idealyze/debug.log
```

## Infrastructure

- **Cloudflare Worker** at `idealize.diananerd.com` (repo: diananerd/idealize-worker, private)
- `/install.sh` → proxies GitHub raw from `latest` tag
- `/install.sh?channel=beta` → proxies from `beta` tag
- Deploy: `cd ../idealize-worker && npx wrangler deploy`

## Known Ghostty Quirks

- `resize_split:left` only shrinks panes created via `split direction left`
- Window IDs are `tab-group-*` format
- `close` message doesn't work on windows — use `perform action "close_window"`
- `confirm-close-surface` requires `reload_config` to apply to running windows
- broot `:select` doesn't highlight remotely — use `:escape;filename` instead
- Splits created later can change IDs of existing terminals
