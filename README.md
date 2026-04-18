# paperclip (deployment scaffolding)

This repo does **not** contain Paperclip source code. It holds the Coolify deployment config for a private Paperclip instance that builds from upstream `paperclipai/paperclip` at a pinned tag.

- Live URL (Tailscale-private): `https://paperclip.home.anteras.org`
- Upstream: https://github.com/paperclipai/paperclip
- Pinned tag: see `build.context` fragment in `docker-compose.yaml`
- Full design rationale and phased execution checklist: `plans/coolify-deploy.md`

## Bumping the upstream version

1. Find the new tag on the upstream releases page.
2. In `docker-compose.yaml`, update the `build.context` fragment (`#v2026.NNN.0`).
3. Commit, push, redeploy from Coolify.
4. Re-apply any compose mutations if upstream's reference compose changed shape.

## Structure

- `docker-compose.yaml` — what Coolify deploys.
- `plans/` — design and execution checklist.
- `scripts/` — helper scripts (tag-check cron, backup helpers) — populated during execution.
