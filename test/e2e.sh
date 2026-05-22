#!/usr/bin/env bash
# e2e.sh — End-to-end integration test for claude-skills-deploy.
#
# Creates a throwaway Coolify project + Doppler project, provisions staging +
# production apps, triggers a staging deploy, smoke-tests the live URL, and
# cleans up on failure via a trap; on success leaves both apps running.
#
# Usage:
#   bash test/e2e.sh                                  # default server + domain
#   bash test/e2e.sh --server hetzner-strategem       # test against a specific server
#   bash test/e2e.sh --keep                           # skip cleanup (debug failures)
#   E2E_SERVER=other bash test/e2e.sh                 # change server alias (default: vultr-stream)
#   E2E_BASE_DOMAIN=ci.example.com bash test/e2e.sh   # change base domain (default: cicd.streamlinity.com)
#   E2E_IMAGE=ghcr.io/my-org/my-hello:latest bash test/e2e.sh
#
# Defaults E2E_SERVER and E2E_BASE_DOMAIN — change these for other domains.
#
# Prerequisites:
#   ~/.claude/coolify.json  configured with a server alias (ssh_host required)
#   doppler CLI             authenticated (doppler whoami)
#   python3 + pyyaml        (pip3 install pyyaml)
#   curl, ssh
#
# The test image (nginx:alpine on port 3000 with /api/health) must be pushed to
# GHCR before the first run:
#   bash test/push-hello-world.sh

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib-coolify-api.sh"
source "$SKILL_DIR/scripts/lib-doppler-api.sh"

# ── Configuration ──────────────────────────────────────────────────────────────

TIMESTAMP=$(date +%Y%m%d%H%M%S)
TEST_PROJECT="csd-e2e-${TIMESTAMP}"
KEEP_ON_EXIT=false
# E2E_SERVER:      Coolify server alias to test against.
#                  Default: vultr-stream — change for other servers.
# E2E_BASE_DOMAIN: Base domain for staging/production test URLs.
#                  Default: cicd.streamlinity.com — change for other domains.
E2E_SERVER="${E2E_SERVER:-vultr-stream}"
E2E_BASE_DOMAIN="${E2E_BASE_DOMAIN:-cicd.streamlinity.com}"
SERVER_ALIAS=""
# Override E2E_IMAGE to use a different test image (must listen on port 3000,
# serve /api/health returning 200, and be pullable by the Coolify VPS).
E2E_IMAGE="${E2E_IMAGE:-ghcr.io/anatesan-stream/claude-skills-deploy/hello-world:latest}"
DEPLOY_TIMEOUT=180    # seconds to wait for Coolify deploy to finish
SMOKE_TIMEOUT=120     # seconds to wait for HTTPS smoke test (cert issuance takes ~30-60s)

# ── Argument parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) SERVER_ALIAS="$2"; shift 2 ;;
    --keep)   KEEP_ON_EXIT=true; shift ;;
    *) echo "Unknown argument: $1" >&2; echo "Usage: bash test/e2e.sh [--server ALIAS] [--keep]" >&2; exit 1 ;;
  esac
done

# ── State (populated as test proceeds, used by cleanup) ────────────────────────

WORK_DIR=""
COOLIFY_PROJECT_UUID=""
STG_APP_UUID=""
PRD_APP_UUID=""
DOPPLER_CREATED=false
SSH_HOST=""
PASS=0
FAIL=0
RESULTS=()

pass() { PASS=$((PASS+1)); RESULTS+=("  ✓ $*"); echo "  ✓ $*"; }
fail() { FAIL=$((FAIL+1)); RESULTS+=("  ✗ $*"); echo "  ✗ $*" >&2; }
step() { echo ""; echo "=== $* ==="; }

# ── Cleanup (runs on failure via EXIT trap; skipped on success) ─────────────────

