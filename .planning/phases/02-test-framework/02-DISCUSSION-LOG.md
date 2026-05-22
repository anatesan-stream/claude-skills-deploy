# Phase 2: Test Framework - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-22
**Phase:** 02-test-framework
**Areas discussed:** Teardown behavior on failure, E2E_BASE_DOMAIN default, validate-workflow.sh scope

---

## Teardown behavior on failure

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-clean on failure | Keep deployment on success (per TEST-03), but trap EXIT still cleans up orphaned resources when the script exits non-zero. Operators use --keep to preserve state for debugging failures. | ✓ |
| Never auto-clean | Script never tears down anything — operator always runs cleanup-deployment.sh manually. | |
| Always prompt | On exit, ask the operator whether to clean up. Requires interactive TTY. | |

**User's choice:** Auto-clean on failure
**Notes:** Standard trap behavior: cleanup runs on non-zero exit, no-op on exit 0.

---

## Production app on success

| Option | Description | Selected |
|--------|-------------|----------|
| Keep production app too, mention it in summary | Both staging and production apps remain. Summary lists both URLs. | ✓ |
| Delete production app on success | Production was provisioned but never deployed — deleting it keeps the Coolify project cleaner. | |

**User's choice:** Keep both, mention in summary.

---

## E2E_BASE_DOMAIN default

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as specified | vultr-stream + cicd.streamlinity.com are the correct defaults. Add header comment for other domains. | ✓ |
| No hardcoded default | Make E2E_BASE_DOMAIN required — fail fast if not set. | |

**User's choice:** Keep defaults as specified in TEST-04.

---

## validate-workflow.sh scope

| Option | Description | Selected |
|--------|-------------|----------|
| Strict minimum — VALID-01 + VALID-02 only | Only required checks. Avoids false positives. | ✓ |
| Add top-level structure check | Also verify 'on:' and 'jobs:' keys exist. | |

**User's choice:** Strict minimum.

---

## Claude's Discretion

- Exact Python inline structure for JSON report construction
- Whether to accumulate all VALID-02 failures or exit on first offending reference

## Deferred Ideas

None.
