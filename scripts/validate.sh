#!/usr/bin/env bash
# validate.sh — Dry-run validation for /setup-coolify.
# Reads ./coolify.yaml. Exits 0 only when:
#   1. coolify.yaml parses and required fields are present
#   2. ~/.claude/coolify.json has the server alias referenced by coolify.yaml
#   3. Every env_vars key exists in Doppler staging AND production (non-empty, non-placeholder)
#   4. Coolify API reachable: GET /projects returns 200
# On failure: prints MISSING/INVALID lines and exits 1. No Coolify mutations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-coolify-api.sh"
source "$SCRIPT_DIR/lib-doppler-api.sh"

YAML_PATH="${1:-./coolify.yaml}"

if [ ! -f "$YAML_PATH" ]; then
  echo "ERROR: $YAML_PATH not found" >&2
  exit 1
fi

# Parse coolify.yaml fields into shell vars
eval "$(python3 -c "
import yaml,sys
d=yaml.safe_load(open('$YAML_PATH'))
print(f\"PROJECT='{d.get('project','')}'\")
print(f\"SERVER='{d.get('server','')}'\")
print(f\"DOPPLER_PROJECT='{d.get('doppler_project','')}'\")
print(f\"REGISTRY_IMAGE='{d.get('registry',{}).get('image','')}'\")
print(f\"STAGING_DOMAIN='{d.get('environments',{}).get('staging',{}).get('domain','')}'\")
print(f\"STAGING_DOPPLER='{d.get('environments',{}).get('staging',{}).get('doppler_environment','')}'\")
print(f\"PROD_DOMAIN='{d.get('environments',{}).get('production',{}).get('domain','')}'\")
print(f\"PROD_DOPPLER='{d.get('environments',{}).get('production',{}).get('doppler_environment','')}'\")
print(f\"ENV_VARS='{' '.join(d.get('env_vars',[]))}'\")
")"

ERRORS=0
fail() { echo "FAIL: $*" >&2; ERRORS=$((ERRORS+1)); }

[ -n "$PROJECT" ] || fail "INVALID:coolify.yaml:project (empty)"
[ -n "$SERVER" ] || fail "INVALID:coolify.yaml:server (empty)"
[ -n "$DOPPLER_PROJECT" ] || fail "INVALID:coolify.yaml:doppler_project (empty)"
[ -n "$REGISTRY_IMAGE" ] || fail "INVALID:coolify.yaml:registry.image (empty)"
[ -n "$STAGING_DOMAIN" ] || fail "INVALID:coolify.yaml:environments.staging.domain"
[ -n "$PROD_DOMAIN" ] || fail "INVALID:coolify.yaml:environments.production.domain"
[ -n "$ENV_VARS" ] || fail "INVALID:coolify.yaml:env_vars (empty list)"

if [ "$ERRORS" -gt 0 ]; then
  echo "" >&2
  echo "Stop: coolify.yaml schema errors above. Fix and re-run." >&2
  exit 1
fi

# Verify the server alias exists in coolify.json
if ! coolify_load_server "$SERVER"; then
  fail "INVALID:coolify.json:server alias '$SERVER' not found"
  echo "" >&2; echo "Run /setup-coolify init to add it." >&2
  exit 1
fi
doppler_load_account "$SERVER"

echo "validate: server alias '$SERVER' -> $COOLIFY_URL (doppler account: $DOPPLER_ACCOUNT)"

# Verify Coolify API reachable
if ! coolify_curl GET "/projects" >/dev/null 2>&1; then
  fail "INVALID:coolify:api unreachable at $COOLIFY_URL (check api_key, HTTPS, allowed_ips)"
  exit 1
fi
echo "validate: Coolify API reachable"

# Verify every env_vars key exists in BOTH staging and production with non-placeholder values
for ENV in "$STAGING_DOPPLER" "$PROD_DOPPLER"; do
  for KEY in $ENV_VARS; do
    # Strip trailing comment-encoded build_time annotation if any survived (defensive)
    KEY="${KEY%%#*}"
    KEY="${KEY// /}"
    [ -z "$KEY" ] && continue
    if ! doppler_check_key "$DOPPLER_PROJECT" "$ENV" "$KEY"; then
      RC=$?
      if [ "$RC" = "2" ]; then
        fail "MISSING:$KEY:$ENV (present but value is TODO_REPLACE_BEFORE_DEPLOY)"
      else
        fail "MISSING:$KEY:$ENV (key absent in Doppler)"
      fi
    fi
  done
done

if [ "$ERRORS" -gt 0 ]; then
  echo "" >&2
  echo "Stop: $ERRORS Doppler key error(s) above. Fix in Doppler dashboard or via:" >&2
  echo "  doppler --account $DOPPLER_ACCOUNT secrets set --project $DOPPLER_PROJECT --config <env> KEY=VALUE" >&2
  exit 1
fi

echo "OK: All keys present in $DOPPLER_PROJECT/$STAGING_DOPPLER and $DOPPLER_PROJECT/$PROD_DOPPLER"
echo "OK: $COOLIFY_URL API reachable"
echo "OK: ready to provision (run /setup-coolify without arguments)"
exit 0
