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

## DNS convention for LAN-backed services

**Convention: every service exposed through a host-level Traefik gateway needs
both records below.** Cloudflare DNS is public, but the gateway record
intentionally contains a private LAN address:

1. An `A` record for the gateway hostname, such as
   `<gateway>.weinbender.io` → the gateway's LAN IPv4 address.
2. A `CNAME` record for the service hostname, such as
   `<service>.weinbender.io` → `<gateway>.weinbender.io`.

Create the gateway A record as soon as the gateway LXC is provisioned and its
LAN IPv4 address is known. This is a provisioning follow-up, not an Ansible
task; do not try to automate it through Ansible. The service CNAME is added
later when the service is assigned to that gateway.

The current repository convention is to use an unproxied record pair
(`proxied = false`):

- `<gateway>.weinbender.io` → an `A` record for the gateway's LAN IPv4 address.
- `<service>.weinbender.io` → a `CNAME` targeting
  `<gateway>.weinbender.io`.

Most Cloudflare DNS records are currently managed outside Terraform, in the
Cloudflare dashboard. Records that are managed in Terraform belong in
`terraform/cloudflare/dns.tf`; do not assume that file contains the complete
zone. The service's Traefik router must use the same
`<service>.weinbender.io` hostname. Do not point a LAN-backed service directly
to the tunnel target; tunnel CNAMEs are a separate ingress path.

## Dashboard

The dashboard is exposed without authentication over HTTP at `http://<host-ip>/dashboard/`.

## Secrets

| Variable | 1Password reference | Purpose |
|---|---|---|
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare DNS-01 API token |
| `ACME_EMAIL` | `op://network/acme/traefik-email` | Let's Encrypt account email |

The 1Password item/path names can be changed in `.env.template` without changing the workflow.
