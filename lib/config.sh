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

    _RESOLVED_CONFIG=$(cat "$defaults")

    if [[ -f "$user_conf" ]] && jq empty "$user_conf" 2>/dev/null; then
        _RESOLVED_CONFIG=$(echo "$_RESOLVED_CONFIG" | jq --slurpfile u "$user_conf" '. * $u[0]')
    fi

    if [[ -f "$project_conf" ]] && jq empty "$project_conf" 2>/dev/null; then
        _RESOLVED_CONFIG=$(echo "$_RESOLVED_CONFIG" | jq --slurpfile p "$project_conf" '. * $p[0]')
    fi

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
