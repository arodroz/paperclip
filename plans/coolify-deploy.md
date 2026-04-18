# Deploy Paperclip on Coolify (gpu-server, Tailscale-private)

Goal: host a single-user Paperclip instance at `https://paperclip.home.anteras.org`, reachable from any Tailscale-connected device, using OpenRouter as the sole LLM backend via the `opencode-local` adapter.

Source of truth: this plan. Phase table below doubles as the todo list — check off as work lands, capture commit hashes in the repo purposing this scaffolding (`arodroz/paperclip`).

## Locked decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Source | Upstream `paperclipai/paperclip`, no fork. Pinned to tag `v2026.416.0` (2026-04-16). |
| 2 | Server | `gpu-server` (Coolify UUID `noo0so0kco00wk8kc8skss48`). |
| 3 | Network | Tailscale-reachable. FQDN `paperclip.home.anteras.org` → `100.74.233.23` (Tailscale IP of `gpu-server`, same node that serves `home.home.anteras.org`). |
| 4 | TLS | Wildcard Let's Encrypt cert `*.home.anteras.org` (valid through 2026-07-10) already deployed on Traefik. No per-subdomain cert work. |
| 5 | Source type | Docker Compose, using upstream `docker/docker-compose.yml` as the starting point. |
| 6 | Adapter | `opencode-local` only. Models routed via OpenRouter. `claude-local` and `codex-local` left dormant (their CLIs ship in the image but no agent will be configured against them). |
| 7 | `PAPERCLIP_PUBLIC_URL` | `https://paperclip.home.anteras.org` (hard-coded in the compose, not `${…:-default}`). |
| 8 | Secrets storage | Coolify masked env vars. |
| 9 | `BETTER_AUTH_SECRET` | `openssl rand -base64 48`, generated once, pasted into Coolify. Never rotated casually. |
| 10 | OpenRouter key scope | Dedicated key named `paperclip-home-anteras`, key-level credit limit **$20** initially. |
| 11 | OpenRouter env vars | `OPENROUTER_API_KEY=sk-or-...` + `OPENAI_BASE_URL=https://openrouter.ai/api/v1`. No `OPENAI_API_KEY`, no `ANTHROPIC_API_KEY`. |
| 12 | First-user bootstrap | `paperclipai auth bootstrap-ceo` run via Coolify in-UI terminal after first successful deploy. Default 72h expiry; visit the printed invite URL to sign up as instance admin. |
| 13 | Backups — Postgres | Coolify scheduled `pg_dump` to `garage` S3. Daily. Retain 14 days. |
| 14 | Backups — `paperclip-data` volume | Weekly `tar czf` → `garage` S3. Retain 4 weeks. |
| 15 | Backup validation | One-time restore test after first deploy (new ephemeral Coolify resource, restore both backups, confirm login works). |
| 16 | Resource limits | `server`: 4 cpus / 6 GB mem / 6 GB memswap. `db`: 1 cpu / 1 GB mem. |
| 17 | Version update | Manual bumps. Weekly cron on `localhost` (Mon 09:00) checks `releases/latest`; writes an Obsidian note when a new tag is available. |
| 18 | Uptime monitor | `uptime-kuma` HTTP check on `https://paperclip.home.anteras.org/api/health`, 60s interval, alert after 2 consecutive fails. |
| 19 | Logs | `dozzle` picks up the containers automatically — no config needed. |
| 20 | Homepage tile | Add via `sync-homepage` skill after first successful deploy. Group: "AI". |
| 21 | Coolify project | New project `paperclip`, description: "Autonomous agent orchestration — single-user, Tailscale-private." |
| 22 | `arodroz/paperclip` repo | **Repurposed**, not deleted. Holds this plan, the in-Coolify compose reference, bootstrap notes, and backup/restore scripts. |

## Compose mutations (applied in Coolify's in-UI compose editor)

Base file: upstream `docker/docker-compose.yml` at tag `v2026.416.0`.

1. `server.ports`: remove `"3100:3100"`. Add `expose: ["3100"]` so Coolify-attached Traefik can route but the port isn't bound on the host.
2. `server.environment.PAPERCLIP_PUBLIC_URL`: hard-code to `https://paperclip.home.anteras.org` (drop the `${…:-http://localhost:3100}` fallback — defaults cause auth/invite bugs if env plumbing misfires).
3. `db.ports`: remove `"5432:5432"`. Postgres is only reachable from the `server` container via the compose network.
4. Both services: add `deploy.resources.limits` with the values from decision #16. Also add `deploy.resources.reservations` matching `limits` for `db` only (Postgres benefits from predictable allocation; `server` is bursty and should not reserve).

