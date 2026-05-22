# Per-Domain Setup Guide

A complete walkthrough from blank VPS to a working Coolify + Doppler CI/CD pipeline.
Follow these steps once per Coolify instance (i.e., once per domain/org). After this
guide is complete, run `bash init/init.sh` in any target repo to bootstrap it.

---

## Overview

This guide covers the one-time infrastructure setup required before you can run
`/setup-coolify` on any repo. You will: stand up a Coolify instance, generate an API
token, add an SSH alias, configure Doppler, populate `~/.claude/coolify.json`, wire up
GitHub Actions secrets, and finally bootstrap + provision your first repo.

The reference implementation is skillmap on Vultr (IP `149.248.4.46`) using Doppler
workspace `streamlinity` and Coolify at `https://coolify.cicd.streamlinity.com`. Replace
these values with your own throughout.

---

## Step 1: Stand up a Coolify instance

**Recommended VPS providers:** Vultr, Hetzner, AWS EC2. A $6–12/mo VPS (2 vCPU, 4 GB RAM)
is sufficient for most workloads. Ubuntu 22.04 LTS is the tested base image.

1. Provision a new VPS, note its public IP.
2. SSH in as root:
   ```bash
   ssh root@<ip>
   ```
3. Install Coolify:
   ```bash
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
   ```
   This installs Docker, Coolify, and sets up systemd. The install takes 2–5 minutes.
4. Once the install completes, open `http://<ip>:8000` in a browser. Create your admin
   account on the first-run wizard.
5. Enable HTTPS: navigate to Coolify **Settings → Configuration → HTTPS** and follow the
   prompts to issue a Let's Encrypt certificate for your Coolify domain. You will need a
   DNS A record pointing to the VPS IP first (e.g., `coolify.cicd.example.com → <ip>`).

**Post-install: clear `allowed_ips`**

By default Coolify may restrict API access to specific IPs. Before API calls from
GitHub Actions (or your local machine) will work, open Coolify **Settings → Security**
and clear `allowed_ips` (set to `*` or your known IP ranges). Leaving this at the
default value causes every API call to return HTTP 403 even with a valid token.

---

## Step 2: Generate a Coolify API token

1. Log in to your Coolify dashboard.
2. Navigate to **Settings → Keys & Tokens → API Tokens**.
3. Click **Create Token**. Give it a descriptive name (e.g., `claude-skills-deploy`).
4. Scope: **read + write** (the skill needs write access to create/update apps).
5. **Copy the token immediately.** Coolify uses Laravel Sanctum which stores hashed tokens
   only — the plaintext is shown once at creation and cannot be retrieved later.
6. Store it temporarily in a secure note; you will paste it into `~/.claude/coolify.json`
   and into a GitHub Actions secret in steps below.

---

## Step 3: Create the SSH alias

The skill SSHes to your Coolify server to create persistent Docker volumes (Doppler
fallback cache). Add an alias to `~/.ssh/config`:

```
Host my-coolify-server
  HostName <ip-address>
  User root
  IdentityFile ~/.ssh/id_ed25519
```

Replace `my-coolify-server` with a memorable alias (e.g., `vultr-stream`,
`hetzner-strategem`). This alias is the value you set for `ssh_host` in
`~/.claude/coolify.json` and `server:` in `coolify.yaml`.

Confirm the alias works:
```bash
ssh -o BatchMode=yes my-coolify-server 'echo ok'
```
The output should be `ok`. If it times out, check the VPS firewall (port 22 must be
open) and that your public key is in `root@<ip>:~/.ssh/authorized_keys`.

---

## Step 4: Set up Doppler

1. **Install the Doppler CLI:**
   ```bash
   curl -Ls --tlsv1.2 --proto "=https" https://cli.doppler.com/install.sh | sh
   doppler --version   # should be 3.76.0 or later
   ```

2. **Authenticate:**
   ```bash
   doppler login
   ```
   This opens a browser OAuth flow. Complete it and return to the terminal.

3. **Create a Doppler project** (one project per repo you deploy):
   ```bash
   doppler projects create <project-name>
   ```
   Or create via the Doppler dashboard at `dashboard.doppler.com`. Use a slug that
   matches your repo name (e.g., `skillmap`, `strategem-website`).

4. **Create the required configs.** Doppler uses "configs" for environments. The skill
   expects at least `staging` and `production` configs:
   ```bash
   # Doppler creates dev + staging + production by default for new projects.
   # Verify they exist:
   doppler configs --project <project-name>
   ```
   If `staging` or `production` are absent, create them via the dashboard:
   Doppler → Your Project → Configs → Add Config.

