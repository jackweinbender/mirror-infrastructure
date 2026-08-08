# compose-stacks/public-gateway

Public ingress application stack: Cloudflare Tunnel (Zero Trust Access) + demo service. Traefik is deployed once per Docker host by `compose-stacks/docker-host`.

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| Host Traefik | `traefik:v3.7` | Host-level L7 reverse proxy, auto-TLS (deployed separately) |
| `cloudflared` | `cloudflare/cloudflared:latest` | Cloudflare Tunnel endpoint for Zero Trust |
| `helloworld` | `nginx:alpine` | Demo service at `helloworld.weinbender.io` |

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

```bash
# Prerequisites
1. Deploy `compose-stacks/docker-host` to the host.
2. Apply `terraform/cloudflare/` if using the tunnel.
3. Store the tunnel token in 1Password.

# Local
cp .env.template .env
# Fill secrets
docker compose up -d

# CI/CD
# 1. deploy-docker-platform.yaml → host
# 2. deploy.yaml → stack: public-gateway
```

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