Also add to `server.environment` once OpenRouter key is in Coolify secrets:

```yaml
OPENROUTER_API_KEY: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY must be set}"
OPENAI_BASE_URL: "https://openrouter.ai/api/v1"
```

Re-apply these four mutations each time we bump the pinned tag; upstream compose may drift.

## Phases

| Phase | Action | Status | Notes |
|---|---|---|---|
| P1 | Prereq: verify OpenRouter key exists; set key-level $20 cap; confirm name is `paperclip-home-anteras` | [ ] | User-owned; agent cannot do this step. |
| P2 | Coolify: create project `paperclip` | [ ] | Via MCP `projects action=create`. |
| P3 | Coolify: create Docker Compose app in `paperclip` project on `gpu-server`, git source `paperclipai/paperclip` ref `v2026.416.0`, compose path `docker/docker-compose.yml` | [ ] | Coolify will clone the repo on first deploy. |
| P4 | Coolify: set FQDN `paperclip.home.anteras.org` on the `server` service | [ ] | Triggers Traefik label generation. |
| P5 | Coolify: paste masked env vars: `BETTER_AUTH_SECRET`, `OPENROUTER_API_KEY` | [ ] | `BETTER_AUTH_SECRET` via `openssl rand -base64 48`. |
| P6 | Coolify: apply compose mutations 1–4 in the in-UI compose editor | [ ] | Save diff for future tag bumps. |
| P7 | Coolify: first deploy; wait for health check; verify `curl https://paperclip.home.anteras.org/api/health` returns `{"status":"ok"}` from tailnet | [ ] | Expect 3–8 min build. |
| P8 | Coolify terminal: `paperclipai auth bootstrap-ceo`; visit printed invite URL; sign up as instance admin | [ ] | Token in browser history is harmless; DB stores only hash. |
| P9 | Coolify: configure Postgres scheduled backup to `garage` S3, daily, 14-day retention | [ ] | Uses Coolify's built-in Postgres backup UI. |
| P10 | Coolify: add scheduled task on `localhost` server — weekly `tar` of `paperclip-data` volume → `garage` S3, 4-week retention | [ ] | Small shell one-liner via Coolify cron. |
| P11 | Restore test: spin up throwaway Coolify app, restore latest backups, verify login works, then delete | [ ] | Only way to know backups work. |
| P12 | Configure first agent: hire CEO in UI with `opencode-local` adapter + a chosen OpenRouter model; set per-agent monthly budget (e.g., $5) | [ ] | Layer 3 of spend control. |
| P13 | `uptime-kuma`: add HTTP monitor on `/api/health`, 60s, 2-fail threshold | [ ] | Existing uptime-kuma project. |
| P14 | Scheduled task on `localhost` (Mon 09:00): check `gh api repos/paperclipai/paperclip/releases/latest`, compare to current ref, write Obsidian note if newer | [ ] | Script lives in this repo under `scripts/check-upstream-tag.sh`. |
| P15 | `sync-homepage` skill: add tile for `paperclip.home.anteras.org` in the "AI" group | [ ] | Do after P7 passes. |
| P16 | Repurpose `arodroz/paperclip`: add README declaring its role as the deployment scaffolding repo; commit this plan; add the exact Coolify compose as `reference/docker-compose.coolify.yml` | [ ] | So future-me knows why it exists. |

## Open questions

- None. All branches resolved during the grill-me session.

## Notes carried forward

- Upstream commit `b9a80dc` (2026-04-17) added multi-user access + invite flows (#3784). Not in `v2026.416.0`. Bump when next tag ships if you want that UI.
- `OPENCODE_ALLOW_ALL_MODELS=true` is already set in the upstream Dockerfile — do not override.
- Paperclip's default `PAPERCLIP_DEPLOYMENT_MODE=authenticated` + `EXPOSURE=private` are correct for our setup; don't change.
- `PAPERCLIP_ALLOWED_HOSTNAMES` is not needed — the host is auto-derived from `PAPERCLIP_PUBLIC_URL`. If we ever add a MagicDNS alias (e.g. `coolify.tailnet.ts.net`), add it here.
- `pi-local` was considered and rejected: Pi CLI is not baked into the upstream image, and we agreed no fork. Revisit if upstream starts shipping pi in the image.