5. **Seed secrets.** Every key listed in `env_vars` in your `coolify.yaml` must exist in
   both the `staging` and `production` Doppler configs before `/setup-coolify validate`
   will pass:
   ```bash
   doppler secrets set --project <project-name> --config staging KEY=value
   doppler secrets set --project <project-name> --config production KEY=value
   ```
   Repeat for every key your application needs (e.g., `DATABASE_URL`,
   `ANTHROPIC_API_KEY`, `STRIPE_SECRET_KEY`).

---

## Step 5: Configure ~/.claude/coolify.json

Create (or update) `~/.claude/coolify.json` with your server entry. Use the exact schema
below (see [docs/schema.md](./schema.md) for the canonical field reference):

```json
{
  "servers": {
    "<alias>": {
      "url": "https://<coolify-domain>",
      "api_key": "<from-step-2>",
      "doppler_account": "<doppler-workspace-alias>",
      "ssh_host": "<from-step-3>"
    }
  }
}
```

Concrete example for the reference implementation:
```json
{
  "servers": {
    "vultr-stream": {
      "url": "https://coolify.cicd.streamlinity.com",
      "api_key": "xOIN...",
      "doppler_account": "streamlinity",
      "ssh_host": "v_cicd_stream"
    }
  }
}
```

**Secure the file immediately:**
```bash
chmod 0600 ~/.claude/coolify.json
```

**Alternatively,** run the interactive prompts which write this file for you:
```bash
/setup-coolify init
```
This prompts for server alias, URL, API key, Doppler account, and SSH host, then merges
the new entry into `~/.claude/coolify.json` and sets permissions.

> **Note:** `ssh_host` is required. Earlier Phase 7 builds defaulted to `v_cicd_stream`
> when absent — that fallback has been removed. Scripts fail clearly if the field is
> missing.

---

## Step 6: Set up the GitHub repo

The generated `.github/workflows/deploy.yml` requires two GitHub Actions secrets:

1. **`COOLIFY_API_KEY`** — the Coolify API token from Step 2:
   ```bash
   gh secret set COOLIFY_API_KEY --body "<token>"
   ```

2. **`COOLIFY_URL`** — the Coolify instance root URL:
   ```bash
   gh secret set COOLIFY_URL --body "https://coolify.cicd.streamlinity.com"
   ```

3. **Enable GHCR write permission.** GitHub Actions needs permission to push Docker images
   to GHCR (GitHub Container Registry). In your repo settings:
   - Go to **Settings → Actions → General → Workflow permissions**
   - Select **Read and write permissions**
   - Save.

   Or via CLI:
   ```bash
   gh api repos/{owner}/{repo} --method PATCH --field default_workflow_permissions=write
   ```

---

## Step 7: Bootstrap and provision

With all setup complete, bootstrap any target repo:

```bash
# Navigate to the repo root:
cd ~/development/<your-project>

# Run the bootstrapper (writes BOTH coolify.yaml AND .github/workflows/deploy.yml):
bash ~/.claude/skills/setup-coolify/init/init.sh
```

You will be prompted for:
- Project name (e.g., `skillmap`)
- Server alias (must match a key in `~/.claude/coolify.json`, e.g., `vultr-stream`)
- Doppler project slug (e.g., `skillmap`)
- GHCR registry image (e.g., `ghcr.io/anatesan-stream/ai-upskilling`)
- Staging domain (e.g., `skillmap-staging.cicd.streamlinity.com`)
- Production domain (e.g., `skillmap.cicd.streamlinity.com`)
- Build context (default `.`; set to `./skillmap` only for monorepos with a nested app)
- Dockerfile path (default `./Dockerfile`)
- Env var keys (space-separated list of all keys your app needs)

After the bootstrapper completes, validate and provision:
```bash
/setup-coolify validate    # dry-run: checks Doppler keys + Coolify API
/setup-coolify             # provisions staging + production apps (idempotent)
```

Commit and push the generated files:
```bash
git add coolify.yaml .github/workflows/deploy.yml
git commit -m "ci: add Coolify deploy pipeline"
git push
```

---

## Verifying success

1. **Check the GitHub Actions workflow was registered:**
   ```bash
   gh workflow view Deploy --repo <org>/<repo>
   ```

2. **Trigger a test push.** Push any commit to `main`. The workflow runs:
   - Build Docker image → push to GHCR with `sha-<commit>` tag
   - Patch staging app → trigger staging deploy → smoke test (HTTP 200 on `/api/health`)
   - On smoke test green: patch production app → trigger production deploy

3. **Check Coolify UI.** Both apps (`<project>-staging` and `<project>-production`) should
   appear in the Coolify project with a green status indicator after the first deploy.

4. **Verify Doppler token injection.** In Coolify, open either app → Environment Variables.
   You should see `DOPPLER_TOKEN` set to a service token, plus all `env_vars` keys listed
   (with `DOPPLER_*` prefix from Coolify's display). The actual secret values are NOT
   stored in Coolify — they are pulled from Doppler at container start.

5. **Visit the staging URL** in a browser. The app should load without errors.
