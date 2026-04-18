# Deploy Paperclip on Coolify (gpu-server, Tailscale-private)

Goal: host a single-user Paperclip instance at `https://paperclip.home.anteras.org`, reachable from any Tailscale-connected device, using OpenRouter as the sole LLM backend via the `opencode-local` adapter.

Source of truth: this plan. Phase table below doubles as the todo list. Capture commit hashes in the Notes column as phases land.

## Locked decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Source | Upstream `paperclipai/paperclip`, built via Docker Compose remote git context (`https://github.com/paperclipai/paperclip.git#v2026.416.0`). Pinned at the tag. Not forked. |
| 2 | Deploy repo | `arodroz/paperclip` (public). Holds the Coolify compose, plan, scripts. Coolify points Git Source here, not at upstream. |
| 3 | Server | `gpu-server` (Coolify UUID `noo0so0kco00wk8kc8skss48`). |
| 4 | Network | Tailscale-reachable. FQDN `paperclip.home.anteras.org` → `100.74.233.23`. |
| 5 | TLS | Wildcard Let's Encrypt cert `*.home.anteras.org` (valid through 2026-07-10). Automatic. |
| 6 | Source type | Docker Compose. Coolify clones `arodroz/paperclip@main`, reads `/docker-compose.yaml`. |
| 7 | Database | **Reuse** existing shared Coolify Postgres (UUID `bokc0gko8g0s4g0sgs484s00`, Postgres 16-alpine). New database `paperclip` owned by new role `paperclip`. Connection over `coolify` Docker network by UUID hostname. |
| 8 | Adapter | `opencode-local` only. Models routed via OpenRouter. `claude-local` and `codex-local` left dormant. |
| 9 | `PAPERCLIP_PUBLIC_URL` | `https://paperclip.home.anteras.org` (hard-coded in compose). |
| 10 | Domain routing | Coolify `SERVICE_FQDN_SERVER_3100` magic env var in compose — auto-generates Traefik labels at deploy. UI "Domains for server" field did not persist via Livewire over Playwright. |
| 11 | Secrets storage | Coolify env vars (app-level). Real values injected at container start. |
| 12 | `BETTER_AUTH_SECRET` | Generated via `openssl rand -base64 48`. Set once. Never rotated casually. |
| 13 | OpenRouter key scope | Dedicated key `sk-or-v1-...` with key-level $20 cap on OpenRouter dashboard. |
| 14 | OpenRouter env | `OPENROUTER_API_KEY` + `OPENAI_BASE_URL=https://openrouter.ai/api/v1`. No `OPENAI_API_KEY`, no `ANTHROPIC_API_KEY`. |
| 15 | First-user bootstrap | `paperclipai auth bootstrap-ceo` run via Coolify in-UI terminal on the server container after first deploy. |
| 16 | Backups — Postgres | Coolify scheduled `pg_dump` to `garage` S3 on the **shared** Postgres resource. Daily. Retain 14 days. |
| 17 | Backups — `paperclip-data` volume | Weekly `tar czf` → `garage` S3. Retain 4 weeks. |
| 18 | Backup validation | One-time restore test after first deploy. |
| 19 | Resource limits | Server container: 4 cpus / 6 GB mem, declared in compose `deploy.resources.limits`. No db limits (db is shared, not ours to size). |
| 20 | Version update | Manual bumps. Weekly cron on `localhost` (Mon 09:00) → Obsidian note on new tag. |
| 21 | Uptime monitor | `uptime-kuma` HTTP check on `/api/health`, 60s, alert after 2 fails. |
| 22 | Logs | `dozzle` — no config. |
| 23 | Homepage tile | Via `sync-homepage` skill, group AI. |
| 24 | Coolify project | `paperclip` (UUID `lpn8bbi8i0bxsut0786r93fh`). |

## Compose structure

Kept at `docker-compose.yaml` in the repo root. One service, `server`. Builds via remote git context at the pinned tag. No local `db` service — we reference the shared Coolify Postgres over the `coolify` network via `DATABASE_URL`.

