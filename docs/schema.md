# coolify.yaml & coolify.json Schema Reference

Canonical schema for the two config files consumed by the setup-coolify skill.
`coolify.yaml` is per-repo and committed; `~/.claude/coolify.json` is machine-local
and contains credentials.

---

## coolify.yaml — Per-Repo Manifest

`coolify.yaml` lives at the root of each repo you deploy. It contains no secret values —
secrets live in Doppler. Commit this file. The `server:` alias selects which Coolify
instance and Doppler account to use; all other config is repo-local.

### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `project` | string | Coolify project name (also used as Coolify-side project name). Conventionally the same as the repo name without the org prefix. | `skillmap` |
| `server` | string | Alias matching a key in `~/.claude/coolify.json` `servers`. Determines Coolify URL and Doppler account routing. | `vultr-stream` |
| `doppler_project` | string | Doppler project slug. Conventionally the same as `project` unless multiple repos share one Doppler project. | `skillmap` |
| `registry.image` | string | GHCR image path (no tag). The CI workflow appends the git SHA tag at build time — never include it here. Format: `ghcr.io/<org>/<repo>`. | `ghcr.io/anatesan-stream/ai-upskilling` |
| `environments.staging.domain` | string | FQDN for staging (no protocol, no trailing slash). | `skillmap-staging.cicd.streamlinity.com` |
| `environments.staging.doppler_environment` | string | Doppler config name for staging. | `staging` |
| `environments.production.domain` | string | FQDN for production (no protocol, no trailing slash). | `skillmap.cicd.streamlinity.com` |
| `environments.production.doppler_environment` | string | Doppler config name for production. | `production` |
| `env_vars` | list of strings | Secret keys your app reads at runtime. All are injected at container start from Doppler — NOT baked into the image. Keys must exist in both staging and production Doppler configs. | `[DATABASE_URL, ANTHROPIC_API_KEY]` |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `registry.retention_tags` | int | `5` | Number of GHCR image tags to retain. Older tags are deleted by the CI workflow after each push. |
| `build.context` | string | `.` | Docker build context path relative to repo root. Use `.` for repos with the app at root (the common case). Set to `./skillmap` or similar only for monorepos / nested-app layouts like ai-upskilling. |
| `build.dockerfile` | string | `./Dockerfile` | Path to the Dockerfile, relative to repo root. For nested apps (e.g. `build.context: ./skillmap`), set this to `./skillmap/Dockerfile`. |
| `coolify_app_ids.staging` | string \| null | `~` | Coolify application UUID for staging. Written by `provision.sh` after the first successful run. Do not edit manually. |
| `coolify_app_ids.production` | string \| null | `~` | Coolify application UUID for production. Written by `provision.sh` after the first successful run. Do not edit manually. |

### Reserved (Not Yet Active)

The `# build_time: true` trailing-comment annotation on `env_vars` entries is reserved
for a future per-environment build mode where staging and production need different
baked-in values. Under the current same-image promotion model all `env_vars` — including
`NEXT_PUBLIC_*` keys — are injected at container start via Doppler. The annotation is
intentionally absent from active manifests; `provision.sh` and `generate-workflow.sh`
currently parse but ignore it.

Do not add `# build_time: true` to current manifests. The field name is locked for future
use; it will be a breaking change when activated.

---

## coolify.json — Machine-Local Credentials

Path: `~/.claude/coolify.json`. **Never commit this file.** Set permissions immediately
after creation:

```bash
chmod 0600 ~/.claude/coolify.json
```

Use `/setup-coolify init` to populate this file interactively, or write it manually
using the schema below.

> **Note:** JSON has no comment syntax. This table IS the annotation — refer to it when
> filling out the file manually.

### Required Fields per Server Entry

| Field | Where to get the value | Example |
|-------|------------------------|---------|
| `url` | Coolify dashboard URL — the root domain your Coolify instance runs on, HTTPS, no trailing slash. | `https://coolify.cicd.streamlinity.com` |
| `api_key` | Coolify → Settings → Keys & Tokens → Generate API Token. Scoped to your instance. | `xOIN...` (opaque string) |
| `doppler_account` | Your Doppler account slug — visible in the Doppler dashboard URL (`dashboard.doppler.com/workplace/<slug>`) or run `doppler configure get account`. | `streamlinity` |
| `ssh_host` | SSH alias from `~/.ssh/config` that reaches the Coolify server as root. Used by `provision.sh` to create Docker volumes on first deploy. Must match a `Host` entry in `~/.ssh/config`. | `v_cicd_stream` |

> **Important:** `ssh_host` is REQUIRED as of this skill release. Earlier Phase 7
> implementations defaulted to `v_cicd_stream` when absent — that fallback has been
> removed. Scripts will fail loudly if the field is missing. Run `/setup-coolify init`
> to populate this file interactively.

---

## Complete Annotated Example

### coolify.yaml — annotated

Lines are annotated with one of three labels:

- `# CHANGE THIS` — values the new repo owner must set
- `# leave as-is` — sane defaults; only change for advanced use
- `# auto-filled by /setup-coolify` — written by `provision.sh`; do not edit

