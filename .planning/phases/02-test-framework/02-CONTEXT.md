# Phase 2: Test Framework - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Modify `test/e2e.sh` to satisfy TEST-01 through TEST-05: remove auto-teardown on success, add JSON report writing, add `E2E_SERVER`/`E2E_BASE_DOMAIN` env var support, and print a completion summary. Create `test/validate-workflow.sh` from scratch for VALID-01 and VALID-02. No new scripts beyond these two files.

</domain>

<decisions>
## Implementation Decisions

### Teardown behavior (TEST-03)
- **D-01:** On successful completion, do NOT tear down — staging app and production app both remain running. The `trap EXIT` cleanup runs only when the script exits non-zero (failure path). `--keep` flag continues to suppress cleanup on failures as a debugging affordance.
- **D-02:** On success, keep both staging and production apps (do not selectively delete the production app). Both are mentioned in the completion summary.

### E2E server + domain configuration (TEST-04)
- **D-03:** `E2E_SERVER` env var overrides the server alias (default: `vultr-stream`). The existing `--server ALIAS` flag also continues to work, with `--server` taking precedence over `E2E_SERVER`.
- **D-04:** `E2E_BASE_DOMAIN` env var overrides the base domain (default: `cicd.streamlinity.com`). The staging/production domains are constructed as `${TEST_PROJECT}-staging.${E2E_BASE_DOMAIN}` and `${TEST_PROJECT}-production.${E2E_BASE_DOMAIN}`.
- **D-05:** Script header comment must clearly document both defaults and say "change these for other domains."

### JSON test report (TEST-02)
- **D-06:** Write report to `test/results/YYYYMMDD-HHMMSS.json` (create `test/results/` directory if missing). Report contains: `staging_url`, `project_uuid`, `staging_app_uuid`, `production_app_uuid`, `run_timestamp` (ISO 8601), `server_alias`, `steps` array (each step: `name`, `passed` boolean, `detail` string). Use Python inline to construct and write the JSON.
- **D-07:** Write the report just before the final completion summary, whether the test passed or failed (so a failed run also leaves a report for diagnostics).

### Completion summary (TEST-05)
- **D-08:** On success, print a summary block showing: staging URL, report file path, and the exact next command `bash test/cleanup-deployment.sh <report-file>`. Match the visual style of the existing step headers (`═══...═══` border).

### validate-workflow.sh scope (VALID-01, VALID-02)
- **D-09:** Strict minimum — only two checks: (1) YAML parses without error (VALID-01), (2) every job name in every `needs:` list exists as a defined job in the same file (VALID-02). No additional structural checks.
- **D-10:** On VALID-02 failure, print the offending `needs:` reference AND the job name that does not exist. Exit code 1. On success, print "OK: YAML syntax valid" and "OK: all needs references resolve" and exit 0.
- **D-11:** `validate-workflow.sh` lives at `test/validate-workflow.sh` (alongside `e2e.sh`), not in `scripts/`. It is a standalone script — no library sourcing required.

### Claude's Discretion
- Exact Python inline structure for JSON report construction (flat dict or helper function — whichever is cleaner)
- Whether to accumulate all VALID-02 failures and report them all at once before exiting, or exit on first offending reference

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing files to modify
- `test/e2e.sh` — full file; the teardown logic, configuration section, and final summary are the main change areas
- `scripts/lib-coolify-api.sh` — `coolify_load_server` function pattern (for reading coolify.json); sourced by e2e.sh
- `scripts/lib-doppler-api.sh` — `doppler_load_account` pattern; also sourced by e2e.sh

### Supporting references
- `.planning/codebase/TESTING.md` — full E2E test flow description, existing step structure, fixture image details
- `.planning/codebase/CONVENTIONS.md` — section divider style (`# ── Section name ──`), Python inline heredoc pattern (`<<'PY'`), `set -euo pipefail` requirement
- `.planning/codebase/STRUCTURE.md` — `test/` directory layout; where to add `test/results/` and `test/validate-workflow.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `pass()`, `fail()`, `step()` helpers in `test/e2e.sh` — already defined; use the same pattern in `validate-workflow.sh` if step output is needed
- `coolify_load_server` / `doppler_load_account` in libs — already sourced in `e2e.sh`; the server alias loading logic can reference `E2E_SERVER` before sourcing the libs

### Established Patterns
- `trap cleanup EXIT` — already in `e2e.sh`; needs conditional logic on `$?` inside `cleanup()` to distinguish success from failure
- Python inline with `<<'PY'` heredoc — already used throughout `e2e.sh` for JSON parsing; use same for report construction
- `SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` — self-location pattern for `validate-workflow.sh` (though it doesn't source any libs, still good practice)

### Integration Points
- `test/results/` — new directory; `e2e.sh` creates it with `mkdir -p test/results/` before writing the report
- `test/validate-workflow.sh` — standalone; invoked directly by operator or by e2e.sh smoke-test equivalent; no lib sourcing needed
- The existing `--keep` flag in `e2e.sh` interacts with the new teardown logic: on success the trap is a no-op regardless of `--keep`; on failure `--keep` suppresses cleanup

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the decisions above — open to standard approaches for the mechanical parts.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-test-framework*
*Context gathered: 2026-05-22*
