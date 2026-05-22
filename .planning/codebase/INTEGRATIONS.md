# External Integrations

**Analysis Date:** 2026-05-21

## APIs & External Services

**Coolify (self-hosted PaaS):**
- Purpose: Application lifecycle management — create projects, upsert apps, set env vars, trigger deploys, check app/deployment status
- Client: Raw `curl` calls in `scripts/lib-coolify-api.sh` via `coolify_curl()` wrapper
- API base: `${COOLIFY_URL}/api/v1` (URL from `~/.claude/coolify.json`)
- Auth: `Authorization: Bearer ${COOLIFY_API_KEY}` (Bearer token, API key generated in Coolify UI under Settings → Keys & Tokens)
- Endpoints used:
  - `GET  /projects` — list/verify projects
  - `POST /projects` — create project
  - `GET  /servers` — resolve server UUID by name
  - `GET  /destinations` — resolve destination UUID
  - `GET  /sources` — list GitHub Apps
  - `GET  /applications` — list apps (lookup by name)
  - `POST /applications/dockerimage` (primary) or `/applications/private-github-app` (fallback) — create app
  - `PATCH /applications/{uuid}` — update image tag, domain, health check, Docker run options
  - `PATCH /applications/{uuid}/envs/bulk` — bulk set env vars
  - `GET  /deploy?uuid={uuid}&force=false` — trigger deploy
  - `GET  /deployments/{uuid}` — poll deployment status
  - `DELETE /applications/{uuid}` — cleanup (test/e2e.sh only)
  - `DELETE /projects/{uuid}` — cleanup (test/e2e.sh only)

**Doppler (secrets manager):**
- Purpose: Secret storage, service token creation, per-environment secret injection at container startup
- Client: Doppler CLI v3.76.0 wrapped in `scripts/lib-doppler-api.sh` via `doppler_cmd()` passthrough
- Auth: Doppler CLI authenticated locally (`doppler whoami`); no `--account` flag on CLI v3.76.0 — the token itself scopes the workspace. `DOPPLER_ACCOUNT` field in `coolify.json` is for logging/reference only.
- Operations used:
  - `doppler secrets get --project <p> --config <c> <KEY> --plain` — validate and fetch individual secret values (`validate.sh`, `provision.sh`)
  - `doppler secrets download --project <p> --config <c> --no-file --format docker` — download all secrets as Docker env format (`lib-doppler-api.sh:doppler_download_secrets`)
  - `doppler configs tokens create <name> -p <project> -c <config> --plain` — create scoped service token (`provision.sh`)
  - `doppler configs tokens revoke <name> -p <project> -c <config> --yes` — revoke prior token before rotation (`provision.sh`)
  - `doppler projects create <name>` — create test project (`test/e2e.sh`)
  - `doppler projects delete <name> --yes` — delete test project (`test/e2e.sh`)
  - `doppler environments create ...` — create test environment (`test/e2e.sh`)
  - `doppler secrets set <KEY=VALUE>` — set dummy secrets for E2E (`test/e2e.sh`)

**GitHub Container Registry (GHCR):**
- Purpose: Docker image storage; same image promoted from staging to production (no rebuild)
- Client: `docker/login-action@v3` + `docker/build-push-action@v6` in generated `deploy.yml`; `docker pull` in `test/e2e.sh`
- Auth: `secrets.GITHUB_TOKEN` (in CI); `GHCR_TOKEN` env var (for `test/push-hello-world.sh`)
- Image naming: `ghcr.io/<org>/<repo>:<short-sha>` — tag is 7-char git SHA from `${GITHUB_SHA:0:7}`
- Cleanup: `actions/delete-package-versions@v5` keeps last `registry.retention_tags` (default 5) tags

## Data Storage

**Databases:**
- None — this skill has no database dependency

