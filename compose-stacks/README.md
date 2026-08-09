# compose-stacks/

Docker Compose stacks deployed to self-hosted VMs via GitHub Actions → Tailscale → SSH.

## Stacks

| Stack | Services | Purpose |
|-------|----------|---------|
| `docker-host/` | Traefik | Host-level reverse proxy and shared `proxy` network |
| `cloudflare-tunnel/` | Cloudflare Tunnel | Public ingress through the host's Traefik instance |

## Deployment

Application stacks are deployed by `.github/workflows/deploy.yaml` (`workflow_dispatch`). The host platform is deployed by `.github/workflows/deploy-docker-platform.yaml` (`workflow_dispatch`):
Changes under `compose-stacks/docker-host/**` are deployed by manually dispatching the platform workflow for each affected host. Ansible remains responsible for preparing the host.

1. **Sync** — `rsync` the selected stack directory to the target VM over Tailscale
2. **Inject secrets** — `op inject` reads `.env.template` → writes `.env` on remote (never on runner)
3. **Deploy** — `docker compose up -d --pull missing`

For each Docker host, the platform workflow first creates the external `proxy` network if needed, then deploys Traefik and its persistent ACME volume.

## Required Secrets (GitHub)

| Secret | Source | Used By |
|--------|--------|---------|
| `ONE_PASSWORD_SA_TOKEN` | 1Password | All stacks |
| `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_CLIENT_SECRET` | Tailscale | All stacks |
| `CLOUDFLARE_ZONE_ID` / `CLOUDFLARE_ACCOUNT_ID` | Cloudflare | cloudflare-tunnel |
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
