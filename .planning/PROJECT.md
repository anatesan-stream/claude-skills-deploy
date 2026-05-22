# claude-skills-deploy

## What This Is

A Claude Code skills repo that provides a standardized, domain-agnostic way to deploy any application onto a Coolify + Doppler managed CI/CD environment running on a VPS. The skill provisions staging and production apps, wires in Doppler secrets, and generates a same-image-promotion GitHub Actions pipeline — all from a single `coolify.yaml` manifest committed to the target repo. It is designed to be forked to support additional domains (e.g., `strategem.ai` alongside `streamlinity.com`) with zero script changes.

## Core Value

A developer can clone this repo, run one command, see a working hello-world deployment on their Coolify server, and trust the skill is correct before using it for a real application.

## Requirements

### Validated

- ✓ Idempotent Coolify provisioning via `/setup-coolify` — existing
- ✓ Dry-run pre-flight validation via `/setup-coolify validate` — existing
- ✓ Interactive repo bootstrap via `bash init/init.sh` (writes `coolify.yaml` + `deploy.yml`) — existing
- ✓ Multi-server support via `coolify.json` server alias lookup — existing
- ✓ Domain-agnostic deployment config — zero script changes between domains — existing
- ✓ Coolify app creation + bulk env var injection — existing
- ✓ Doppler service token creation and rotation per environment — existing
- ✓ Docker volume creation via SSH for Doppler fallback cache — existing
- ✓ Same-image promotion CI/CD pipeline (build once → staging → production) — existing
- ✓ Generated `.github/workflows/deploy.yml` — existing

### Active

**Bug fixes (prerequisite for passing E2E test):**
- [ ] Fix `generate-workflow.sh`: `needs: [smoke-staging, build]` → `needs: [deploy-staging, build]` — generated workflow currently invalid
- [ ] Fix `provision.sh`: silent empty-value injection when `doppler secrets get` subprocess fails — should hard-fail with specific key + error
- [ ] Fix `provision.sh`: hardcoded `coolify_get_server_uuid "localhost"` — should read from `coolify.json` with configurable `server_name` field (default `localhost`)

**Test framework:**
- [ ] Review and refine `test/e2e.sh` — full provision→deploy→smoke-test; no auto-cleanup (remove unconditional `trap EXIT` cleanup)
- [ ] Write test report to `test/results/` — staging URL, Coolify app IDs, per-step pass/fail, timestamp
- [ ] Make E2E test portable — replace hardcoded `cicd.streamlinity.com` with `E2E_BASE_DOMAIN` env var
- [ ] Add static validation of generated `deploy.yml` — YAML lint + job dependency graph check (catches job-name bugs like the `smoke-staging` issue)
- [ ] Add `test/cleanup-deployment.sh` — separate teardown script for hello-world deployment; reads app IDs from test report

### Out of Scope

- Live GitHub Actions pipeline execution as part of test — static validation covers workflow correctness; live CI adds external dependency and slow feedback
- Production deployment validation — staging smoke test is sufficient for trust signal
- Multi-node Coolify support — target architecture is single-node; `server_name` default of `localhost` covers the common case
- Per-env build mode (`build_time: true`) — field is reserved for future use; current same-image promotion model is the target behavior

## Context

- The core skill was developed and validated through the deployment of `git@github.com:anatesan-stream/ai-upskilling.git` — that work proved out the Coolify + Doppler approach
- Work is continuing in this repo after a `/clear` interrupted a previous session in a different working directory; `test/e2e.sh` exists but has not been run against real infrastructure
- The codebase audit (`CONCERNS.md`) identified 3 HIGH bugs that would cause the E2E test to fail — fixing them is the first phase of work
- Test audience: new users onboarding to the skill, maintainers running CI on this repo, developers forking for a new domain (e.g., strategem.ai)
- The hello-world test container (`test/hello-world/`) is a minimal nginx image serving `/api/health` → 200 and `index.html` with a known sentinel string
- The test should leave the hello-world deployment running so a new user can browse to the staging URL and see proof of a working deployment before running cleanup

## Constraints

- **No auto-cleanup**: E2E test must not tear down the deployment — new users need to see the result
- **Domain portability**: Any hardcoded `streamlinity.com` references in the test harness must become env vars — the test must run on any Coolify server
- **No GitHub API dependency**: Test framework must not require a live GitHub push or Actions run — runs standalone on the operator's machine
- **Bash + Python3 only**: No new language runtimes or package managers — the skill is pure shell + python3 (pyyaml); test tooling must stay in this stack

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Static workflow validation instead of live GitHub Actions run | Avoids external dependency, catches structural bugs fast (like the `smoke-staging` job name bug) | — Pending |
| No auto-cleanup in E2E test | New users need to see the deployed result to build trust in the skill | — Pending |
| Fix HIGH bugs before building test framework | E2E test would fail for the wrong reasons if workflow generation is broken | — Pending |
| `E2E_BASE_DOMAIN` env var for portability | Allows domain fork developers to run the same test against their Coolify server | — Pending |
| Test report written to `test/results/` | Persists pass/fail state and URLs between test run and cleanup; enables maintainer CI assertions | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-21 after initialization*
