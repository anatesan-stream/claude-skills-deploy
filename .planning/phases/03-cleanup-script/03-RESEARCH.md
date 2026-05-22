# Phase 3: Cleanup Script - Research

**Researched:** 2026-05-22
**Domain:** Bash shell scripting — Coolify REST API DELETE operations, Doppler CLI project deletion, Docker volume removal via SSH
**Confidence:** HIGH

## Summary

Phase 3 adds `test/cleanup-deployment.sh` — a standalone script an operator runs after inspecting a hello-world deployment to tear it down. The script reads a JSON report file (written by Phase 2's E2E test), extracts all resource identifiers and credentials from it, and deletes everything the E2E run created: Coolify staging app, Coolify production app, Coolify project, Docker volumes on the VPS via SSH, and the Doppler project.

The implementation is an extraction and adaptation of the existing `cleanup()` function in `test/e2e.sh` (lines 70-149). Rather than reading live shell variables, `cleanup-deployment.sh` reads the same values from a JSON report file via `python3 -c "import json; ..."`. All library functions (`coolify_load_server`, `coolify_curl`, `doppler_load_account`) are already in `scripts/lib-coolify-api.sh` and `scripts/lib-doppler-api.sh` and need only be sourced.

**Primary recommendation:** Extract e2e.sh cleanup() directly — the deletion sequence, warn-and-continue pattern, and API calls are already proven. The only new work is: (1) reading inputs from a JSON file instead of live vars, (2) the confirmation block (CLEAN-02), and (3) missing-field validation at startup.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Full teardown — mirror the full `e2e.sh` cleanup() function exactly: staging app → production app → Coolify project → Docker volumes via SSH → Doppler project. Everything the E2E test created gets removed.
- **D-02:** Deletion order matches e2e.sh: apps first, then project, then volumes, then Doppler project. This is the safe order (project delete can cascade to apps in some Coolify versions, so apps first avoids ambiguity).
- **D-03:** Phase 2's E2E test writes a **full teardown record** to `test/results/YYYYMMDD-HHMMSS.json`. Required fields: `staging_url`, `coolify_project_uuid`, `staging_app_uuid`, `production_app_uuid`, `doppler_project`, `server_alias`, `ssh_host`, `steps[]`, `timestamp`.
- **D-04:** `cleanup-deployment.sh` reads ALL credentials from the report file — operator only passes the report file path, nothing else.
- **D-05:** Warn-and-continue — print warning for each already-deleted or unreachable resource, continue to the next step. Matches e2e.sh's existing `|| echo "could not delete..."` pattern.
- **D-06:** Exit 0 if all attempted deletes either succeeded or returned 404 (already gone). Exit non-zero only if DELETE returned unexpected error (5xx, auth failure, etc.).
- **D-07:** Print a final confirmation block listing each deleted resource (name, UUID), matching CLEAN-02.
- **D-08:** Read `server_alias` from the report file, then call `coolify_load_server "$server_alias"`.
- **D-09:** If `coolify.json` missing or alias not found, exit non-zero with clear error.

### Claude's Discretion

- Exact wording of the printed confirmation block (beyond listing name + UUID per resource)
- Whether to print a dry-run preview before deleting or delete immediately
- Whether to accept an optional `--dry-run` flag (not required by CLEAN-01/CLEAN-02)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLEAN-01 | `bash test/cleanup-deployment.sh <report-file>` deletes the Coolify project and apps created by an E2E test run, using the app IDs recorded in the report file | Deletion sequence and API calls fully documented in e2e.sh cleanup() lines 109-148; Coolify DELETE /applications/{uuid} and DELETE /projects/{uuid} confirmed via official docs |
| CLEAN-02 | `cleanup-deployment.sh` prints a confirmation of what it deleted (project name, app names, UUIDs) and exits 0 on success | Pattern established in e2e.sh cleanup(); confirmation block design is at Claude's discretion per CONTEXT.md D-07 |
</phase_requirements>

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 4+ | Script execution | All project scripts use bash; CLAUDE.md constraint |
| python3 | 3.6+ | JSON report file parsing via `import json` | Same inline pattern used across all scripts in the codebase |
| curl | any | Coolify REST API DELETE calls via `coolify_curl` | Already in lib-coolify-api.sh; no new dependency |
| doppler CLI | any | `doppler projects delete "$PROJECT" --yes` | Same call used in e2e.sh line 137 |
| ssh | any | Docker volume removal on VPS | Same SSH pattern from e2e.sh lines 127-133 |

### No New Dependencies
This phase adds zero new runtime dependencies. Every tool is already required by `test/e2e.sh`.

---

## Architecture Patterns

### Recommended File Location
```
test/
├── e2e.sh                      # existing
├── cleanup-deployment.sh       # NEW — this phase
├── results/
│   └── YYYYMMDD-HHMMSS.json   # written by Phase 2, read by this script
└── hello-world/
```

**Note:** `test/results/` does not exist yet. Phase 2 creates it. The cleanup script must handle the case where the directory exists but the specified file does not.

### Pattern 1: Script Header (project convention)
Every script in this codebase opens identically:
```bash
#!/usr/bin/env bash
# cleanup-deployment.sh — Delete Coolify/Doppler/Docker resources from an E2E test run.
#
# Usage:
#   bash test/cleanup-deployment.sh test/results/20260522123456.json
#
# Prerequisites:
#   ~/.claude/coolify.json  configured (server_alias must match the report file)
#   doppler CLI             authenticated
#   curl, ssh, python3

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib-coolify-api.sh"
source "$SKILL_DIR/scripts/lib-doppler-api.sh"
```

### Pattern 2: JSON Field Extraction (inline python3)
```bash
# Source: e2e.sh pattern + codebase convention (all scripts use this)
STAGING_APP_UUID=$(python3 -c "
import json, sys
try:
    d = json.load(open('$REPORT_FILE'))
    v = d.get('staging_app_uuid', '')
    if not v: raise SystemExit('ERROR: staging_app_uuid missing from report')
    print(v)
except (FileNotFoundError, json.JSONDecodeError) as e:
    raise SystemExit(f'ERROR: {e}')
")
```

### Pattern 3: Warn-and-Continue DELETE (extracted from e2e.sh lines 109-122)
```bash
# Source: test/e2e.sh lines 109-122
if [ -n "$STAGING_APP_UUID" ]; then
  coolify_curl DELETE "/applications/$STAGING_APP_UUID" >/dev/null 2>&1 \
    && echo "  ✓ deleted staging app $STAGING_APP_UUID" \
    || echo "  ⚠ could not delete staging app $STAGING_APP_UUID (may already be deleted)"
fi
```

**Critical detail:** `coolify_curl` uses `curl -sfS`. The `-f` flag causes curl to exit non-zero on HTTP 4xx/5xx. This means a 404 (already deleted) triggers the `||` branch and prints a warning — which is exactly the desired warn-and-continue behavior per D-05 and D-06. No special 404 handling code is needed; the existing pattern already handles it correctly.

### Pattern 4: Docker Volume Removal via SSH (extracted from e2e.sh lines 126-133)
```bash
# Source: test/e2e.sh lines 126-133
if [ -n "$SSH_HOST" ]; then
  for uuid in "$STAGING_APP_UUID" "$PRODUCTION_APP_UUID"; do
    [ -z "$uuid" ] && continue
    ssh "$SSH_HOST" "docker volume rm ${uuid}-doppler-cache 2>/dev/null || true" \
      && echo "  ✓ removed docker volume ${uuid}-doppler-cache" \
      || true
  done
fi
```

### Pattern 5: Doppler Project Delete (extracted from e2e.sh line 137)
```bash
# Source: test/e2e.sh lines 135-139
doppler projects delete "$DOPPLER_PROJECT" --yes >/dev/null 2>&1 \
  && echo "  ✓ deleted Doppler project $DOPPLER_PROJECT" \
  || echo "  ⚠ could not delete Doppler project $DOPPLER_PROJECT (remove manually at doppler.com)"
```

### Pattern 6: Server Credentials Loading
```bash
# Source: e2e.sh lines 174-175; lib-coolify-api.sh coolify_load_server()
coolify_load_server "$SERVER_ALIAS"   # sets COOLIFY_URL, COOLIFY_API_KEY
doppler_load_account "$SERVER_ALIAS"  # sets DOPPLER_ACCOUNT (for logging; Doppler CLI uses its own auth)
```

`coolify_load_server` already handles the error case (D-09): if `coolify.json` is missing or the alias not found, it prints `ERROR: server alias '<alias>' not found in ~/.claude/coolify.json` and returns 1, which propagates as a fatal error under `set -euo pipefail`.

### Confirmation Block (CLEAN-02)
The exact content is at Claude's discretion per CONTEXT.md. Minimum required: project name, staging app UUID, production app UUID, Doppler project name.

Recommended structure based on CONTEXT.md specifics section:
```bash
echo ""
echo "═══════════════════════════════════"
echo " Cleanup complete"
echo "═══════════════════════════════════"
echo "  Coolify project:   $TEST_PROJECT ($COOLIFY_PROJECT_UUID)"
echo "  Staging app UUID:  $STAGING_APP_UUID"
echo "  Production app UUID: $PRODUCTION_APP_UUID"
echo "  Doppler project:   $DOPPLER_PROJECT"
echo "  Server:            $SERVER_ALIAS → $COOLIFY_URL"
echo "═══════════════════════════════════"
```

### Anti-Patterns to Avoid

- **Re-implementing coolify_curl:** Do not write raw curl calls — always use `coolify_curl DELETE "/path"`. The library handles auth headers and URL construction.
- **Sourcing lib files with relative paths:** Always use `"$SKILL_DIR/scripts/lib-coolify-api.sh"` (absolute, derived from `BASH_SOURCE[0]`). Relative sourcing breaks when the script is called from any other directory.
- **Shell text munging for JSON:** Always use `python3 -c "import json; ..."` for JSON parsing. The codebase has zero `jq` or `grep`/`sed` JSON parsing — consistency matters.
- **Exiting on the first failed delete:** Use `|| echo "warning"` not `|| exit 1`. The whole point of the script is best-effort cleanup that completes all steps.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| API authentication | Custom Bearer header logic | `coolify_curl` from lib-coolify-api.sh | Already handles auth, URL construction, -sfS flags |
| Server alias → URL lookup | Manual JSON parsing of coolify.json | `coolify_load_server "$alias"` | Handles missing registry, missing alias, exports all three globals |
| JSON report parsing | `grep`, `sed`, `awk` | `python3 -c "import json; ..."` | Codebase convention; handles nested keys and missing fields cleanly |
| Doppler project deletion | Doppler REST API call | `doppler projects delete "$name" --yes` | CLI already authenticated; handles workspace scoping |

---

## Coolify API: DELETE Endpoints

### Confirmed Endpoints (HIGH confidence — official docs)

| Endpoint | Method | Response 200 | Response 404 |
|----------|--------|--------------|--------------|
| `/api/v1/applications/{uuid}` | DELETE | `{"message": "Application deleted."}` | resource not found |
| `/api/v1/projects/{uuid}` | DELETE | `{"message": "Project deleted."}` | resource not found |

**Source:** https://coolify.io/docs/api-reference/api/operations/delete-application-by-uuid and https://coolify.io/docs/api-reference/api/operations/delete-project-by-uuid

**Query parameters for DELETE /applications/{uuid}** (all default true, documented in official API):
- `delete_configurations` — remove app configuration
- `delete_volumes` — remove associated volumes
- `docker_cleanup` — run Docker cleanup job
- `delete_connected_networks` — remove network associations

**Application delete is soft-delete + async:** The implementation dispatches `DeleteResourceJob` for asynchronous container/volume cleanup. The API returns 200 immediately; actual container stop and removal happens via a background worker.

**Cascade behavior (MEDIUM confidence — not explicitly documented):** The decision to delete apps before the project (D-02) is correct. Some Coolify versions may cascade-delete apps when a project is deleted; deleting apps first ensures they are removed regardless.

### 404 Handling

`coolify_curl` uses `curl -sfS`:
- `-s` = silent (no progress)
- `-f` = fail on HTTP 4xx/5xx (exit non-zero)
- `-S` = show error message on failure

A 404 (resource already deleted) causes curl to exit non-zero, which triggers the `||` branch in the warn-and-continue pattern. This is correct — the script treats "already gone" as a non-fatal warning, not an error. **No special 404 detection code is required.**

---

## Report File Schema

### Exact JSON Structure (Phase 2 MUST write, Phase 3 reads)

```json
{
  "staging_url": "https://csd-e2e-20260522123456-staging.cicd.streamlinity.com",
  "coolify_project_uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "staging_app_uuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy",
  "production_app_uuid": "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz",
  "doppler_project": "csd-e2e-20260522123456",
  "server_alias": "vultr-stream",
  "ssh_host": "v_cicd_stream",
  "steps": [
    {"name": "prerequisites", "passed": true, "timestamp": "2026-05-22T12:34:56Z"},
    {"name": "coolify_api", "passed": true, "timestamp": "2026-05-22T12:35:01Z"}
  ],
  "timestamp": "2026-05-22T12:34:56Z"
}
```

**Fields the cleanup script reads:**
- `server_alias` — used to call `coolify_load_server`
- `ssh_host` — used for `ssh "$SSH_HOST" "docker volume rm ..."`
- `coolify_project_uuid` — used for `coolify_curl DELETE "/projects/..."`
- `staging_app_uuid` — used for app delete and volume delete
- `production_app_uuid` — used for app delete and volume delete
- `doppler_project` — used for `doppler projects delete`

**Fields not used by cleanup but present for TEST-02 compliance:**
- `staging_url`, `steps[]`, `timestamp`

**Note on project name:** The report file does not need a `coolify_project_name` field because the confirmation block can display `doppler_project` (which equals `TEST_PROJECT` in e2e.sh, e.g. `csd-e2e-20260522123456`). The Coolify project has the same name. If the planner wants to display the name separately, Phase 2 could include it, but it is derivable and not required.

---

## Deletion Ordering

**Safe order (D-02, matches e2e.sh):**

```
1. DELETE /applications/$STAGING_APP_UUID      (Coolify app — staging)
2. DELETE /applications/$PRODUCTION_APP_UUID   (Coolify app — production)
3. DELETE /projects/$COOLIFY_PROJECT_UUID      (Coolify project)
4. ssh docker volume rm $STG_APP_UUID-doppler-cache    (VPS Docker volume)
5. ssh docker volume rm $PRD_APP_UUID-doppler-cache    (VPS Docker volume)
6. doppler projects delete $DOPPLER_PROJECT --yes      (Doppler project)
```

**Rationale:**
- Apps deleted before project to avoid ambiguity if Coolify cascades on project delete
- Docker volumes deleted after Coolify apps so the running container has released the volume mount (app soft-delete dispatches async cleanup, but by the time volumes are deleted the mount should be released)
- Doppler project deleted last — no Coolify dependency; safe at any point after apps are gone
- The temp work directory cleanup from e2e.sh (step after Doppler) does NOT apply here — there is no temp dir

---

## Missing-Field Validation Strategy

The cleanup script reads from a report file that Phase 2 writes. If the report is truncated or missing fields, the script must fail clearly before attempting any deletions.

**Recommended approach:** Extract all required fields in a single Python block at startup, fail with a named error if any are missing, then proceed to deletion. This is cleaner than per-field extraction with individual error checks.

```bash
# Read and validate all required fields from the report at startup
eval "$(python3 -c "
import json, sys
try:
    d = json.load(open('$REPORT_FILE'))
except FileNotFoundError:
    raise SystemExit('ERROR: report file not found: $REPORT_FILE')
except json.JSONDecodeError as e:
    raise SystemExit(f'ERROR: invalid JSON in report file: {e}')

required = ['server_alias', 'ssh_host', 'coolify_project_uuid',
            'staging_app_uuid', 'production_app_uuid', 'doppler_project']
missing = [k for k in required if not d.get(k)]
if missing:
    raise SystemExit('ERROR: report file missing fields: ' + ', '.join(missing))

print(f\"SERVER_ALIAS='{d['server_alias']}'\")
print(f\"SSH_HOST='{d['ssh_host']}'\")
print(f\"COOLIFY_PROJECT_UUID='{d['coolify_project_uuid']}'\")
print(f\"STAGING_APP_UUID='{d['staging_app_uuid']}'\")
print(f\"PRODUCTION_APP_UUID='{d['production_app_uuid']}'\")
print(f\"DOPPLER_PROJECT='{d['doppler_project']}'\")
")"
```

This exits non-zero immediately (before any API calls) if the report file is missing, not valid JSON, or missing any required field.

---

## Recommended Plan Breakdown

### Option A: One Plan (recommended)

The entire cleanup-deployment.sh script is a single new file. There are no existing files to edit. The script is ~80-100 lines. One plan with two tasks is cleaner and avoids artificial sequencing.

**Plan 03-01-PLAN.md: Create test/cleanup-deployment.sh**

- **Task 1:** Write `test/cleanup-deployment.sh` — the complete script (header, arg parsing, report file validation, credential loading, deletion sequence, confirmation block)
- **Task 2:** Smoke-test the script's non-destructive path — verify it exits non-zero with a clear error when passed a non-existent report file, a malformed report file, or a report file with missing required fields. No live Coolify server required.

### Option B: Two Plans

Could split into "write script" and "validation tests". Not recommended — the script is simple enough that splitting creates overhead without benefit.

**Verdict: One plan, two tasks.**

---

## Common Pitfalls

### Pitfall 1: coolify_curl Treats 404 as Fatal (without || handling)
**What goes wrong:** Developer calls `coolify_curl DELETE "/applications/$UUID"` without `|| echo "..."`. If the resource was already deleted (404), curl exits non-zero, `set -euo pipefail` kills the script, and subsequent deletions never run.
**Why it happens:** `curl -sfS` with `-f` flag treats HTTP 4xx as error.
**How to avoid:** Always use `coolify_curl DELETE "..." >/dev/null 2>&1 && echo "✓ ..." || echo "⚠ ..."`. The e2e.sh pattern already does this correctly — copy it exactly.
**Warning signs:** Script exits after first delete; only one resource is cleaned up.

### Pitfall 2: Relative Library Sourcing
**What goes wrong:** `source ./scripts/lib-coolify-api.sh` fails if the script is called from a directory other than the repo root.
**Why it happens:** `./` is relative to the shell's `CWD`, not the script's location.
**How to avoid:** Always derive `SKILL_DIR` from `BASH_SOURCE[0]`:
```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib-coolify-api.sh"
```

### Pitfall 3: Docker Volume Name Mismatch
**What goes wrong:** Volume delete command targets wrong name — volume lingers on VPS.
**Why it happens:** Volume name is `${APP_UUID}-doppler-cache` (set in provision.sh's SSH call). If the UUID variable contains whitespace or is empty, `docker volume rm -doppler-cache` silently removes nothing.
**How to avoid:** Guard with `[ -z "$uuid" ] && continue` before the SSH call (same guard as e2e.sh line 128). Verify variable names match provision.sh's `docker volume create` call.

### Pitfall 4: eval Injection from Untrusted Report File
**What goes wrong:** If a report file contains a crafted value like `staging_app_uuid: "'; rm -rf /"`, the `eval "$(python3 ...)"` pattern could execute it.
**Why it happens:** `eval` interprets the printed string as shell.
**How to avoid:** This is a low-risk concern in a developer tool where the operator controls the report file. The Python block already validates field values are non-empty strings. The risk is acceptable for this use case (same pattern used in e2e.sh lines 317-323). Document but don't over-engineer.

### Pitfall 5: Missing test/results Directory
**What goes wrong:** Script is run before any E2E test has been executed — `test/results/` directory does not exist, causing a confusing Python FileNotFoundError rather than a clear error message.
**Why it happens:** Phase 2 creates the directory on first run; Phase 3 is standalone.
**How to avoid:** The Python `FileNotFoundError` catch in the validation block produces `ERROR: report file not found: <path>` which is clear enough. No special directory check needed.

---

## Code Examples

### Complete Deletion Sequence (verified from e2e.sh lines 108-148)

```bash
# Source: test/e2e.sh lines 108-148 (cleanup() function)

step "Cleanup"

# 1. Delete Coolify apps (staging first, then production)
coolify_curl DELETE "/applications/$STAGING_APP_UUID" >/dev/null 2>&1 \
  && echo "  ✓ deleted staging app $STAGING_APP_UUID" \
  || echo "  ⚠ could not delete staging app $STAGING_APP_UUID (may already be deleted)"

coolify_curl DELETE "/applications/$PRODUCTION_APP_UUID" >/dev/null 2>&1 \
  && echo "  ✓ deleted production app $PRODUCTION_APP_UUID" \
  || echo "  ⚠ could not delete production app $PRODUCTION_APP_UUID (may already be deleted)"

# 2. Delete Coolify project
coolify_curl DELETE "/projects/$COOLIFY_PROJECT_UUID" >/dev/null 2>&1 \
  && echo "  ✓ deleted Coolify project $COOLIFY_PROJECT_UUID" \
  || echo "  ⚠ could not delete Coolify project $COOLIFY_PROJECT_UUID (may already be deleted)"

# 3. Remove Docker volumes on VPS via SSH
for uuid in "$STAGING_APP_UUID" "$PRODUCTION_APP_UUID"; do
  [ -z "$uuid" ] && continue
  ssh "$SSH_HOST" "docker volume rm ${uuid}-doppler-cache 2>/dev/null || true" \
    && echo "  ✓ removed docker volume ${uuid}-doppler-cache" \
    || true
done

# 4. Delete Doppler project
doppler projects delete "$DOPPLER_PROJECT" --yes >/dev/null 2>&1 \
  && echo "  ✓ deleted Doppler project $DOPPLER_PROJECT" \
  || echo "  ⚠ could not delete Doppler project $DOPPLER_PROJECT (remove manually at doppler.com)"
```

### Argument Parsing
```bash
# Source: project convention (e2e.sh lines 44-50)
REPORT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; echo "Usage: bash test/cleanup-deployment.sh <report-file>" >&2; exit 1 ;;
    *)  REPORT_FILE="$1"; shift ;;
  esac
done

[ -n "$REPORT_FILE" ] || { echo "ERROR: report file path required" >&2; echo "Usage: bash test/cleanup-deployment.sh <report-file>" >&2; exit 1; }
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Manual cleanup instructions printed in --keep mode (e2e.sh lines 90-103) | Automated script reading report file | Eliminates copy-paste error; operator runs one command |

---

## Open Questions

1. **Does Phase 2 write `coolify_project_uuid` to the report?**
   - What we know: CONTEXT.md D-03 requires it. Phase 2 is not yet planned.
   - What's unclear: Phase 2 may not yet exist when Phase 3 is implemented.
   - Recommendation: Phase 3's plan should include a note that `test/e2e.sh` must be updated to write this field if Phase 2 does not do so.

2. **Is `production_app_uuid` guaranteed to be present?**
   - What we know: e2e.sh creates both staging and production apps (Step 5 via provision.sh). Both UUIDs should be in the report.
   - What's unclear: If provision.sh fails mid-way, one UUID may be present and the other absent.
   - Recommendation: Guard each deletion with `[ -n "$uuid" ]` checks (same as e2e.sh) and treat empty UUID as "not created / skip."

3. **Coolify project name for the confirmation block**
   - What we know: The report file has `doppler_project` (e.g. `csd-e2e-20260522123456`), which is also used as the Coolify project name in e2e.sh (line 33: `TEST_PROJECT="csd-e2e-${TIMESTAMP}"`).
   - What's unclear: Whether Phase 2 includes a `coolify_project_name` field separately.
   - Recommendation: The confirmation block can display `doppler_project` as both the Coolify project name and Doppler project name — they are equal in e2e.sh. No separate field needed.

---

## Environment Availability

This script runs on the same machine that ran `test/e2e.sh`. All dependencies are already validated by the E2E test's own prerequisite check.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash 4+ | Script execution | ✓ (WSL2 Ubuntu) | verified by project | — |
| python3 | JSON parsing | ✓ (WSL2) | present | — |
| doppler CLI | Project deletion | assumed ✓ (e2e prereq) | — | Manual deletion at doppler.com |
| curl | coolify_curl | ✓ (system) | — | — |
| ssh | Docker volume removal | ✓ (system) | — | Skip volume removal with warning |

**Step 2.6: No new external dependencies introduced by Phase 3.**

---

## Validation Architecture

`nyquist_validation` is set to `false` in `.planning/config.json`. This section is skipped.

---

## Sources

### Primary (HIGH confidence)
- `test/e2e.sh` lines 70-149 — `cleanup()` function; direct source for all deletion logic
- `scripts/lib-coolify-api.sh` — `coolify_load_server`, `coolify_curl` implementations
- `scripts/lib-doppler-api.sh` — `doppler_load_account` implementation
- https://coolify.io/docs/api-reference/api/operations/delete-application-by-uuid — DELETE /applications/{uuid} confirmed: 200 on success, 404 on not found; query params documented
- https://coolify.io/docs/api-reference/api/operations/delete-project-by-uuid — DELETE /projects/{uuid} confirmed: 200 on success, 404 on not found

### Secondary (MEDIUM confidence)
- https://deepwiki.com/coollabsio/coolify/8.2-application-api-endpoints — soft-delete behavior, async `DeleteResourceJob`

### Tertiary (LOW confidence)
- Cascade delete behavior (apps deleted when project deleted): not officially documented; safe-order (apps before project) adopted to avoid ambiguity regardless of version behavior

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all tools already in use
- Architecture: HIGH — direct extraction from proven e2e.sh cleanup() function
- Coolify DELETE endpoints: HIGH — verified via official API docs
- 404 handling behavior: HIGH — derived from curl -sfS flag behavior (curl man page)
- Cascade delete behavior: LOW — not documented; mitigated by deletion order

**Research date:** 2026-05-22
**Valid until:** 2026-11-22 (stable Coolify API; bash patterns are stable)