cleanup() {
  local exit_code=$?
  echo ""
  echo "═══════════════════════════════════"
  echo " Test Results"
  echo "═══════════════════════════════════"
  for r in "${RESULTS[@]}"; do echo "$r"; done
  echo ""
  echo " Passed: $PASS  Failed: $FAIL"
  echo "═══════════════════════════════════"

  if $KEEP_ON_EXIT; then
    echo ""
    echo "─── --keep: skipping cleanup ───"
    echo "  Coolify project: $TEST_PROJECT (uuid: ${COOLIFY_PROJECT_UUID:-not_created})"
    echo "  Staging app UUID: ${STG_APP_UUID:-not_created}"
    echo "  Production app UUID: ${PRD_APP_UUID:-not_created}"
    echo "  Doppler project: $TEST_PROJECT (created: $DOPPLER_CREATED)"
    echo "  Work dir: ${WORK_DIR:-none}"
    echo ""
    echo "  Manual cleanup:"
    if [ -n "$STG_APP_UUID" ]; then
      echo "    curl -X DELETE $COOLIFY_URL/api/v1/applications/$STG_APP_UUID -H 'Authorization: Bearer \$KEY'"
    fi
    if [ -n "$PRD_APP_UUID" ]; then
      echo "    curl -X DELETE $COOLIFY_URL/api/v1/applications/$PRD_APP_UUID -H 'Authorization: Bearer \$KEY'"
    fi
    if [ -n "$COOLIFY_PROJECT_UUID" ]; then
      echo "    curl -X DELETE $COOLIFY_URL/api/v1/projects/$COOLIFY_PROJECT_UUID -H 'Authorization: Bearer \$KEY'"
    fi
    if $DOPPLER_CREATED; then
      echo "    doppler projects delete $TEST_PROJECT --yes"
    fi
    exit $exit_code
  fi

  # On success, skip teardown — operator inspects live deployment via the staging URL.
  # The completion summary (staging URL, report path, cleanup command) is printed
  # in the main body BEFORE exit 0 fires the trap. Here we only print the
  # "deployment is live" reminder so it appears after the Test Results banner.
  if [ "$exit_code" -eq 0 ]; then
    echo ""
    echo "  Deployment is live — staging and production apps left running."
    echo "  Run cleanup when ready:"
    echo "    bash test/cleanup-deployment.sh ${REPORT_FILE:-<report-file>}"
    exit 0
  fi

  step "Cleanup"

  # Delete Coolify apps first, then project
  if [ -n "$STG_APP_UUID" ]; then
    coolify_curl DELETE "/applications/$STG_APP_UUID" >/dev/null 2>&1 \
      && echo "  ✓ deleted staging app $STG_APP_UUID" \
      || echo "  ⚠ could not delete staging app $STG_APP_UUID (remove manually)"
  fi
  if [ -n "$PRD_APP_UUID" ]; then
    coolify_curl DELETE "/applications/$PRD_APP_UUID" >/dev/null 2>&1 \
      && echo "  ✓ deleted production app $PRD_APP_UUID" \
      || echo "  ⚠ could not delete production app $PRD_APP_UUID (remove manually)"
  fi
  if [ -n "$COOLIFY_PROJECT_UUID" ]; then
    coolify_curl DELETE "/projects/$COOLIFY_PROJECT_UUID" >/dev/null 2>&1 \
      && echo "  ✓ deleted Coolify project $COOLIFY_PROJECT_UUID" \
      || echo "  ⚠ could not delete Coolify project $COOLIFY_PROJECT_UUID (remove manually)"
  fi

  # Remove Doppler fallback-cache Docker volumes from the VPS (created by provision.sh via SSH)
  if [ -n "$SSH_HOST" ]; then
    for uuid in "$STG_APP_UUID" "$PRD_APP_UUID"; do
      [ -z "$uuid" ] && continue
      ssh "$SSH_HOST" "docker volume rm ${uuid}-doppler-cache 2>/dev/null || true" \
        && echo "  ✓ removed docker volume ${uuid}-doppler-cache" \
        || true
    done
  fi

  # Delete Doppler project
  if $DOPPLER_CREATED; then
    doppler projects delete "$TEST_PROJECT" --yes >/dev/null 2>&1 \
      && echo "  ✓ deleted Doppler project $TEST_PROJECT" \
      || echo "  ⚠ could not delete Doppler project $TEST_PROJECT (remove manually at doppler.com)"
  fi

  # Remove temp work directory
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
    echo "  ✓ removed work dir $WORK_DIR"
  fi

  exit $exit_code
}
trap cleanup EXIT

