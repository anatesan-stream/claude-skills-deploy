# Architecture

**Analysis Date:** 2026-05-21

## Pattern Overview

**Overall:** Claude Code skill — a directory of shell scripts invoked by a Claude Code session via `SKILL.md`, operating as a thin orchestration layer over two external REST APIs (Coolify and Doppler) and one SSH connection.

**Key Characteristics:**
- No build step, no runtime daemon — the skill is executed procedurally by Claude on demand
- All domain-specific values are external to the skill (in `coolify.yaml` per-repo and `~/.claude/coolify.json` per-machine); the scripts contain zero hardcoded project names, URLs, or credentials
- Idempotent by design — every provisioning operation is a lookup-then-create-if-missing; re-running is safe
- Same-image promotion model: one Docker image is built, deployed to staging, smoke-tested, then promoted to production by pointer change (no rebuild)

## Layers

**Skill Entry Point:**
- Purpose: Claude Code reads `SKILL.md` to understand how to invoke the skill and which subcommand to route to
- Location: `SKILL.md`
- Contains: Skill metadata (`name`, `allowed-tools`, `argument-hint`), routing logic description, execution flow spec
- Depends on: Nothing — read by Claude, not executed
- Used by: Claude Code session when user runs `/setup-coolify [init|validate]`

**Orchestration Scripts:**
- Purpose: High-level workflow controllers that sequence API calls and validate state
- Location: `scripts/provision.sh`, `scripts/validate.sh`, `scripts/generate-workflow.sh`
- Contains: YAML parsing (via inline `python3`), control flow, error handling, SSH calls
- Depends on: `scripts/lib-coolify-api.sh`, `scripts/lib-doppler-api.sh`, `~/.claude/coolify.json`, `./coolify.yaml`
- Used by: Claude (via `SKILL.md` instructions), `init/init.sh`, `test/e2e.sh`

**API Library Layer:**
- Purpose: Reusable Bash functions wrapping Coolify REST API and Doppler CLI
- Location: `scripts/lib-coolify-api.sh`, `scripts/lib-doppler-api.sh`
- Contains: `coolify_curl`, `coolify_upsert_project`, `coolify_find_app_by_name`, `coolify_set_app_envs`, `coolify_deploy_app`, `doppler_check_key`, `doppler_create_service_token`
- Depends on: `curl`, `doppler` CLI, `python3`, `~/.claude/coolify.json`
- Used by: `provision.sh`, `validate.sh`, `generate-workflow.sh`, `test/e2e.sh`

**Bootstrap Layer:**
- Purpose: Interactive one-time setup for a new target repo — generates `coolify.yaml` and `.github/workflows/deploy.yml` from templates
- Location: `init/init.sh`, `init/templates/coolify.yaml.tmpl`
- Contains: Prompts for project parameters, Python-based template rendering, calls to `generate-workflow.sh`
- Depends on: `init/templates/coolify.yaml.tmpl`, `scripts/generate-workflow.sh`, Python3 + PyYAML
- Used by: Human operator (run once per new repo)

**Generated CI Pipeline:**
- Purpose: GitHub Actions workflow that implements the build-once / deploy-twice pipeline
- Location: Written to `<target-repo>/.github/workflows/deploy.yml` by `generate-workflow.sh`
- Contains: `build` job (Docker build + push to GHCR), `deploy-staging` job, `deploy-production` job (triggered only after staging smoke test), `ghcr-cleanup` job
- Depends on: `COOLIFY_API_KEY` GitHub secret, Coolify app UUIDs embedded at generation time from `coolify_app_ids` in `coolify.yaml`
- Used by: GitHub Actions on every push to `main`

## Data Flow

**Provision flow (`/setup-coolify`):**

