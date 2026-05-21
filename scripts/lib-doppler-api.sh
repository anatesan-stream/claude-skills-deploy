#!/usr/bin/env bash
# lib-doppler-api.sh — Doppler CLI wrapper.
# Source this from other scripts. Do not execute directly.
#
# Note: Doppler CLI v3.76.0 has no --account flag. The token itself scopes
# the workspace. DOPPLER_ACCOUNT is retained for reference/logging only.

set -euo pipefail

: "${COOLIFY_REGISTRY:=$HOME/.claude/coolify.json}"

doppler_load_account() {
  local server_alias="$1"
  if [ ! -f "$COOLIFY_REGISTRY" ]; then
    echo "ERROR: $COOLIFY_REGISTRY not found." >&2; return 1
  fi
  DOPPLER_ACCOUNT=$(python3 -c "
import json,sys
d=json.load(open('$COOLIFY_REGISTRY'))
print(d.get('servers',{}).get('$server_alias',{}).get('doppler_account',''))
")
  if [ -z "$DOPPLER_ACCOUNT" ]; then
    echo "ERROR: server '$server_alias' has no doppler_account field in $COOLIFY_REGISTRY" >&2
    return 1
  fi
  export DOPPLER_ACCOUNT
}

doppler_cmd() {
  doppler "$@"
}

doppler_check_key() {
  local project="$1" config="$2" key="$3"
  local value
  value=$(doppler_cmd secrets get --project "$project" --config "$config" "$key" --plain 2>/dev/null || echo "")
  if [ -z "$value" ]; then
    return 1
  fi
  if [ "$value" = "TODO_REPLACE_BEFORE_DEPLOY" ]; then
    return 2  # placeholder — present but not real
  fi
  return 0
}

doppler_create_service_token() {
  local project="$1" config="$2" name="$3"
  doppler_cmd configs tokens create "$name" -p "$project" -c "$config" --plain 2>/dev/null
}

doppler_download_secrets() {
  local project="$1" config="$2"
  doppler_cmd secrets download --project "$project" --config "$config" --no-file --format docker 2>/dev/null
}