**File Storage:**
- `~/.claude/coolify.json` — machine-local credential registry (JSON file on operator's disk)
  - Path overridable via `COOLIFY_REGISTRY` env var (used by both `lib-coolify-api.sh` and `lib-doppler-api.sh`)
  - Contains: `servers.<alias>.{url, api_key, doppler_account, ssh_host}`
  - Permissions: `chmod 0600` required; never committed to git
- `coolify.yaml` — per-repo deployment manifest (YAML file committed to each target repo)
  - Contains: project name, server alias, Doppler project, registry image, environment domains, env var key list, Coolify app UUIDs (written back by `provision.sh`)
  - No secrets — safe to commit

**Caching:**
- Docker named volume `${APP_UUID}-doppler-cache` on the Coolify VPS (mounted at `/etc/doppler-cache`)
  - Created via SSH by `provision.sh`: `ssh ${SSH_HOST} "docker volume create ${VOLUME_NAME}"`
  - Mounted via `custom_docker_run_options` PATCH: `--mount source=${VOLUME_NAME},target=/etc/doppler-cache`
  - Purpose: Doppler CLI fallback cache — if Doppler API unreachable at container start, last fetched secrets are used

## Authentication & Identity

**Coolify API key:**
- Source: Generated in Coolify UI (Settings → Keys & Tokens → API Tokens); stored in `~/.claude/coolify.json` as `api_key`
- Usage: Bearer token in every `coolify_curl` call in `lib-coolify-api.sh`
- In CI: passed as `COOLIFY_API_KEY` GitHub Actions secret; hardcoded into generated `deploy.yml` at provision time

**Doppler service tokens:**
- Created per app/environment by `provision.sh` via `doppler configs tokens create`
- Name pattern: `coolify-${PROJECT}-${ENV_NAME}` (e.g. `coolify-skillmap-staging`)
- Scoped: read-only, to a single Doppler project + config
- Lifetime: rotated on every `provision.sh` run (old token revoked, new one created)
- Injected into Coolify as the `DOPPLER_TOKEN` env var; consumed by `doppler run` at container start (Dockerfile ENTRYPOINT)

**GitHub Actions:**
- `GITHUB_TOKEN` (automatic): used for GHCR push (packages: write) and `actions/delete-package-versions`
- `COOLIFY_API_KEY` (manual secret): added to the target repo's GitHub Actions secrets; used in `deploy-staging` and `deploy-production` jobs of the generated `deploy.yml`

**SSH:**
- `ssh_host` in `~/.claude/coolify.json` must match a `Host` entry in `~/.ssh/config`
- Used exclusively by `provision.sh` for `docker volume create` on the Coolify VPS
- Root or Docker-capable user required on the Coolify server

## Coolify API Operational Notes

**`allowed_ips` must be cleared before API calls work:**
- Coolify may restrict API access to specific IPs by default. Every API call returns HTTP 403 (even with a valid token) until `allowed_ips` is set to `*` or your IP range.
- Location: Coolify → Settings → Security
- Required before: first `/setup-coolify validate` run

**Coolify volume API does not exist:**
- `POST /api/v1/volumes` is absent from Coolify (GitHub issue #4084, closed without implementation).
- The skill works around this via SSH: `ssh ${SSH_HOST} "docker volume create ${VOLUME_NAME}"` then sets `custom_docker_run_options` via PATCH to mount the volume.
- This is why `ssh_host` is a required field in `coolify.json`.

**Coolify API tokens are stored as hashes (Laravel Sanctum):**
- The plaintext token is shown once at creation and cannot be retrieved from Coolify later.
- Generate via: Coolify → Settings → Keys & Tokens → API Tokens → Create Token (read + write scope).

## Webhooks & Event Systems

**Incoming webhooks:**
- None — this skill does not register or handle incoming webhooks

**Outgoing / event triggers:**
- Coolify deploy trigger: `GET /api/v1/deploy?uuid=${APP_UUID}&force=false` — fires a Coolify deployment job; not a webhook, but an event trigger via REST
- GitHub Actions: CI workflow (`deploy.yml`) triggers on `push` to `main` branch, dispatches `build → deploy-staging → smoke-test → deploy-production → ghcr-cleanup` job chain

## CI/CD Pipeline

**Hosting:**
- Coolify (self-hosted) on a VPS (Vultr or Hetzner per operator config)

**CI Pipeline:**
- GitHub Actions — generated by `scripts/generate-workflow.sh` and written to `.github/workflows/deploy.yml` in the target repo
- Pipeline stages:
  1. `build` — Docker build + push to GHCR with short SHA tag
  2. `deploy-staging` — PATCH Coolify staging app image tag → trigger deploy → 6-minute HTTP smoke test loop
  3. `deploy-production` — PATCH Coolify production app with same image tag → trigger deploy (no rebuild)
  4. `ghcr-cleanup` — delete old GHCR tags, keep last `retention_tags` (default 5)

## Environment Configuration

**Required env vars / credentials (operator machine):**
- Doppler CLI authenticated (`doppler whoami` must succeed)
- `~/.claude/coolify.json` with `url`, `api_key`, `doppler_account`, `ssh_host` per server alias
- `~/.ssh/config` entry matching `ssh_host` value, reaching Coolify VPS as root

**Required GitHub Actions secrets (per target repo):**
- `COOLIFY_API_KEY` — Coolify Bearer token; added manually to GitHub repo secrets
- `COOLIFY_URL` — Coolify instance root URL (e.g. `https://coolify.cicd.streamlinity.com`); set via `gh secret set COOLIFY_URL`

**Secrets location:**
- Coolify API key: `~/.claude/coolify.json` (local) + GitHub Actions secret
- Doppler personal token: Doppler CLI keychain (managed by `doppler login`)
- Doppler service tokens: Set as Coolify env var `DOPPLER_TOKEN` per app; never stored on disk by this skill
- All application secrets (DATABASE_URL, STRIPE_SECRET_KEY, etc.): stored in Doppler only; fetched at container start via `doppler run --fallback /etc/doppler-cache/secrets.json`

## Reserved / Future Fields

**`build_time: true` annotation on `env_vars` entries:**
- Reserved for a future per-environment build mode. Under the current same-image promotion model, ALL `env_vars` (including `NEXT_PUBLIC_*` keys) are injected at container start via Doppler — never baked into the image.
- `provision.sh` and `generate-workflow.sh` parse but ignore this annotation.
- Do NOT add `# build_time: true` to current manifests; the field name is locked for a future breaking change.

**`is_buildtime` in Coolify bulk-env API:**
- Response-only in `PATCH /applications/{uuid}/envs/bulk` — not accepted in the request body for bulk updates.

## Placeholder / Sentinel Values

- `TODO_REPLACE_BEFORE_DEPLOY` — Doppler secret value sentinel; `validate.sh` treats this as a missing key (exit code 2 from `doppler_check_key`)
- `REPLACE_WITH_COOLIFY_APP_ID_STAGING` / `REPLACE_WITH_COOLIFY_APP_ID_PRODUCTION` — placeholder UUIDs in `deploy.yml` when generated before provisioning
- `https://REPLACE_WITH_YOUR_COOLIFY_URL` — placeholder Coolify URL in `deploy.yml` before `coolify_load_server` can resolve the real URL
- `~` (YAML null) — initial value of `coolify_app_ids.staging` and `coolify_app_ids.production` before first provision run

---

*Integration audit: 2026-05-21*