1. Claude reads `SKILL.md`, calls `bash scripts/validate.sh ./coolify.yaml`
2. `validate.sh` parses `coolify.yaml` via `python3 yaml.safe_load`, resolves server alias from `~/.claude/coolify.json`, calls Coolify `GET /projects` to verify reachability, calls `doppler secrets get` for every key in `env_vars`
3. If validate passes, Claude calls `bash scripts/provision.sh ./coolify.yaml`
4. `provision.sh` calls Coolify REST API to upsert project and per-environment apps (lookup by name, create if absent)
5. For each environment: SSHes to the Coolify VPS to run `docker volume create ${APP_UUID}-doppler-cache`
6. Creates Doppler service token scoped to the environment config, sets `DOPPLER_TOKEN` + all `env_vars` as Coolify runtime env vars via `PATCH /applications/{uuid}/envs/bulk`
7. Verifies `custom_docker_run_options` round-tripped the volume mount (hard fail if not)
8. Writes resulting app UUIDs back to `coolify.yaml` under `coolify_app_ids`
9. Triggers initial deploy via `GET /deploy?uuid=<uuid>&force=false`

**Runtime secrets flow (container start):**

1. Coolify starts container with `DOPPLER_TOKEN` env var (service token scoped to env)
2. Container `ENTRYPOINT` is `doppler run --fallback /etc/doppler-cache/secrets.json --`
3. Doppler CLI fetches all secrets for the project/config, injects them as env vars, then exec's the app
4. `/etc/doppler-cache` is a Docker volume created by `provision.sh` — provides fallback if Doppler API is unreachable

**CI deploy flow (git push to main):**

1. GitHub Actions `build` job: `docker build` with no env-specific args, tags with `${GITHUB_SHA:0:7}`, pushes to GHCR
2. `deploy-staging` job: `PATCH /applications/$STAGING_APP_UUID` to set new tag, `GET /deploy?uuid=...`, polls HTTPS health endpoint for up to 6 minutes
3. `deploy-production` job: `PATCH /applications/$PROD_APP_UUID` with the **same** tag (no rebuild), triggers deploy

**State Management:**
- `coolify_app_ids` in `coolify.yaml` is the only mutable state owned by this skill — written by `provision.sh` after first successful run to cache UUIDs and avoid repeated API lookups
- `~/.claude/coolify.json` is immutable from the skill's perspective (written only by `/setup-coolify init`)
- All other state lives in Coolify (app configs, deployment records) and Doppler (secret values, service tokens)

## Key Abstractions

**Server alias:**
- Purpose: Decouples repo config (`coolify.yaml`) from machine credentials (`~/.claude/coolify.json`). `server: vultr-stream` in `coolify.yaml` maps to the full URL, API key, Doppler account, and SSH host in `coolify.json`
- Pattern: String key lookup in `~/.claude/coolify.json servers` object
- Functions: `coolify_load_server "$SERVER_ALIAS"` (sets `COOLIFY_URL`, `COOLIFY_API_KEY`), `doppler_load_account "$SERVER_ALIAS"` (sets `DOPPLER_ACCOUNT`)

**Lookup-by-name (no hardcoded UUIDs):**
- Purpose: Makes scripts portable across Coolify instances and resilient to manual changes in the Coolify UI
- Pattern: `coolify_find_app_by_name "$APP_NAME"` returns UUID or empty string; caller creates if empty
- Applied to: project UUID, server UUID, destination UUID, app UUID

**Same-image promotion:**
- Purpose: Ensures staging and production run byte-identical Docker images; prevents the "works on staging, breaks on prod" class of bugs caused by environment-specific builds
- Constraint: No `--build-arg` may reference env-specific values. `generate-workflow.sh` includes a guard that exits with error if `NEXT_PUBLIC_BASE_URL` appears as a build-arg in the generated YAML.

## One-Time Setup Flow

Per `docs/architecture.md`, these 7 steps run once per domain/Coolify instance (steps ①–③ and ⑤–⑦ are CLI; only step ④ requires a browser):

| Step | Action |
|------|--------|
| ① | `git clone claude-skills-deploy → ~/.claude/skills/setup-coolify/` |
| ② | Configure `~/.claude/coolify.json` (Coolify URL, API key, Doppler account, ssh_host) |
| ③ | `bash init/init.sh` in target repo → writes `coolify.yaml` + `.github/workflows/deploy.yml` |
| ④ | Create Doppler project + `staging`/`production` configs + seed secrets (**browser step**) |
| ⑤ | `/setup-coolify validate` — dry-run; no mutations |
| ⑥ | `/setup-coolify` — provisions Coolify apps, creates Docker volumes, wires Doppler tokens, writes back UUIDs |
| ⑦ | `git add coolify.yaml deploy.yml && git push` — activates GitHub Actions pipeline |

