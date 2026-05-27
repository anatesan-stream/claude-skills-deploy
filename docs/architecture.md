# Architecture & Setup Flow

Two repos and three external services work together to produce a same-image-promotion CI/CD pipeline. This document shows what you build and how the pieces connect.

---

## One-time setup flow

Run through these steps once per domain. Steps ①–③ and ⑤–⑦ are CLI commands; only step ④ (creating the Doppler project) requires a browser.

```mermaid
%%{init: {"flowchart": {"htmlLabels": true}}}%%
flowchart TD
    A["<div style='text-align:left; padding:2px 8px'><b>① Install skill</b><br/>• Fork <code>anatesan-stream/claude-skills-deploy</code> on GitHub<br/>• Clone your fork to <code>~/.claude/skills/setup-coolify/</code></div>"]
    B["<div style='text-align:left; padding:2px 8px'><b>② Configure machine credentials</b><br/>File: <code>~/.claude/coolify.json</code><br/>• Coolify URL<br/>• API key<br/>• ssh_host (alias in ~/.ssh/config)<br/>• Doppler account</div>"]
    C["<div style='text-align:left; padding:2px 8px'><b>③ Bootstrap your app repo</b><br/><code>bash ~/.claude/skills/setup-coolify/init/init.sh</code><br/>Writes two files:<br/>• <code>coolify.yaml</code> — deploy manifest, safe to commit<br/>• <code>.github/workflows/deploy.yml</code> — CI pipeline</div>"]
    D["<div style='text-align:left; padding:2px 8px'><b>④ Create Doppler project</b> ⚠ browser step<br/>• New project at dashboard.doppler.com<br/>• Create two configs: staging · production<br/>• Add all secrets listed in <code>coolify.yaml</code> env_vars</div>"]
    E["<div style='text-align:left; padding:2px 8px'><b>⑤ Dry-run validate</b><br/><code>/setup-coolify validate</code><br/>• Checks Coolify API reachability<br/>• Verifies every Doppler secret exists in staging + production<br/>• No mutations</div>"]
    F["<div style='text-align:left; padding:2px 8px'><b>⑥ Provision</b><br/><code>/setup-coolify</code><br/>• Coolify staging app created<br/>• Coolify production app created<br/>• Doppler service tokens generated + wired as DOPPLER_TOKEN<br/>• Docker volume created on VPS for Doppler fallback cache<br/>• App UUIDs written back to <code>coolify.yaml</code></div>"]
    G["<div style='text-align:left; padding:2px 8px'><b>⑦ Go live</b><br/>• <code>git add coolify.yaml .github/workflows/deploy.yml</code><br/>• <code>git commit -m 'ci: add Coolify deploy pipeline'</code><br/>• <code>git push</code><br/>GitHub Actions pipeline is now active</div>"]

    A --> B --> C --> D --> E --> F --> G

    style A fill:#e3f2fd,stroke:#1976D2,color:#000
    style B fill:#e3f2fd,stroke:#1976D2,color:#000
    style C fill:#e3f2fd,stroke:#1976D2,color:#000
    style D fill:#fff3e0,stroke:#F57C00,color:#000
    style E fill:#e3f2fd,stroke:#1976D2,color:#000
    style F fill:#e3f2fd,stroke:#1976D2,color:#000
    style G fill:#e8f5e9,stroke:#388E3C,color:#000
```

---

## End-state component architecture

Seven components work together once setup is complete. The overview below shows how they connect; the pipeline detail that follows zooms into the runtime deploy loop.

### Overview

```mermaid
%%{init: {"flowchart": {"htmlLabels": true}}}%%
graph LR
    SKILL_REPO["📦 Skill Repo<br/><i>github: claude-skills-deploy</i>"]
    DEV["💻 Developer Machine<br/><i>skill + credentials</i>"]
    APP_REPO["📁 App Repo<br/><i>github: your-org/your-app</i>"]
    CI["⚙ GitHub Actions<br/><i>CI pipeline</i>"]
    REGISTRY["🐳 GHCR<br/><i>image registry</i>"]
    COOLIFY["🚀 Coolify<br/><i>your VPS</i>"]
    DOPPLER["🔐 Doppler<br/><i>secrets</i>"]

    SKILL_REPO  -->|"install"| DEV
    DEV         -->|"init.sh generates"| APP_REPO
    DEV         -->|"provision"| COOLIFY
    DEV         -->|"provision"| DOPPLER
    APP_REPO    -->|"git push triggers"| CI
    CI          -->|"push image"| REGISTRY
    CI          -->|"deploy API"| COOLIFY
    REGISTRY    -->|"pull image"| COOLIFY
    DOPPLER     -->|"inject secrets"| COOLIFY
```

