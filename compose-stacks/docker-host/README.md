# Docker host platform stack

This is the host-level platform deployed to every Docker host with the platform workflow. It is intentionally separate from application stacks and is excluded from application reconciliation.

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

Changes under `compose-stacks/docker-host/` automatically run `.github/workflows/deploy-docker-platform.yaml` for every inventory workload host with `host_roles: deploy`. Manual dispatch reconciles that same complete host set. The workflow:

1. Validates the inventory and Compose configuration before connecting to any host.
2. Connects the runner to Tailscale.
3. Creates `proxy` if it does not exist; the platform workflow owns this external network.
4. Syncs this directory to a unique private staging directory under `/etc/compose-stacks/.staging/`.
5. Resolves `.env.template` through 1Password directly into staging.
6. Validates the staged Compose project, publishes it only after validation, and reconciles Traefik with Docker Compose.

A host-specific file named `docker-compose.<host>.yaml` is copied to the staged directory as `docker-compose.override.yaml` when it exists. This lets every host use the same automatic Compose merge command. The `traefik-lxc` host therefore uses `docker-compose.traefik-lxc.yaml` to mount additional files from `traefik/dynamic/`; other hosts receive the same source tree but have no override file.

The operation is safe to repeat for every host. A host needs Docker, Tailscale connectivity from the runner, and an SSH user permitted to run Docker. Ansible prepares Docker, Tailscale, the deployment user, and the required host directories; this workflow deploys and maintains the platform stack.

## Dashboard

The Traefik dashboard is exposed without authentication over HTTP at
`http://<host-ip>/dashboard/`.

## Secrets

| Variable | 1Password reference | Purpose |
|---|---|---|
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare DNS-01 API token |
| `ACME_EMAIL` | `op://network/acme/traefik-email` | Let's Encrypt account email |

The 1Password item/path names can be changed in `.env.template` without changing the workflow.
