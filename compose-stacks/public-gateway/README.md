# compose-stacks/public-gateway

Public ingress stack: Traefik (reverse proxy, ACME via Cloudflare DNS-01) + Cloudflare Tunnel (Zero Trust Access) + demo service.

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| `traefik` | `traefik:v3.7` | L7 reverse proxy, auto-TLS (DNS-01 challenge via Cloudflare) |
| `cloudflared` | `cloudflare/cloudflared:latest` | Cloudflare Tunnel endpoint for Zero Trust |
| `helloworld` | `nginx:alpine` | Demo service at `helloworld.weinbender.io` |

## Architecture

```
Internet → Cloudflare Edge
    ├─ Zero Trust Access (email OTP, service tokens)
    └─ Cloudflare Tunnel → cloudflared (VM) → Traefik (VM) → Services
```

- **Cloudflare Tunnel**: Terminates at `cloudflared` on VM. Created by `terraform/cloudflare/` (Plan 001).
- **Traefik**: Handles routing, TLS certs (via `certificatesresolver.cloudflare` using DNS-01), label-based service discovery.
- **Zero Trust Access**: Policies enforced at Cloudflare edge before traffic reaches tunnel.

## Traefik Configuration

- Static: `traefik/traefik.yml`
  - Entrypoints: `web` (80), `websecure` (443)
  - Providers: `docker` (watch labels), `file` (dynamic config)
  - CertificatesResolvers: `cloudflare` (ACME DNS-01 via `CF_DNS_API_TOKEN`)
- Dynamic: `traefik/dynamic/*.yml` (middlewares, TLS options, etc.)

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
# 1. terraform apply in terraform/cloudflare/
# 2. Store tunnel token + DNS API token in 1Password

# Local
cp .env.template .env
# Fill secrets
docker compose up -d

# CI/CD
# GitHub Actions workflow_dispatch → deploy.yaml → stack: public-gateway
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
      - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
```

2. Ensure DNS record exists (CNAME → tunnel) — either via Terraform or Cloudflare dashboard
3. Deploy

## Zero Trust Access (from terraform/cloudflare/access.tf)

| Application | Domain | Policy |
|-------------|--------|--------|
| UK 2026 | `uk2026.weinbender.io` | Email OTP allowlist (12 emails) |
| API | Service token | `weinbender-io-api` token for programmatic access |