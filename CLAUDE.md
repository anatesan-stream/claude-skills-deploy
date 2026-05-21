# claude-skills-deploy

Coolify + Doppler deployment skills for Claude Code.

## Available Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `setup-coolify` | `/setup-coolify` | Provision/update Coolify staging + production apps from coolify.yaml. Idempotent. |
| `setup-coolify init` | `/setup-coolify init` | Interactive setup of `~/.claude/coolify.json` for a new Coolify server alias. |
| `setup-coolify validate` | `/setup-coolify validate` | Dry-run check: verifies Doppler keys + Coolify API reachability. No mutations. |

## Install

```bash
git clone https://github.com/anatesan-stream/claude-skills-deploy.git ~/.claude/skills/setup-coolify
```

No build step. `/setup-coolify` is immediately available in any new Claude Code session.

## Bootstrap a new repo

From the target repo's root directory:

```bash
bash ~/.claude/skills/setup-coolify/init/init.sh
```

The init script prompts for project name, server alias, Doppler project, GHCR registry image, staging/production domains, build paths, and env var keys. It writes `coolify.yaml` to the current directory.

Then:
```bash
/setup-coolify validate    # dry-run check
/setup-coolify             # provision Coolify + Doppler
bash ~/.claude/skills/setup-coolify/scripts/generate-workflow.sh
```

## Documentation

- **[README.md](./README.md)** — Top-level user guide
- **[docs/setup-guide.md](./docs/setup-guide.md)** — Per-domain Coolify + Doppler initial setup
- **[docs/fork-guide.md](./docs/fork-guide.md)** — How to use this skill for a new domain (strategem.ai example)
- **[docs/schema.md](./docs/schema.md)** — coolify.yaml + coolify.json schema reference
- **[references/api-reference.md](./references/api-reference.md)** — Coolify + Doppler REST API reference

## Design

Domain-agnostic by design. The `server:` field in `coolify.yaml` selects which Coolify instance and Doppler workspace to use. Per-machine credentials live in `~/.claude/coolify.json` (never committed). Adding a new domain requires zero script changes — only a new server entry in `coolify.json` and a new `coolify.yaml` in the target repo.
