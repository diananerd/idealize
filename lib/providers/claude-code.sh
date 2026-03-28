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
    settings=$(provider_settings_path "${1:-user}")
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
            return 0
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
            select(.hooks | all(.command | test("idealyze|idealize/lib/hooks\\.sh") | not))
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