# ── Prerequisites ──────────────────────────────────────────────────────────────

step "Prerequisites"

command -v python3 >/dev/null       || { echo "MISSING: python3" >&2; exit 1; }
python3 -c "import yaml" 2>/dev/null || { echo "MISSING: pyyaml — pip3 install pyyaml" >&2; exit 1; }
command -v doppler >/dev/null        || { echo "MISSING: doppler CLI" >&2; exit 1; }
command -v curl >/dev/null           || { echo "MISSING: curl" >&2; exit 1; }
command -v ssh >/dev/null            || { echo "MISSING: ssh" >&2; exit 1; }
[ -f "$HOME/.claude/coolify.json" ]  || { echo "MISSING: ~/.claude/coolify.json" >&2; exit 1; }

# Resolution precedence: --server flag (already set above) > E2E_SERVER env var > error
if [ -z "$SERVER_ALIAS" ]; then
  SERVER_ALIAS="$E2E_SERVER"
fi

coolify_load_server "$SERVER_ALIAS"
doppler_load_account "$SERVER_ALIAS"

SSH_HOST=$(python3 -c "
import json
d=json.load(open('$HOME/.claude/coolify.json'))
print(d.get('servers',{}).get('$SERVER_ALIAS',{}).get('ssh_host',''))
")
[ -n "$SSH_HOST" ] || { echo "MISSING: ssh_host in coolify.json servers.$SERVER_ALIAS" >&2; exit 1; }

echo "  server alias:    $SERVER_ALIAS → $COOLIFY_URL"
echo "  doppler account: $DOPPLER_ACCOUNT"
echo "  ssh host:        $SSH_HOST"
echo "  test project:    $TEST_PROJECT"
echo "  image:           $E2E_IMAGE"
pass "prerequisites met"

# ── Preflight: verify test image is pullable ───────────────────────────────────

step "Preflight: verify test image is pullable"
echo "  image: $E2E_IMAGE"
if docker pull "$E2E_IMAGE" --quiet >/dev/null 2>&1; then
  pass "test image pullable: $E2E_IMAGE"
else
  fail "test image not found or not pullable: $E2E_IMAGE"
  echo "" >&2
  echo "  Build and push the test image first:" >&2
  echo "    export GHCR_TOKEN=ghp_...   # PAT with write:packages scope" >&2
  echo "    bash test/push-hello-world.sh" >&2
  echo "" >&2
  echo "  Or override with a custom image:" >&2
  echo "    E2E_IMAGE=my-org/my-hello-world:latest bash test/e2e.sh" >&2
  exit 1
fi

# ── Work directory ─────────────────────────────────────────────────────────────

WORK_DIR=$(mktemp -d -t csd-e2e-XXXX)

# ── Step 1: Coolify API reachable ──────────────────────────────────────────────

step "Step 1: Coolify API"
if coolify_curl GET "/projects" >/dev/null 2>&1; then
  pass "Coolify API reachable at $COOLIFY_URL"
else
  fail "Coolify API unreachable at $COOLIFY_URL"
  exit 1
fi

# ── Step 2: Doppler project + secrets ─────────────────────────────────────────

step "Step 2: Doppler test project"

doppler projects create "$TEST_PROJECT" \
  --description "claude-skills-deploy E2E test — auto-deleted" >/dev/null 2>&1
DOPPLER_CREATED=true
echo "  created project: $TEST_PROJECT"

# Create staging and production environments (may already exist from workspace template)
for env_slug in staging production; do
  doppler environments create \
    --name "$(python3 -c "print('$env_slug'.capitalize())")" \
    --slug "$env_slug" \
    --project "$TEST_PROJECT" >/dev/null 2>&1 || true
done

# Set dummy secrets in both configs — these get injected into the container via Doppler
for cfg in staging production; do
  doppler secrets set \
    HELLO=world \
    E2E_TEST=true \
    --project "$TEST_PROJECT" \
    --config "$cfg" >/dev/null 2>&1
  echo "  secrets set in: $TEST_PROJECT/$cfg (HELLO, E2E_TEST)"
done

pass "Doppler project ready (staging + production configs with dummy secrets)"

# ── Step 3: Generate coolify.yaml ─────────────────────────────────────────────

step "Step 3: Generate test coolify.yaml"

STAGING_DOMAIN="${TEST_PROJECT}-staging.${E2E_BASE_DOMAIN}"
PROD_DOMAIN="${TEST_PROJECT}-production.${E2E_BASE_DOMAIN}"
YAML_PATH="$WORK_DIR/coolify.yaml"

python3 - "$YAML_PATH" <<PY
import yaml, sys
path = sys.argv[1]
d = {
    'project': '$TEST_PROJECT',
    'server': '$SERVER_ALIAS',
    'doppler_project': '$TEST_PROJECT',
    'registry': {
        'image': '$E2E_IMAGE',
        'retention_tags': 5
    },
    'build': {'context': '.', 'dockerfile': './Dockerfile'},
    'environments': {
        'staging': {
            'domain': '$STAGING_DOMAIN',
            'doppler_environment': 'staging'
        },
        'production': {
            'domain': '$PROD_DOMAIN',
            'doppler_environment': 'production'
        }
    },
    'env_vars': ['HELLO', 'E2E_TEST'],
    'coolify_app_ids': {'staging': None, 'production': None}
}
with open(path, 'w') as f:
    yaml.safe_dump(d, f, sort_keys=False, default_flow_style=False)
PY

python3 -c "import yaml; yaml.safe_load(open('$YAML_PATH'))" \
  && pass "coolify.yaml valid YAML" \
  || { fail "coolify.yaml failed YAML parse"; exit 1; }

# ── Step 4: validate.sh ────────────────────────────────────────────────────────

step "Step 4: validate.sh"

if bash "$SKILL_DIR/scripts/validate.sh" "$YAML_PATH" 2>&1; then
  pass "validate.sh passed"
else
  fail "validate.sh failed — aborting before any Coolify mutation"
  exit 1
fi

# ── Step 5: provision.sh ───────────────────────────────────────────────────────

step "Step 5: provision.sh (creates Coolify apps + Doppler service tokens)"

# provision.sh runs validate.sh internally as its first step — that's fine (idempotent)
if bash "$SKILL_DIR/scripts/provision.sh" "$YAML_PATH" 2>&1; then
  pass "provision.sh completed"
else
  fail "provision.sh failed"
  exit 1
fi

# Read back the app UUIDs written by provision.sh into coolify.yaml
eval "$(python3 -c "
import yaml
d=yaml.safe_load(open('$YAML_PATH'))
ids=d.get('coolify_app_ids',{})
print(f\"STG_APP_UUID='{ids.get('staging','')}'\")
print(f\"PRD_APP_UUID='{ids.get('production','')}'\")
")"

if [ -n "$STG_APP_UUID" ] && [ -n "$PRD_APP_UUID" ]; then
  pass "app UUIDs written back: staging=$STG_APP_UUID production=$PRD_APP_UUID"
  # Extract Coolify project UUID for cleanup
  COOLIFY_PROJECT_UUID=$(coolify_curl GET "/projects" | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    if p.get('name')=='$TEST_PROJECT': print(p.get('uuid','')); break
")
else
  fail "coolify_app_ids not written back to coolify.yaml"
  exit 1
fi

# ── Step 6: Trigger staging deploy ────────────────────────────────────────────

step "Step 6: Trigger staging deploy"

# Update the staging app's image tag to 'latest' (provision.sh defaults to 'main')
coolify_curl PATCH "/applications/$STG_APP_UUID" \
  '{"docker_registry_image_tag": "latest"}' >/dev/null 2>&1
echo "  patched staging app image tag → latest"

DEPLOYMENT_UUID=$(coolify_deploy_app "$STG_APP_UUID")
if [ -n "$DEPLOYMENT_UUID" ]; then
  pass "deploy triggered: deployment_uuid=$DEPLOYMENT_UUID"
else
  fail "deploy trigger returned no deployment UUID"
  exit 1
fi

# ── Step 7: Poll deployment status ────────────────────────────────────────────

step "Step 7: Wait for deploy to finish (timeout: ${DEPLOY_TIMEOUT}s)"

START_TS=$(date +%s)
DEPLOY_STATUS="unknown"
while true; do
  DEPLOY_STATUS=$(coolify_curl GET "/deployments/$DEPLOYMENT_UUID" 2>/dev/null \
    | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('status','unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")

  NOW_TS=$(date +%s)
  ELAPSED=$((NOW_TS - START_TS))
  echo "  [${ELAPSED}s] deploy status: $DEPLOY_STATUS"

  case "$DEPLOY_STATUS" in
    finished) break ;;
    error|failed|cancelled)
      fail "deploy ended with status: $DEPLOY_STATUS"
      echo "  Check Coolify dashboard for logs: $COOLIFY_URL"
      exit 1
      ;;
  esac

  if (( ELAPSED > DEPLOY_TIMEOUT )); then
    fail "deploy did not finish within ${DEPLOY_TIMEOUT}s (last status: $DEPLOY_STATUS)"
    exit 1
  fi
  sleep 10
done

pass "deploy finished (took $(($(date +%s) - START_TS))s)"

# ── Step 8: Verify app is running via Coolify API ─────────────────────────────

step "Step 8: Verify app status via Coolify API"

APP_STATUS=$(coolify_curl GET "/applications/$STG_APP_UUID" 2>/dev/null \
  | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('status','unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")

echo "  staging app status: $APP_STATUS"
if [ "$APP_STATUS" = "running" ]; then
  pass "staging app is running"
else
  fail "staging app status is '$APP_STATUS' (expected 'running')"
  # Don't exit — still attempt the HTTP smoke test; status field may lag
fi

# ── Step 9: HTTP smoke test ────────────────────────────────────────────────────

step "Step 9: HTTP smoke test — https://${STAGING_DOMAIN} (timeout: ${SMOKE_TIMEOUT}s)"
echo "  (Let's Encrypt cert issuance takes ~30-60s on first use for a new domain)"

START_TS=$(date +%s)
SMOKE_PASSED=false

while true; do
  ELAPSED=$(($(date +%s) - START_TS))

  # Check /api/health — must return HTTP 200
  HEALTH_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    "https://${STAGING_DOMAIN}/api/health" 2>/dev/null || echo "000")

  echo "  [${ELAPSED}s] /api/health → HTTP $HEALTH_CODE"

  if [ "$HEALTH_CODE" = "200" ]; then
    # Also verify the smoke-test string is in the root page
    BODY=$(curl -sf --max-time 10 "https://${STAGING_DOMAIN}/" 2>/dev/null || echo "")
    if echo "$BODY" | grep -q "claude-skills-deploy-e2e-ok"; then
      SMOKE_PASSED=true
      break
    else
      echo "  /api/health returned 200 but root page body check failed — retrying"
    fi
  fi

  if (( ELAPSED > SMOKE_TIMEOUT )); then
    echo "  smoke test timed out after ${SMOKE_TIMEOUT}s"
    break
  fi
  sleep 10
done

if $SMOKE_PASSED; then
  pass "smoke test: https://${STAGING_DOMAIN}/api/health returned 200 + body check passed"
else
  fail "smoke test: could not reach https://${STAGING_DOMAIN} within ${SMOKE_TIMEOUT}s"
  echo "  This may be a Let's Encrypt cert delay. The deploy itself finished successfully."
  echo "  Verify manually: curl https://${STAGING_DOMAIN}/api/health"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
# Cleanup runs via trap EXIT
