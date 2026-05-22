# Technology Stack

**Analysis Date:** 2026-05-21

## Languages

**Primary:**
- Bash (POSIX + bash 4+) - All skill scripts, library files, init, test, and workflow generation
- Python 3 (3.6+) - Inline data processing embedded in bash scripts via `python3 -c` and heredoc `<<'PY'` blocks; used for YAML parsing, JSON construction, and config extraction

**Secondary:**
- YAML - Config format for `coolify.yaml` (per-repo manifest) and GitHub Actions workflow `deploy.yml`
- JSON - Machine-local credentials format (`~/.claude/coolify.json`)

## Runtime

**Environment:**
- Linux (bash shell required; tested on Ubuntu via GitHub Actions `ubuntu-latest`)
- macOS compatible (bash 3 ships by default — scripts use `#!/usr/bin/env bash` with `set -euo pipefail`)

**No Node.js, no Ruby, no compiled binaries.** The skill itself is pure shell + Python.

## Package Manager

- None — no `package.json`, `requirements.txt`, `Cargo.toml`, or `go.mod` present
- Lockfile: Not applicable
- Python dependency: `pyyaml` (PyPI) — required by `provision.sh`, `validate.sh`, `generate-workflow.sh`, and `test/e2e.sh`; installed by the consumer, not by this skill

## Frameworks

**Core:**
- None — skill is plain bash with no framework dependencies

**Testing:**
- Custom bash test runner (`test/e2e.sh`) with inline pass/fail counters; no framework (no bats, no shunit2)

**Build/Dev:**
- None — no build step; scripts are executed directly

## Key Dependencies (External CLI Tools)

**Required at runtime on the operator machine:**

| Tool | Version Noted | Purpose |
|------|---------------|---------|
| `bash` | 4+ recommended | Script execution |
| `python3` | 3.6+ | YAML/JSON parsing (inline in all major scripts) |
| `pyyaml` | any | Python YAML library — `import yaml` in `provision.sh`, `validate.sh`, `generate-workflow.sh`, `test/e2e.sh` |
| `doppler` | CLI v3.76.0 (noted in `lib-doppler-api.sh`) | Secret management CLI; `doppler secrets`, `doppler configs tokens` |
| `curl` | any | Coolify REST API calls in `lib-coolify-api.sh` and generated `deploy.yml` |
| `ssh` | any | Docker volume creation on Coolify VPS via `provision.sh` |
| `docker` | any | Image pull check in `test/e2e.sh`; Docker volume management on remote server |

**Required only in CI (generated `deploy.yml`):**

| Tool / Action | Version | Purpose |
|---------------|---------|---------|
| `actions/checkout` | v4 | Source checkout |
| `docker/login-action` | v3 | GHCR authentication |
| `docker/build-push-action` | v6 | Docker image build and push |
| `actions/delete-package-versions` | v5 | GHCR tag retention cleanup |

## Configuration

**Environment:**
- No `.env` file used by the skill itself
- Credentials live in `~/.claude/coolify.json` (machine-local, never committed)
- Per-repo deployment config lives in `coolify.yaml` (committed, no secrets)
- Doppler service tokens are scoped per Coolify app and set as env vars by `provision.sh`

**Config files in this repo:**
- `coolify.yaml` — per-repo manifest (template at `init/templates/coolify.yaml.tmpl`)
- `~/.claude/coolify.json` — machine-local credential registry (path overridable via `COOLIFY_REGISTRY` env var in `lib-coolify-api.sh` and `lib-doppler-api.sh`)

## Platform Requirements

**Development / Operator machine:**
- Linux or macOS
- `bash` 4+, `python3` with `pyyaml`, `doppler` CLI (authenticated), `curl`, `ssh`
- `~/.ssh/config` entry for the Coolify VPS (`ssh_host` alias in `coolify.json`)
- `~/.claude/coolify.json` populated via `/setup-coolify init`

**Production (Coolify VPS):**
- Recommended: $6–12/mo VPS (2 vCPU, 4 GB RAM minimum); Ubuntu 22.04 LTS tested
- Providers: Vultr, Hetzner, AWS EC2
- Coolify install: `curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash` (installs Docker + Coolify + systemd; 2–5 min)
- Coolify (self-hosted; single-node with server named `localhost`)
- Docker (for named volume management)
- HTTPS / Let's Encrypt (Coolify-managed; requires DNS A record pointing to VPS before enabling)
- `allowed_ips` in Coolify Settings → Security must be cleared (`*`) before API calls succeed
- GHCR image pull access (public images or GHCR PAT configured in Coolify)

**CI (GitHub Actions):**
- `ubuntu-latest` runner
- `COOLIFY_API_KEY` — Coolify Bearer token (GitHub Actions secret, set manually per repo)
- `COOLIFY_URL` — Coolify instance root URL (GitHub Actions secret, set via `gh secret set COOLIFY_URL`)
- `GITHUB_TOKEN` — automatic; needs `packages: write` for GHCR push (set via repo Settings → Actions → General → Workflow permissions → Read and write)

**Backward compatibility notes (Phase 8 additions):**
- `build.context` / `build.dockerfile` in `coolify.yaml` — optional; absent fields default to `.` and `./Dockerfile`. Existing files without the `build:` block continue to work.
- `ssh_host` in `coolify.json` — required as of Phase 8; Phase 7 implementations defaulted to `v_cicd_stream` when absent (fallback removed). Run `/setup-coolify init` to populate.

---

*Stack analysis: 2026-05-21*
