---
phase: 01-bug-fixes
plan: 02
subsystem: infra
tags: [doppler, provision, error-handling, python-heredoc, bash]

# Dependency graph
requires: []
provides:
  - "provision.sh Python heredoc with returncode checking and accumulated error reporting for Doppler secrets fetch"
affects: [02-test-framework, e2e-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Accumulate-then-exit pattern: collect all failures before raising SystemExit, never fail-fast in multi-key loops"
    - "Python inline stderr: errors written to sys.stderr (not stdout) inside command substitution so stdout stays clean for JSON capture"

key-files:
  created: []
  modified:
    - scripts/provision.sh

key-decisions:
  - "D-03: Loop all env_var keys before exiting — operator sees every failing key in one run, not just the first"
  - "D-04: Per-key error format is ERROR: doppler secrets get KEY_NAME failed: <stderr> — Doppler subprocess stderr included verbatim"
  - "D-05: Explicit result.returncode != 0 check; raise SystemExit(1) after loop — propagates via set -e in parent bash"

patterns-established:
  - "Failure simulation via fake CLI shim on PATH validates error paths without real credentials"

requirements-completed: [BUG-02]

# Metrics
duration: 1min
completed: 2026-05-22
---

# Phase 01 Plan 02: Bug Fix - Doppler Silent Empty-Value Injection Summary

**Python heredoc in provision.sh now checks result.returncode, accumulates per-key (key, stderr) failures, and raises SystemExit(1) with named-key error lines after exhausting all keys**

## Performance

- **Duration:** 1 min
- **Started:** 2026-05-22T07:26:54Z
- **Completed:** 2026-05-22T07:27:54Z
- **Tasks:** 2 (1 file change + 1 validation)
- **Files modified:** 1

## Accomplishments
- Replaced 5-line silent heredoc with 12-line error-accumulating version in provision.sh
- Doppler fetch failures now produce: summary line ("N key(s) failed in project/config:") + per-key line ("ERROR: doppler secrets get KEY_NAME failed: <stderr>")
- All keys are attempted before exit — operator sees the complete failure list in one run
- Confirmed via CLI shim simulation: failure path exits 1 with correct stderr; success path exits 0 and emits valid JSON with all keys

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace Doppler fetch heredoc with returncode-checking version** - `c6d049d` (fix)
2. **Task 2: Simulate Doppler failure with fake CLI shim** - validation only, no file changes

**Plan metadata:** (docs commit — created below)

## Files Created/Modified
- `scripts/provision.sh` — Python heredoc at lines 147-169 replaced: added `failures = []`, `if result.returncode != 0: failures.append(...)`, post-loop `if failures: ... raise SystemExit(1)`

## Decisions Made
- Followed D-03/D-04/D-05 from CONTEXT.md exactly — no discretion required beyond the decisions already logged
- Preserved `<<'PY'` (quoted heredoc delimiter) to prevent shell expansion inside Python body

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BUG-02 closed. provision.sh now hard-fails on Doppler secrets fetch errors with actionable error messages.
- BUG-01 (generate-workflow.sh job reference) and BUG-03 (hardcoded server UUID) addressed in plans 01-01 and 01-03 respectively.
- Phase 2 (test framework) can proceed once all three HIGH bugs are patched.

---
*Phase: 01-bug-fixes*
*Completed: 2026-05-22*

## Self-Check: PASSED

- FOUND: scripts/provision.sh
- FOUND: .planning/phases/01-bug-fixes/01-02-SUMMARY.md
- FOUND: commit c6d049d
