# Docker host platform stack

This is the host-level platform deployed to every Docker LXC host. It is intentionally separate from application stacks.

## What it provides

- An idempotently created, attachable Docker bridge network named `proxy`.
- Traefik on ports 80 and 443 with Docker label discovery.
- An unauthenticated dashboard accessible by host IP.
- Persistent ACME state in the `traefik_acme` Docker volume.
- Cloudflare DNS-01 certificate issuance using the `letsencrypt` resolver.

Traefik only discovers containers that explicitly set `traefik.enable=true`. Application stacks must join the external network:

```yaml
services:
  app:
    image: example/app:latest
    networks: [proxy]
    labels:
      traefik.enable: "true"
      traefik.http.routers.app.rule: Host(`app.example.com`)
      traefik.http.routers.app.entrypoints: websecure
      traefik.http.routers.app.tls.certresolver: letsencrypt

networks:
  proxy:
    external: true
    name: proxy
```

## Deployment

Use `.github/workflows/deploy-docker-host.yaml` with the host's Tailscale name and SSH user. The workflow:

1. Validates the Compose file.
2. Connects the runner to Tailscale.
3. Creates `proxy` if it does not exist.
4. Syncs this directory to `/etc/compose-stacks/docker-host`.
5. Resolves `.env.template` through 1Password directly into the host.
6. Reconciles Traefik with Docker Compose.

The operation is safe to repeat for every host. A host needs Docker, Tailscale connectivity from the runner, and an SSH user permitted to run Docker. No Ansible is involved.

## Dashboard

The Traefik dashboard is exposed without authentication over HTTP at
`http://<host-ip>/dashboard/`.

## Secrets

| Variable | 1Password reference | Purpose |
|---|---|---|
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare DNS-01 API token |
| `ACME_EMAIL` | `op://network/acme/traefik-email` | Let's Encrypt account email |

The 1Password item/path names can be changed in `.env.template` without changing the workflow.
