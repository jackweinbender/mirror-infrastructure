# Traefik

See [`../OPERATIONS.md`](../OPERATIONS.md) for the repository-wide Compose
stack and deployment process.

Host-level Traefik runs as a normal assigned Compose stack. It provides HTTP and HTTPS entrypoints, Docker label discovery, the dashboard, ACME DNS-01 certificates, and file-provider routes for services outside Docker discovery.

Traefik joins the external `proxy` network created by `docker-networking`. Application stacks must join that network and set `traefik.enable=true` to be discovered.

## Deployment

Traefik is currently assigned to each Docker deploy host:

```text
deployments/
  <host>/
    .env.template
```

The `traefik-lxc` deployment also has a Compose overlay that mounts dynamic routes from `traefik/dynamic/`. Add or remove a deployment directory to change where Traefik runs.

The normal `deploy.yaml` workflow reconciles `docker-networking` first, then deploys assigned application stacks including Traefik.

## Dashboard

The dashboard is exposed without authentication over HTTP at `http://<host-ip>/dashboard/`.

## Secrets

| Variable | 1Password reference | Purpose |
|---|---|---|
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare DNS-01 API token |
| `ACME_EMAIL` | `op://network/acme/traefik-email` | Let's Encrypt account email |

The 1Password item/path names can be changed in `.env.template` without changing the workflow.
