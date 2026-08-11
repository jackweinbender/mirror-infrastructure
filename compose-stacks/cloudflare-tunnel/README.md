# compose-stacks/cloudflare-tunnel

Cloudflare Tunnel stack for public ingress (Zero Trust Access). Traefik is deployed once per Docker host by `compose-stacks/docker-host`.

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| `cloudflared` | `cloudflare/cloudflared:latest` | Cloudflare Tunnel endpoint for Zero Trust |
| Host Traefik | `traefik:v3.7` | Host-level L7 reverse proxy and auto-TLS (deployed separately) |

## Architecture

```
Internet → Cloudflare Edge
    ├─ Zero Trust Access (email OTP, service tokens)
    └─ Cloudflare Tunnel → cloudflared (host) → Traefik (host) → Services
```

- **Cloudflare Tunnel**: Terminates at `cloudflared` on VM. Created by `terraform/cloudflare/` (Plan 001).
- **Traefik**: Deployed by `compose-stacks/docker-host`; handles routing, TLS certs (via the `letsencrypt` resolver using DNS-01), and label-based service discovery.
- **Zero Trust Access**: Policies enforced at Cloudflare edge before traffic reaches tunnel.

## Traefik Configuration

Host-level configuration lives in `compose-stacks/docker-host/traefik/`. This stack joins the external `proxy` network and contributes application containers via Docker labels.


## Cloudflare Tunnel

After `terraform apply` in `terraform/cloudflare/`:
1. Go to Cloudflare Zero Trust → Networks → Tunnels → `weinbender-io` → Configure
2. Copy tunnel token
3. Store in 1Password: `op://network/cloudflare-tunnel-weinbender-io/credential`

## Secrets (.env.template)

| Variable | 1Password Path | Purpose |
|----------|----------------|---------|
| `CLOUDFLARE_TUNNEL_TOKEN` | `op://network/cloudflare-tunnel-weinbender-io/credential` | Tunnel credential |
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare API token (Zone:DNS:Edit) |

Injected at deploy via `op inject` — never touches runner disk.

## Deploy

The application assignment is represented by a file in `deployments/`, for example `deployments/docker-vm-dmz.env`. Add another `<deploy-host>.env` to run this stack on another inventory host. Remove the file to stop it there; the application workflow tears down Compose before deleting its remote files.

Prerequisites:
1. Deploy `compose-stacks/docker-host` with `deploy-docker-platform.yaml` so the external `proxy` network exists.
2. Apply `terraform/cloudflare/` if using the tunnel.
3. Store the tunnel token in 1Password.

For local validation, merge `deployments/_shared.env` and a host template using a representative token value and run `docker compose config --quiet`. CI resolves `op://` references with `op inject`; the resolved `.env` is never committed or stored on the runner.

## Add a New Service

1. Add to `docker-compose.yaml`:
```yaml
  myservice:
    image: myorg/myservice:latest
    networks: [proxy]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myservice.rule=Host(`myservice.weinbender.io`)"
      - "traefik.http.routers.myservice.entrypoints=websecure"
      traefik.http.routers.myservice.tls.certresolver=letsencrypt
```

2. Ensure DNS record exists (CNAME → tunnel) — either via Terraform or Cloudflare dashboard
3. Deploy

## Zero Trust Access (from terraform/cloudflare/access.tf)

| Application | Domain | Policy |
|-------------|--------|--------|
| UK 2026 | `uk2026.weinbender.io` | Email OTP allowlist (12 emails) |
| API | Service token | `weinbender-io-api` token for programmatic access |