# compose-stacks/

Docker Compose stacks deployed to self-hosted VMs via GitHub Actions → Tailscale → SSH.

## Stacks

| Stack | Services | Purpose |
|-------|----------|---------|
| `homeassistant/` | Home Assistant, Mosquitto (MQTT), Zigbee2MQTT | Home automation hub |
| `public-gateway/` | Traefik, Cloudflare Tunnel, Hello World demo | Public ingress + tunnel |

## Deployment

Triggered by `.github/workflows/deploy.yaml` (`workflow_dispatch`):

1. **Validate** — `docker compose config` + Home Assistant config check (if applicable)
2. **Sync** — `rsync` stack directory to target VM over Tailscale
3. **Inject secrets** — `op inject` reads `.env.template` → writes `.env` on remote (never on runner)
4. **Deploy** — `docker compose up -d --pull missing`

## Required Secrets (GitHub)

| Secret | Source | Used By |
|--------|--------|---------|
| `ONE_PASSWORD_SA_TOKEN` | 1Password | All stacks |
| `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_CLIENT_SECRET` | Tailscale | All stacks |
| `CLOUDFLARE_ZONE_ID` / `CLOUDFLARE_ACCOUNT_ID` | Cloudflare | public-gateway |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` | GCP | WIF auth |

## Local Development

```bash
cd compose-stacks/<stack>
cp .env.template .env
# Edit .env with local values
docker compose up -d
```

## Conventions

- `.env.template` with `op://` references — checked in
- `.env` — generated at deploy time, **never committed**
- `.rsyncexclude` — excludes local-only files from sync
- `network_mode: host` for Home Assistant stack (required for device discovery)