```yaml
# coolify.yaml — per-repo deploy manifest. SAFE TO COMMIT (no secrets).
# Full schema: docs/schema.md

project: myapp           # CHANGE THIS: short slug, lowercase. Becomes the Coolify project name.
server: vultr-stream     # CHANGE THIS: must match a key in ~/.claude/coolify.json servers.
doppler_project: myapp   # CHANGE THIS (or leave same as project): Doppler project slug.

registry:
  # CHANGE THIS: GHCR image path — org/repo only, NO tag.
  # init.sh auto-suggests this from your git remote.
  # The CI workflow appends the git SHA tag; never include it here.
  image: ghcr.io/your-org/your-repo
  retention_tags: 5      # leave as-is: number of GHCR tags to keep

build:
  # leave as-is if Dockerfile is at repo root (default for most projects).
  # CHANGE context/dockerfile only for monorepos (e.g. context: ./myapp).
  context: .
  dockerfile: ./Dockerfile

environments:
  staging:
    domain: myapp-staging.example.com   # CHANGE THIS: staging FQDN, no protocol
    doppler_environment: staging         # leave as-is: matches Doppler config name
  production:
    domain: myapp.example.com            # CHANGE THIS: production FQDN, no protocol
    doppler_environment: production      # leave as-is: matches Doppler config name

# CHANGE THIS: list every env var your app reads.
# All are injected at container start from Doppler — NOT baked into the image.
# Keys must exist in both the staging and production Doppler configs.
env_vars:
  - DATABASE_URL
  - ANTHROPIC_API_KEY
  - STRIPE_SECRET_KEY

# auto-filled by /setup-coolify — DO NOT edit. ~ = not yet provisioned.
coolify_app_ids:
  staging: ~
  production: ~
```

### coolify.json — annotated

JSON has no comment syntax. Use the annotation table below when filling in values, then
write the JSON block with the actual values substituted.

| Field | What to put here |
|-------|-----------------|
| `url` | Your Coolify dashboard root URL (HTTPS, no trailing slash) |
| `api_key` | Coolify → Settings → Keys & Tokens → Generate API Token |
| `doppler_account` | Doppler account slug — `doppler configure get account` |
| `ssh_host` | SSH alias from `~/.ssh/config` that reaches the Coolify server as root |

The example below shows two server entries. Multiple entries let you deploy different
projects to different Coolify instances from the same machine. The `server:` field in
each `coolify.yaml` selects which entry to use.

```json
{
  "servers": {
    "vultr-stream": {
      "url": "https://coolify.cicd.streamlinity.com",
      "api_key": "REDACTED",
      "doppler_account": "streamlinity",
      "ssh_host": "v_cicd_stream"
    },
    "hetzner-strategem": {
      "url": "https://coolify.cicd.strategem.ai",
      "api_key": "REDACTED",
      "doppler_account": "strategem",
      "ssh_host": "hetzner-strategem"
    }
  }
}
```

---

## Field Lifecycle

Knowing who writes each field prevents accidental overwrites.

### User-written fields (in `coolify.yaml`)

Set these yourself when onboarding a new repo:

- `project`
- `server`
- `doppler_project`
- `registry.image`
- `registry.retention_tags` (optional; default 5 is usually correct)
- `environments.staging.domain`
- `environments.staging.doppler_environment`
- `environments.production.domain`
- `environments.production.doppler_environment`
- `env_vars` (list)
- `build.context` (optional; default `.`)
- `build.dockerfile` (optional; default `./Dockerfile`)

### Skill-written fields (in `coolify.yaml`)

These are set automatically by `provision.sh` after the first successful run:

- `coolify_app_ids.staging` — Coolify application UUID, cached to avoid repeated lookups
- `coolify_app_ids.production` — Coolify application UUID, cached to avoid repeated lookups

Do not edit these manually. If you delete or reprovision an app, `provision.sh` will
overwrite them on the next run.

### User-written fields (in `coolify.json`)

All fields in `~/.claude/coolify.json` are user-written. Use `/setup-coolify init` to
populate interactively, or write the file manually.

**Permissions:** `chmod 0600 ~/.claude/coolify.json` (file contains API keys).

---

## Validation

`validate.sh` runs a dry-run pre-flight check before any Coolify API calls. It enforces:

### coolify.yaml checks

- All required fields present and non-empty (`project`, `server`, `doppler_project`,
  `registry.image`, `environments.staging.domain`, `environments.staging.doppler_environment`,
  `environments.production.domain`, `environments.production.doppler_environment`, `env_vars`)
- `env_vars` is a non-empty list

### coolify.json checks

- `servers.<alias>` entry exists for the `server` value referenced in `coolify.yaml`
- Server entry contains all four required fields: `url`, `api_key`, `doppler_account`,
  `ssh_host`
- `ssh_host` value matches a `Host` entry in `~/.ssh/config`

### Live checks

- Coolify API: `GET /projects` returns HTTP 200 (confirms URL and API key are valid)
- Doppler: every `env_vars` key is present in both staging and production configs with
  non-placeholder values (not empty string, not `CHANGE_ME`)

Run validation before provisioning:

```bash
bash ~/.claude/skills/setup-coolify/scripts/validate.sh ./coolify.yaml
```

Exit code 0 = all checks passed. Non-zero = at least one check failed (error message
printed to stderr with the failing field/key name).

---

## Backward Compatibility

### `build.context` / `build.dockerfile` (added in Phase 8)

These fields are optional with safe defaults (`.` and `./Dockerfile`). Existing
`coolify.yaml` files that omit the `build:` block continue to work — scripts treat
absence as the defaults. Only set these for repos where the app is not at root.

### `ssh_host` (added in Phase 8)

Required in `~/.claude/coolify.json` server entries as of this skill release. Phase 7
implementations defaulted to `v_cicd_stream` when absent — this fallback has been
removed. Update your `~/.claude/coolify.json` to add `"ssh_host": "<alias>"` to each
server entry. The `/setup-coolify init` interactive flow now prompts for this value.

### `coolify_app_ids` (carried from Phase 7)

These cache fields are optional in the schema; `provision.sh` writes them on first run
and reads them to skip re-provisioning on subsequent runs. Files created before Phase 7
that lack this block are treated as if both values are `~` (null).