## What Lives Where After Setup

| Location | Contents | Committed? |
|----------|----------|-----------|
| `~/.claude/skills/setup-coolify/` | Skill files (SKILL.md, scripts, init, docs) | No — local install |
| `~/.claude/coolify.json` | Coolify URL + API key + Doppler account + `ssh_host` | **Never** — contains secrets |
| `<target-repo>/coolify.yaml` | Deploy manifest: project slug, server alias, domains, env var names | **Yes** — no secrets |
| `<target-repo>/.github/workflows/deploy.yml` | GitHub Actions pipeline (build → GHCR → Coolify) | **Yes** |
| GHCR | Docker images tagged by git SHA; last N tags retained | N/A |
| Coolify (VPS) | Staging + production apps with `DOPPLER_TOKEN` env var | N/A |
| Doppler | Project with `staging` + `production` configs; service tokens per env | N/A |

## Entry Points

**`/setup-coolify` (provision):**
- Location: `SKILL.md` + `scripts/provision.sh`
- Triggers: Claude Code user runs `/setup-coolify` with no arguments
- Responsibilities: Full idempotent provisioning — validate, upsert Coolify resources, create Docker volumes, wire Doppler tokens, write back UUIDs, trigger deploys

**`/setup-coolify validate`:**
- Location: `SKILL.md` + `scripts/validate.sh`
- Triggers: Claude Code user runs `/setup-coolify validate`
- Responsibilities: Dry-run pre-flight — schema check, server alias lookup, Coolify API ping, Doppler key presence check. No mutations.

**`/setup-coolify init`:**
- Location: `SKILL.md`
- Triggers: Claude Code user runs `/setup-coolify init`
- Responsibilities: Interactive prompts to create/update `~/.claude/coolify.json` for a new server alias. Claude executes this directly without calling a script.

**`init/init.sh`:**
- Location: `init/init.sh`
- Triggers: Human runs `bash ~/.claude/skills/setup-coolify/init/init.sh` from target repo root
- Responsibilities: Prompts for project parameters, renders `coolify.yaml.tmpl`, calls `generate-workflow.sh`, validates output YAML

**`test/e2e.sh`:**
- Location: `test/e2e.sh`
- Triggers: Human or CI runs `bash test/e2e.sh [--server ALIAS] [--keep]`
- Responsibilities: Full end-to-end test — creates throwaway Coolify + Doppler project, provisions apps, deploys, smoke-tests live HTTPS URL, unconditional cleanup via `trap EXIT`

## Error Handling

**Strategy:** Fail fast with descriptive messages. Every error path prints `ERROR: <specific field/step>` to stderr and exits non-zero. No silent failures.

**Patterns:**
- `set -euo pipefail` in all scripts — any unhandled non-zero exit propagates immediately
- `validate.sh` accumulates errors into a counter and prints all failures before exiting — gives the operator a complete list rather than stopping at the first missing key
- `provision.sh` runs `validate.sh` as its first step and aborts before touching Coolify if validation fails
- Volume mount round-trip verification: `provision.sh` reads back `custom_docker_run_options` after PATCH and hard-fails if the mount string is absent (Coolify version compatibility guard)
- `init.sh` validates generated YAML with `python3 yaml.safe_load` and checks for unsubstituted `{{` tokens before writing output

## Cross-Cutting Concerns

**Credentials:** Never in scripts or committed files. `~/.claude/coolify.json` (API keys), `chmod 0600`. Doppler service tokens created at provision time and stored only in Coolify env vars.

**Python3 dependency:** Used inline throughout shell scripts for YAML parsing (`yaml.safe_load`), JSON construction, and field extraction. Eliminates `jq`/`yq` as external dependencies. Requires `pyyaml` (`pip3 install pyyaml`).

**Idempotency:** Every create operation is preceded by a lookup. Running `/setup-coolify` twice is safe — it will PATCH existing apps but not create duplicates.

**SSH access:** `provision.sh` SSHes to the Coolify VPS (alias from `~/.ssh/config`) to create persistent Docker volumes. This is the only operation that touches the server's filesystem directly. Required field: `ssh_host` in `~/.claude/coolify.json`.

---

*Architecture analysis: 2026-05-21*