**What lives in each component:**

| Component | Contents |
|-----------|----------|
| **Skill Repo** | `SKILL.md`, `scripts/`, `init/`, `docs/`, `references/` — the skill itself, installed once per machine |
| **Developer Machine** | `~/.claude/skills/setup-coolify/` (installed skill) · `~/.claude/coolify.json` (Coolify URL, API key, Doppler account, ssh_host) |
| **App Repo** | `coolify.yaml` (deploy manifest, committed, no secrets) · `.github/workflows/deploy.yml` (CI pipeline, committed) |
| **GitHub Actions** | Build job · deploy-staging job · smoke-test · deploy-production job (see pipeline detail below) |
| **GHCR** | Docker images tagged by git SHA — `your-app:abc1234`, `your-app:def5678`, … |
| **Coolify** | Staging app (`your-app-staging.example.com`) · Production app (`your-app.example.com`) · both with `DOPPLER_TOKEN` env var |
| **Doppler** | One project per app · `stg` config with service token A · `prd` config with service token B |

---

### Runtime pipeline detail

Every `git push` to `main` triggers this sequence. The image is built **once** and the same tag is promoted to production — no rebuild.

```mermaid
%%{init: {"flowchart": {"htmlLabels": true}}}%%
flowchart LR
    PUSH["git push\nto main"]

    subgraph CI ["⚙ GitHub Actions"]
        direction LR
        BUILD["<div style='text-align:left'><b>build</b><br/>• Docker build<br/>• tag: sha-abc1234<br/>• push to GHCR</div>"]
        STG_DEPLOY["<div style='text-align:left'><b>deploy-staging</b><br/>• PATCH app → sha-abc1234<br/>• trigger Coolify deploy<br/>• poll until running</div>"]
        SMOKE["<div style='text-align:left'><b>smoke-test</b><br/>• GET /api/health<br/>• expect HTTP 200</div>"]
        PRD_DEPLOY["<div style='text-align:left'><b>deploy-production</b><br/>• PATCH app → sha-abc1234<br/>• trigger Coolify deploy<br/>• same image, no rebuild</div>"]
    end

    subgraph REGISTRY ["🐳 GHCR"]
        IMG["your-app:sha-abc1234"]
    end

    subgraph COOLIFY ["🚀 Coolify (VPS)"]
        STG_APP["Staging app\nyour-app-staging.example.com"]
        PRD_APP["Production app\nyour-app.example.com"]
    end

    DOPPLER["🔐 Doppler\nstg + prd service tokens"]

    PUSH        --> BUILD
    BUILD       -->|"image stored"| IMG
    BUILD       --> STG_DEPLOY
    STG_DEPLOY  -->|"deploy API"| STG_APP
    STG_DEPLOY  --> SMOKE
    SMOKE       -->|"green"| PRD_DEPLOY
    PRD_DEPLOY  -->|"deploy API"| PRD_APP
    IMG         -->|"pulled at\ncontainer start"| STG_APP
    IMG         -->|"pulled at\ncontainer start"| PRD_APP
    DOPPLER     -->|"DOPPLER_TOKEN\nsecrets injected\nat container start"| STG_APP
    DOPPLER     -->|"DOPPLER_TOKEN\nsecrets injected\nat container start"| PRD_APP
```

---

## What lives where after setup

| Location | Contents | Committed? |
|----------|----------|-----------|
| `~/.claude/skills/setup-coolify/` | Skill files — `SKILL.md`, `scripts/`, `init/`, `docs/` | No — local install |
| `~/.claude/coolify.json` | Coolify URL + API key + Doppler account + `ssh_host` | **Never** — contains secrets |
| `your-app/coolify.yaml` | Deploy manifest: project slug, server alias, domains, env var names | **Yes** — no secrets |
| `your-app/.github/workflows/deploy.yml` | GitHub Actions pipeline (build → GHCR → Coolify) | **Yes** |
| GHCR | Docker images tagged by git SHA; N most recent kept | N/A |
| Coolify (VPS) | Staging app + production app, each with `DOPPLER_TOKEN` env var | N/A |
| Doppler | One project per app; `stg` + `prd` configs with scoped service tokens | N/A |

---

## See also

- [Setup guide](./setup-guide.md) — step-by-step walkthrough with concrete commands
- [Test environment](./test-environment.md) — E2E prerequisites, run/inspect/cleanup workflow
- [Schema reference](./schema.md) — all `coolify.yaml` and `coolify.json` fields documented
- [Fork guide](./fork-guide.md) — using this skill for a second domain (e.g. strategem.ai)
