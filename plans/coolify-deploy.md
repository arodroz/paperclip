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
| P3 | Provision `paperclip` DB + role on shared Postgres | [x] | Via Coolify Terminal + psql. User `paperclip`, DB `paperclip`. |
| P4 | Create Coolify compose app from `arodroz/paperclip@main` | [x] | App UUID `f13ye319mc8wu6gy11zesaa4`. Compose at `/docker-compose.yaml`. |
| P5 | Set FQDN via `docker_compose_domains` UI field | [x] | Required `pressSequentially` — `fill()` doesn't trigger Livewire. |
| P6 | Set secrets (BETTER_AUTH_SECRET, OPENROUTER_API_KEY, DATABASE_URL) | [x] | Via MCP `env_vars update`. |
| P7 | First successful deploy | [x] | Commit `c58921c`. Needed pinning past `v2026.416.0` (stale gh-keyring SHA) to `e93e418`, full 40-char SHA, and coolify network attachment. |
| P8 | Cross-host Traefik dynamic config on localhost proxy | [x] | `paperclip-home.yaml` in localhost Coolify's Proxy > Dynamic Configurations routes to `http://192.168.1.65:3110`. Key learning saved to user-level memory. Host port 3110 (3100 taken on gpu-server). |
| P9 | Verify `/api/health` over Tailscale | [x] | `HTTP/2 200` at 11:33:21 UTC. `bootstrapInviteActive: true` after P10. |
| P10 | Bootstrap CEO | [x] | CLI path blocked (`local_trusted` vs env-override mismatch + `/` intercept in Coolify keyboard shortcuts). Bypassed via direct SQL `INSERT` on `invites` table with SHA-256-hashed `pcp_bootstrap_*` token. Invite URL shown to user, 72h expiry. |
| P11 | Backups — Postgres daily to `garage` S3 | DEFERRED | Coolify's per-instance backup dumps ALL databases on the shared PG (no DB filter in UI), which crosses shared infra boundaries. Proper paperclip-only path: dedicated sidecar container with `pg_dump` + `mc` or `awscli` pushing to garage S3. Not ad-hoc configurable via MCP/Playwright. |
| P12 | Backups — `paperclip-data` volume weekly tar | DEFERRED | Requires a sidecar container with access to the Docker volume (e.g. a second compose service mounting `paperclip-data:/data:ro` + `mc`) and S3 credentials. |
| P13 | Backup restore test | DEFERRED | Depends on P11/P12. |
| P14 | uptime-kuma monitor on `/api/health` | TODO (user) | User login required for uptime.home.anteras.org. Manual step: add HTTP monitor, 60s, alert after 2 fails, URL `https://paperclip.home.anteras.org/api/health`, expect `"status":"ok"`. |
| P15 | Tag-check cron (Mon 09:00 → Obsidian) | TODO | Script `scripts/check-upstream-tag.sh` in this repo (to be added). Coolify scheduled task on localhost. |
| P16 | Homepage tile via `sync-homepage` skill | TODO | Group "AI". Icon: `paperclip-outline`. |
| P17 | Hire first agent (opencode + OpenRouter + $5/mo budget) | TODO (user) | In Paperclip UI after CEO signup. |
| P18 | Commit plan to arodroz/paperclip | [x] | Via commits `9a3d75b`, plus this update. |

## Deferred backup strategy (notes for future work)

Two complementary needs:

1. **Postgres `paperclip` database dump.** The shared Coolify Postgres (`bokc0gko8g0s4g0sgs484s00`) hosts multiple user databases; using Coolify's per-instance backup would back up *everything* on it. For a paperclip-specific backup:

   - Add a sidecar service in `docker-compose.yaml` — e.g. `postgres-backup` using `postgres:16-alpine` as the base image so `pg_dump` is present.
   - Mount a small volume `paperclip-db-backups:/backups`.
   - Entrypoint loops: `sleep until interval; pg_dump "$DATABASE_URL" > /backups/paperclip-$(date +%F).sql.gz; prune > 14 days`.
   - For S3 push: either add `mc` (minio client) or `aws-cli` to the image and push to garage after each dump.

2. **`paperclip-data` volume tar.** Instance config + secrets key + agent workspaces + uploaded assets. Changes slowly.

   - Add a second sidecar `paperclip-data-backup` service mounting `paperclip-data:/data:ro` and `paperclip-backups:/out`.
   - Entrypoint loops: `tar czf /out/paperclip-data-$(date +%F).tar.gz -C /data .; prune > 4 weeks`.
   - Push to garage S3 same as above.

Both are easiest when run as dedicated compose services in this same stack — they get DB and volume access for free.

## Open questions

- None outstanding. P11–P13 intentionally deferred.

## Notes carried forward

- Postgres 16 on shared instance vs upstream's 17 reference — app only needs Drizzle-compatible PG (12+).
- Upstream `v2026.416.0` Dockerfile had a stale `cli.github.com` keyring SHA; fixed same day in `407e76c` → we pinned to `e93e418` (post-fix, minimal delta).
- `OPENCODE_ALLOW_ALL_MODELS=true` is set in the upstream Dockerfile — do not override.
- `PAPERCLIP_ALLOWED_HOSTNAMES` not needed — derived from `PAPERCLIP_PUBLIC_URL`.
- `pi-local` was considered and rejected: Pi CLI isn't baked into the upstream image, no-fork constraint.
- Coolify's `/` keyboard shortcut opens global search — when typing commands in either Coolify-UI terminal (app or Postgres), use `browser_type` with `slowly: true` via `pressSequentially` rather than per-key `press_key('/')`.
- The Coolify-UI textarea doesn't sync with Livewire via `.value =` set; must use keyboard events (`pressSequentially` / `press_key`) to trigger the `wire:model` binding.
- For cross-host routing to `.home.anteras.org`, Traefik's `docker` provider can't see labels on containers on other hosts. Use a dynamic file-provider config on the Coolify-host proxy (documented in user memory: `reference_coolify_cross_host_routing.md`).