Magic Coolify env vars in the compose:
- `SERVICE_FQDN_SERVER_3100` — triggers Traefik label regeneration with our FQDN.

Variables interpolated from Coolify app env:
- `DATABASE_URL` — `postgres://paperclip:...@bokc0gko8g0s4g0sgs484s00:5432/paperclip`
- `BETTER_AUTH_SECRET`
- `OPENROUTER_API_KEY`

Bumping upstream: edit the `build.context` tag fragment (`#v2026.416.0` → new tag), commit, redeploy. Nothing else needs to change unless upstream's Dockerfile breaks compatibility.

## Phases

| Phase | Action | Status | Notes |
|---|---|---|---|
| P1 | Prereq: OpenRouter key + $20 cap | [x] | User-owned. Key pasted into Coolify env var. |
| P2 | Create Coolify project `paperclip` | [x] | UUID `lpn8bbi8i0bxsut0786r93fh`. |
| P3 | Provision `paperclip` DB + role on shared Postgres | [x] | Via Coolify Terminal + psql. User `paperclip`, DB `paperclip`, pg schema perms granted. |
| P4 | Create Coolify compose app from `arodroz/paperclip@main` | [x] | App UUID `f13ye319mc8wu6gy11zesaa4`. `docker_compose_location=/docker-compose.yaml`. |
| P5 | Set FQDN | [x] | Via `SERVICE_FQDN_SERVER_3100` in compose (UI field didn't persist; magic env var does the job). |
| P6 | Set secrets env vars (BETTER_AUTH_SECRET, OPENROUTER_API_KEY, DATABASE_URL) | [x] | Via MCP `env_vars update`. |
| P7 | First deploy | [ ] | Deployment UUID `owjqjcr0rck9akwfqzzqebdu` in progress. Expect 3-8 min build. |
| P8 | Verify `/api/health` over Tailscale | [ ] | `curl https://paperclip.home.anteras.org/api/health`. |
| P9 | Bootstrap CEO | [ ] | `paperclipai auth bootstrap-ceo` in Coolify terminal on server container. |
| P10 | Configure shared Postgres scheduled backup to `garage` S3 | [ ] | Via Coolify Backups tab on the postgresql resource. Daily, 14d retention. |
| P11 | Weekly `paperclip-data` tar → garage | [ ] | Coolify scheduled task on localhost. |
| P12 | Restore test | [ ] | Throwaway resource, restore both, verify login. |
| P13 | Hire first agent in Paperclip UI (opencode + OpenRouter model + $5 budget) | [ ] | Layer-3 spend control. |
| P14 | uptime-kuma monitor on `/api/health` | [ ] | 60s, 2-fail threshold. |
| P15 | Tag-check cron (Mon 09:00 → Obsidian) | [ ] | Script at `scripts/check-upstream-tag.sh` in this repo. |
| P16 | Homepage tile via sync-homepage skill | [ ] | Group AI. |
| P17 | Commit this plan + README to arodroz/paperclip | [~] | Plan and README committed. Plan will be re-committed after completion. |

## Open questions

- Coolify UI "Domains for server" field did not persist via Playwright — `docker_compose_domains` stayed `null`. We relied on `SERVICE_FQDN_<SVC>_<PORT>` magic var instead. Need to confirm it actually wires Traefik correctly when we inspect `custom_labels` after first deploy.

## Notes carried forward

- Postgres 16 on shared instance vs upstream's 17 reference — app only needs Drizzle-compatible PG (12+), not 17-specific features.
- Upstream commit `b9a80dc` (2026-04-17) added multi-user access + invite flows (#3784). Not in `v2026.416.0`. Bump when next tag ships if you want that UI.
- `OPENCODE_ALLOW_ALL_MODELS=true` is set in the upstream Dockerfile — do not override.
- `PAPERCLIP_ALLOWED_HOSTNAMES` not needed — derived from `PAPERCLIP_PUBLIC_URL`.
- `pi-local` was considered and rejected: Pi CLI isn't baked into the upstream image, and we agreed no fork.
